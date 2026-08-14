import Foundation

/// A local, synthetic URL scheme used to address remote items uniformly through
/// `FileSystem.current` — `filzer-remote://<connection-uuid>/<remote-path>`.
/// `SandboxedFileSystemEngine` recognizes this scheme and routes the operation to the
/// matching `RemoteFileProvider` instead of touching `FileManager`; every other type in
/// the app (views, `FileNode`, viewers reading through the engine) never needs to know
/// the difference.
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
