import Foundation

/// Google Drive client via Drive API v3 + OAuth 2.0 authorization-code+PKCE.
///
/// Unlike WebDAV/Dropbox/OneDrive, Drive has no path strings at all — every item is an
/// opaque `id` with a single `parents` id forming an ID graph, and names aren't unique
/// within a folder. This actor resolves Filzer's path strings to Drive folder ids by
/// walking segment-by-segment and caching the result, seeded with `"/" -> "root"` (the
/// documented alias for My Drive's own root — no initial lookup needed). A cache miss
/// or a stale (deleted/moved) id is resolved fresh from its last-known parent.
actor GoogleDriveIDCache {
	private var pathToID: [String: String] = ["/": "root"]

	func cachedID(for path: String) -> String? { pathToID[path] }
	func store(_ id: String, for path: String) { pathToID[path] = id }
	func invalidate(_ path: String) { pathToID[path] = nil }
}

struct GoogleDriveProvider: RemoteFileProvider {
	enum GoogleDriveError: LocalizedError {
		case httpStatus(Int, String)
		case malformedResponse
		case notFound(String)

		var errorDescription: String? {
			switch self {
			case .httpStatus(let code, let body): return "Google Drive returned an error (\(code)): \(body)"
			case .malformedResponse: return "Google Drive sent a response Filzer couldn't understand."
			case .notFound(let path): return "\"\(path)\" couldn't be found in Google Drive."
			}
		}
	}

	/// A fixed, app-wide custom scheme. Google's "iOS" OAuth client type forces a
	/// redirect URI derived from each user's own Client ID (their reversed Client ID),
	/// which a statically-built, bring-your-own-Client-ID IPA can't register in
	/// advance — so Filzer instructs users to register a **Desktop app** type client
	/// instead, which uses this same installed-app flow but accepts an arbitrary
	/// fixed redirect URI (see `AddRemoteLocationView`'s Google instructions).
	static let redirectURI = "com.guy.filzer.google:/oauth2redirect"

	static let endpoints = OAuthEndpoints(
		authorizationURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
		tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
		redirectURI: redirectURI,
		scope: "https://www.googleapis.com/auth/drive",
		extraAuthorizeParams: [:]
	)

	private let sessionManager: OAuthSessionManager
	private let idCache = GoogleDriveIDCache()

	init(connection: RemoteConnection) {
		sessionManager = OAuthSessionManager(
			connectionID: connection.id,
			clientID: connection.clientID ?? "",
			endpoints: Self.endpoints
		)
	}

	func listDirectory(at path: String) async throws -> [RemoteItem] {
		let folderID = try await resolveID(for: path)
		var items: [RemoteItem] = []
		var pageToken: String?
		repeat {
			var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
			components.queryItems = [
				URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
				URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,modifiedTime)"),
				URLQueryItem(name: "pageSize", value: "1000"),
			] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])

			let json = try await authorizedJSON(url: components.url!)
			guard let files = json["files"] as? [[String: Any]] else { throw GoogleDriveError.malformedResponse }
			for file in files {
				guard let node = Self.remoteItem(from: file, parentPath: path) else { continue }
				items.append(node)
				if let id = file["id"] as? String {
					await idCache.store(id, for: node.path)
				}
			}
			pageToken = json["nextPageToken"] as? String
		} while pageToken != nil
		return items
	}

	func readFile(at path: String) async throws -> Data {
		let id = try await resolveID(for: path)
		let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?alt=media")!
		var request = URLRequest(url: url)
		let data = try await authorizedData(&request)
		return data
	}

	func writeFile(at path: String, data: Data) async throws {
		let (parentPath, name) = Self.splitPath(path)
		if let existingID = try? await resolveID(for: path) {
			var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(existingID)?uploadType=media")!)
			request.httpMethod = "PATCH"
			request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
			request.httpBody = data
			_ = try await authorizedData(&request)
			return
		}
		let parentID = try await resolveID(for: parentPath)
		let boundary = "filzer-\(UUID().uuidString)"
		var body = Data()
		body.append(Data("--\(boundary)\r\n".utf8))
		body.append(Data("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
		body.append(try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parentID]]))
		body.append(Data("\r\n--\(boundary)\r\n".utf8))
		body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
		body.append(data)
		body.append(Data("\r\n--\(boundary)--".utf8))

		var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
		request.httpMethod = "POST"
		request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
		request.httpBody = body
		let responseData = try await authorizedData(&request)
		if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any], let id = json["id"] as? String {
			await idCache.store(id, for: path)
		}
	}

	func createDirectory(at path: String) async throws {
		let (parentPath, name) = Self.splitPath(path)
		let parentID = try await resolveID(for: parentPath)
		var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: [
			"name": name,
			"mimeType": "application/vnd.google-apps.folder",
			"parents": [parentID],
		])
		let data = try await authorizedData(&request)
		if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? String {
			await idCache.store(id, for: path)
		}
	}

	func delete(at path: String) async throws {
		let id = try await resolveID(for: path)
		var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)")!)
		request.httpMethod = "DELETE"
		_ = try await authorizedData(&request)
		await idCache.invalidate(path)
	}

	/// Overrides the default read+write fallback — Drive's move is an atomic parent
	/// swap (and optional rename) that works on folders without moving any bytes.
	func move(from source: String, to destination: String) async throws {
		let id = try await resolveID(for: source)
		let (oldParentPath, _) = Self.splitPath(source)
		let (newParentPath, newName) = Self.splitPath(destination)
		let oldParentID = try await resolveID(for: oldParentPath)
		let newParentID = try await resolveID(for: newParentPath)

		var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(id)")!
		components.queryItems = [
			URLQueryItem(name: "addParents", value: newParentID),
			URLQueryItem(name: "removeParents", value: oldParentID),
		]
		var request = URLRequest(url: components.url!)
		request.httpMethod = "PATCH"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
		_ = try await authorizedData(&request)

		await idCache.invalidate(source)
		await idCache.store(id, for: destination)
	}

	// MARK: - Path <-> ID resolution

	private func resolveID(for path: String) async throws -> String {
		if let cached = await idCache.cachedID(for: path) { return cached }
		let normalized = path == "/" ? "/" : path
		guard normalized != "/" else { return "root" }

		let (parentPath, name) = Self.splitPath(normalized)
		let parentID = try await resolveID(for: parentPath)
		let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")

		var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
		components.queryItems = [
			URLQueryItem(name: "q", value: "'\(parentID)' in parents and name='\(escapedName)' and trashed=false"),
			URLQueryItem(name: "fields", value: "files(id)"),
			URLQueryItem(name: "pageSize", value: "1"),
		]
		let json = try await authorizedJSON(url: components.url!)
		guard let files = json["files"] as? [[String: Any]], let id = (files.first?["id"] as? String) else {
			throw GoogleDriveError.notFound(path)
		}
		await idCache.store(id, for: normalized)
		return id
	}

	private static func splitPath(_ path: String) -> (parent: String, name: String) {
		let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let components = trimmed.split(separator: "/")
		guard let name = components.last else { return ("/", path) }
		let parent = components.dropLast().joined(separator: "/")
		return (parent.isEmpty ? "/" : "/" + parent, String(name))
	}

	// MARK: - Transport

	private func authorizedJSON(url: URL) async throws -> [String: Any] {
		var request = URLRequest(url: url)
		let data = try await authorizedData(&request)
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw GoogleDriveError.malformedResponse
		}
		return json
	}

	@discardableResult
	private func authorizedData(_ request: inout URLRequest) async throws -> Data {
		let token = try await sessionManager.validAccessToken()
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else { throw GoogleDriveError.malformedResponse }
		guard (200...299).contains(httpResponse.statusCode) else {
			throw GoogleDriveError.httpStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
		}
		return data
	}

	private static func remoteItem(from json: [String: Any], parentPath: String) -> RemoteItem? {
		guard let name = json["name"] as? String else { return nil }
		let isDirectory = (json["mimeType"] as? String) == "application/vnd.google-apps.folder"
		let size = (json["size"] as? String).flatMap(Int64.init) ?? 0
		let modifiedAt = (json["modifiedTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
		let path = parentPath.hasSuffix("/") ? parentPath + name : parentPath + "/" + name
		return RemoteItem(name: name, path: path, isDirectory: isDirectory, size: size, modifiedAt: modifiedAt)
	}
}
