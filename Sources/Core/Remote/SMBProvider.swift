import AMSMB2
import Foundation

/// SMB2/3 client backed by AMSMB2 (a Swift wrapper around libsmb2). An `actor` so the
/// lazily-created, share-connected `SMB2Manager` can't be raced into connecting twice
/// by concurrent calls into the same provider.
actor SMBProvider: RemoteFileProvider {
	enum SMBProviderError: LocalizedError {
		case invalidHost
		case connectionFailed(String)

		var errorDescription: String? {
			switch self {
			case .invalidHost: return "This SMB server's address isn't valid."
			case .connectionFailed(let message): return message
			}
		}
	}

	private let connection: RemoteConnection
	private let password: String
	/// `RemoteConnection.basePath` for SMB is `"ShareName/optional/path"` — the share
	/// name is therefore the first component of every full path this provider is ever
	/// given (baked in by `RemoteURL` construction), resolved once here and stripped
	/// before talking to AMSMB2, which addresses files relative to the connected
	/// share's own root.
	private let shareName: String
	private var manager: SMB2Manager?

	init(connection: RemoteConnection, password: String) {
		self.connection = connection
		self.password = password
		self.shareName = (connection.basePath as NSString).pathComponents.first(where: { $0 != "/" }) ?? connection.basePath
	}

	func listDirectory(at path: String) async throws -> [RemoteItem] {
		let manager = try await connectedManager()
		let entries = try await manager.contentsOfDirectory(atPath: sharePath(for: path))
		return entries.compactMap { entry -> RemoteItem? in
			guard let name = entry[.nameKey] as? String, name != ".", name != ".." else { return nil }
			let isDirectory = (entry[.isDirectoryKey] as? NSNumber)?.boolValue ?? false
			let size = (entry[.fileSizeKey] as? NSNumber)?.int64Value ?? 0
			let modifiedAt = entry[.contentModificationDateKey] as? Date
			return RemoteItem(name: name, path: childPath(of: path, name: name), isDirectory: isDirectory, size: size, modifiedAt: modifiedAt)
		}
	}

	func readFile(at path: String) async throws -> Data {
		let manager = try await connectedManager()
		return try await manager.contents(atPath: sharePath(for: path), progress: nil)
	}

	func writeFile(at path: String, data: Data) async throws {
		let manager = try await connectedManager()
		try await manager.write(data: data, toPath: sharePath(for: path), progress: nil)
	}

	func createDirectory(at path: String) async throws {
		let manager = try await connectedManager()
		try await manager.createDirectory(atPath: sharePath(for: path))
	}

	func delete(at path: String) async throws {
		let manager = try await connectedManager()
		try await manager.removeItem(atPath: sharePath(for: path))
	}

	/// Overrides the default read+write fallback — SMB2 rename is a real native verb
	/// and (unlike the default) works correctly on directories too.
	func move(from source: String, to destination: String) async throws {
		let manager = try await connectedManager()
		try await manager.moveItem(atPath: sharePath(for: source), toPath: sharePath(for: destination))
	}

	// `copy` is left on the protocol's default (read+write) — `SandboxedFileSystemEngine`
	// never calls it directly (it always does its own recursive tree-walk for copies so
	// folder copies work uniformly across every provider), so there's nothing to gain
	// from AMSMB2's server-side `copyItem` here.

	// MARK: - Connection

	private func connectedManager() async throws -> SMB2Manager {
		if let manager { return manager }
		var components = URLComponents()
		components.scheme = "smb"
		components.host = connection.host
		components.port = connection.port
		guard let smbURL = components.url else { throw SMBProviderError.invalidHost }
		let credential = URLCredential(user: connection.username, password: password, persistence: .forSession)
		guard let newManager = SMB2Manager(url: smbURL, credential: credential) else {
			throw SMBProviderError.connectionFailed("Couldn't create an SMB connection to \(connection.host).")
		}
		try await newManager.connectShare(name: shareName)
		manager = newManager
		return newManager
	}

	/// Strips this connection's fixed `/ShareName` prefix off a full path, leaving the
	/// share-relative path AMSMB2 expects. The share's own root is `"/"`.
	private func sharePath(for fullPath: String) -> String {
		let prefix = "/\(shareName)"
		guard fullPath.hasPrefix(prefix) else { return fullPath.isEmpty ? "/" : fullPath }
		let remainder = String(fullPath.dropFirst(prefix.count))
		return remainder.isEmpty ? "/" : remainder
	}

	private func childPath(of parentFullPath: String, name: String) -> String {
		parentFullPath.hasSuffix("/") ? parentFullPath + name : parentFullPath + "/" + name
	}
}
