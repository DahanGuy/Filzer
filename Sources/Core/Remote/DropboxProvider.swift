import Foundation

struct DropboxProvider: RemoteFileProvider {
	enum DropboxError: LocalizedError {
		case httpStatus(Int, String)
		case malformedResponse

		var errorDescription: String? {
			switch self {
			case .httpStatus(let code, let body): return "Dropbox returned an error (\(code)): \(body)"
			case .malformedResponse: return "Dropbox sent a response Filzer couldn't understand."
			}
		}
	}

	static let redirectURI = "com.guy.filzer.dropbox://oauth/callback"

	static let endpoints = OAuthEndpoints(
		authorizationURL: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
		tokenURL: URL(string: "https://api.dropboxapi.com/oauth2/token")!,
		redirectURI: redirectURI,
		scope: "",
		extraAuthorizeParams: ["token_access_type": "offline"]
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
		var entries: [RemoteItem] = []
		var json = try await rpc("list_folder", body: ["path": path == "/" ? "" : path, "recursive": false])
		while true {
			guard let rawEntries = json["entries"] as? [[String: Any]] else { throw DropboxError.malformedResponse }
			entries.append(contentsOf: rawEntries.compactMap(Self.remoteItem(from:)))
			guard json["has_more"] as? Bool == true, let cursor = json["cursor"] as? String else { break }
			json = try await rpc("list_folder/continue", body: ["cursor": cursor])
		}
		return entries
	}

	func readFile(at path: String) async throws -> Data {
		try await content(route: "download", arg: ["path": path], body: nil)
	}

	func writeFile(at path: String, data: Data) async throws {
		_ = try await content(route: "upload", arg: ["path": path, "mode": "overwrite", "autorename": false], body: data)
	}

	func createDirectory(at path: String) async throws {
		_ = try await rpc("create_folder_v2", body: ["path": path, "autorename": false])
	}

	func delete(at path: String) async throws {
		_ = try await rpc("delete_v2", body: ["path": path])
	}

	func move(from source: String, to destination: String) async throws {
		_ = try await rpc("move_v2", body: ["from_path": source, "to_path": destination, "autorename": false])
	}

	private func rpc(_ route: String, body: [String: Any]) async throws -> [String: Any] {
		var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/\(route)")!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: body)
		let data = try await authorizedRequest(&request)
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw DropboxError.malformedResponse
		}
		return json
	}

	@discardableResult
	private func content(route: String, arg: [String: Any], body: Data?) async throws -> Data {
		var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/\(route)")!)
		request.httpMethod = "POST"
		let argData = try JSONSerialization.data(withJSONObject: arg)
		request.setValue(Self.asciiEscaped(argData), forHTTPHeaderField: "Dropbox-API-Arg")
		if let body {
			request.httpBody = body
			request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
		}
		return try await authorizedRequest(&request)
	}

	private func authorizedRequest(_ request: inout URLRequest) async throws -> Data {
		let token = try await sessionManager.validAccessToken()
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else { throw DropboxError.malformedResponse }
		guard (200...299).contains(httpResponse.statusCode) else {
			throw DropboxError.httpStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
		}
		return data
	}

	private static func asciiEscaped(_ jsonData: Data) -> String {
		let text = String(decoding: jsonData, as: UTF8.self)
		var result = ""
		for scalar in text.unicodeScalars {
			if scalar.value >= 0x20, scalar.value <= 0x7E {
				result.unicodeScalars.append(scalar)
			} else {
				result += String(format: "\\u%04x", scalar.value)
			}
		}
		return result
	}

	private static func remoteItem(from entry: [String: Any]) -> RemoteItem? {
		guard let tag = entry[".tag"] as? String, tag != "deleted", let name = entry["name"] as? String else { return nil }
		let path = (entry["path_display"] as? String) ?? (entry["path_lower"] as? String) ?? name
		let isDirectory = tag == "folder"
		let size = (entry["size"] as? NSNumber)?.int64Value ?? 0
		let modifiedAt = (entry["server_modified"] as? String).flatMap(Self.dropboxDateFormatter.date(from:))
		return RemoteItem(name: name, path: path, isDirectory: isDirectory, size: size, modifiedAt: modifiedAt)
	}

	private static let dropboxDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
		return formatter
	}()
}
