import Foundation

enum RemoteURL {
	static let scheme = "filzer-remote"

	static func url(connectionID: UUID, path: String) -> URL {
		var components = URLComponents()
		components.scheme = scheme
		components.host = connectionID.uuidString
		components.path = path.hasPrefix("/") ? path : "/" + path
		return components.url ?? URL(string: "\(scheme)://\(connectionID.uuidString)/")!
	}

	static func connectionID(from url: URL) -> UUID? {
		guard url.scheme == scheme, let host = url.host else { return nil }
		return UUID(uuidString: host)
	}

	static func remotePath(from url: URL) -> String {
		url.path.isEmpty ? "/" : url.path
	}

	static func isRemote(_ url: URL) -> Bool {
		url.scheme == scheme
	}
}
