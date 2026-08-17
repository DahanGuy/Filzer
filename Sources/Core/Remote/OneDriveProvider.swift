import Foundation

struct OneDriveProvider: RemoteFileProvider {
	enum OneDriveError: LocalizedError {
		case httpStatus(Int, String)
		case malformedResponse
		case noRedirectLocation

		var errorDescription: String? {
			switch self {
			case .httpStatus(let code, let body): return "OneDrive returned an error (\(code)): \(body)"
			case .malformedResponse: return "OneDrive sent a response Filzer couldn't understand."
			case .noRedirectLocation: return "OneDrive didn't provide a download location for this file."
			}
		}
	}

	static let redirectURI = "msauth.com.guy.filzer://auth"

	static let endpoints = OAuthEndpoints(
		authorizationURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
		tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
		redirectURI: redirectURI,
		scope: "offline_access Files.ReadWrite",
		extraAuthorizeParams: [:]
	)

	private let sessionManager: OAuthSessionManager

	init(connection: RemoteConnection) {
		sessionManager = OAuthSessionManager(
			connectionID: connection.id,
			clientID: connection.clientID ?? "",
			endpoints: Self.endpoints
		)
	}

	func listDirectory(at path: String) async throws -> [RemoteItem] {
		var items: [RemoteItem] = []
		var url: URL? = childrenURL(for: path)
		while let currentURL = url {
			let json = try await graphJSON(url: currentURL)
			guard let values = json["value"] as? [[String: Any]] else { throw OneDriveError.malformedResponse }
			items.append(contentsOf: values.compactMap { Self.remoteItem(from: $0, parentPath: path) })
			url = (json["@odata.nextLink"] as? String).flatMap(URL.init(string:))
		}
		return items
	}

	func readFile(at path: String) async throws -> Data {
		var request = URLRequest(url: itemURL(for: path, suffix: ":/content"))
		let token = try await sessionManager.validAccessToken()
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		let (data, response) = try await URLSession.shared.data(for: request)
		try Self.requireSuccess(response, data: data)
		return data
	}

	func writeFile(at path: String, data: Data) async throws {
		var request = URLRequest(url: itemURL(for: path, suffix: ":/content"))
		request.httpMethod = "PUT"
		request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
		request.httpBody = data
		_ = try await authorizedData(&request)
	}

	func createDirectory(at path: String) async throws {
		let (parentPath, name) = Self.splitPath(path)
		var request = URLRequest(url: childrenURL(for: parentPath))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: [
			"name": name,
			"folder": [String: Any](),
			"@microsoft.graph.conflictBehavior": "fail",
		])
		_ = try await authorizedData(&request)
	}

	func delete(at path: String) async throws {
		var request = URLRequest(url: itemURL(for: path, suffix: ""))
		request.httpMethod = "DELETE"
		_ = try await authorizedData(&request)
	}

	func move(from source: String, to destination: String) async throws {
		let (destinationParent, destinationName) = Self.splitPath(destination)
		let encodedParent = Self.percentEncodedPath(destinationParent)
		let parentPath = encodedParent.isEmpty ? "/drive/root" : "/drive/root:\(encodedParent)"
		var request = URLRequest(url: itemURL(for: source, suffix: ""))
		request.httpMethod = "PATCH"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: [
			"parentReference": ["path": parentPath],
			"name": destinationName,
		])
		_ = try await authorizedData(&request)
	}

	private static let base = "https://graph.microsoft.com/v1.0/me/drive"

	private func itemURL(for path: String, suffix: String) -> URL {
		let encoded = Self.percentEncodedPath(path)
		let url = encoded.isEmpty ? "\(Self.base)/root\(suffix)" : "\(Self.base)/root:\(encoded)\(suffix)"
		return URL(string: url)!
	}

	private func childrenURL(for path: String) -> URL {
		let encoded = Self.percentEncodedPath(path)
		let url = encoded.isEmpty ? "\(Self.base)/root/children" : "\(Self.base)/root:\(encoded):/children"
		return URL(string: url)!
	}

	private static func percentEncodedPath(_ path: String) -> String {
		let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard !trimmed.isEmpty else { return "" }
		let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/:"))
		let segments = trimmed.split(separator: "/").map { segment in
			String(segment).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(segment)
		}
		return "/" + segments.joined(separator: "/")
	}

	private static func splitPath(_ path: String) -> (parent: String, name: String) {
		let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let components = trimmed.split(separator: "/")
		guard let name = components.last else { return ("/", path) }
		let parent = components.dropLast().joined(separator: "/")
		return (parent.isEmpty ? "/" : "/" + parent, String(name))
	}

	private func graphJSON(url: URL) async throws -> [String: Any] {
		var request = URLRequest(url: url)
		let data = try await authorizedData(&request)
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw OneDriveError.malformedResponse
		}
		return json
	}

	@discardableResult
	private func authorizedData(_ request: inout URLRequest) async throws -> Data {
		let token = try await sessionManager.validAccessToken()
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		let (data, response) = try await URLSession.shared.data(for: request)
		try Self.requireSuccess(response, data: data)
		return data
	}

	private static func requireSuccess(_ response: URLResponse, data: Data) throws {
		guard let httpResponse = response as? HTTPURLResponse else { throw OneDriveError.malformedResponse }
		guard (200...299).contains(httpResponse.statusCode) else {
			throw OneDriveError.httpStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
		}
	}

	private static func remoteItem(from json: [String: Any], parentPath: String) -> RemoteItem? {
		guard let name = json["name"] as? String else { return nil }
		let isDirectory = json["folder"] != nil
		let size = (json["size"] as? NSNumber)?.int64Value ?? 0
		let modifiedAt = (json["lastModifiedDateTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
		let path = parentPath.hasSuffix("/") ? parentPath + name : parentPath + "/" + name
		return RemoteItem(name: name, path: path, isDirectory: isDirectory, size: size, modifiedAt: modifiedAt)
	}
}
