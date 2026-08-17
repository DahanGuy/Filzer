import Foundation

actor RemoteProviderRegistry {
	static let shared = RemoteProviderRegistry()

	private var providers: [UUID: RemoteFileProvider] = [:]

	func provider(for connectionID: UUID) throws -> RemoteFileProvider {
		if let cached = providers[connectionID] {
			return cached
		}
		guard let connection = Self.loadConnection(id: connectionID) else {
			throw FileSystemError.notFound(RemoteURL.url(connectionID: connectionID, path: "/"))
		}
		let provider: RemoteFileProvider
		switch connection.kind {
		case .webDAV: provider = WebDAVProvider(connection: connection, password: KeychainStore.get(connectionID.uuidString) ?? "")
		case .ftp: provider = FTPProvider(connection: connection, password: KeychainStore.get(connectionID.uuidString) ?? "")
		case .smb: provider = SMBProvider(connection: connection, password: KeychainStore.get(connectionID.uuidString) ?? "")
		case .dropbox: provider = DropboxProvider(connection: connection)
		case .googleDrive: provider = GoogleDriveProvider(connection: connection)
		case .oneDrive: provider = OneDriveProvider(connection: connection)
		}
		providers[connectionID] = provider
		return provider
	}

	func invalidate(_ connectionID: UUID) {
		providers[connectionID] = nil
	}

	private static func loadConnection(id: UUID) -> RemoteConnection? {
		guard
			let data = UserDefaults.standard.data(forKey: RemoteConnectionsStore.defaultsKey),
			let connections = try? JSONDecoder().decode([RemoteConnection].self, from: data)
		else { return nil }
		return connections.first { $0.id == id }
	}
}
