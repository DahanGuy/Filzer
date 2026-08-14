import Foundation

/// Lazily creates and caches one `RemoteFileProvider` per configured connection.
/// An `actor` so concurrent file operations against the same connection can't race
/// each other into creating duplicate provider instances.
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
		let password = KeychainStore.get(connectionID.uuidString) ?? ""
		let provider: RemoteFileProvider
		switch connection.kind {
		case .webDAV: provider = WebDAVProvider(connection: connection, password: password)
		case .ftp: provider = FTPProvider(connection: connection, password: password)
		case .smb: provider = SMBProvider(connection: connection, password: password)
		}
		providers[connectionID] = provider
		return provider
	}

	/// Drops a cached provider — call after editing or removing a connection so the
	/// next access reconnects with fresh credentials/settings.
	func invalidate(_ connectionID: UUID) {
		providers[connectionID] = nil
	}

	/// Reads `RemoteConnectionsStore`'s persisted JSON directly rather than depending on
	/// the (`@MainActor`) store instance — this registry runs off the main actor and is
	/// reachable from `SandboxedFileSystemEngine`, which has no UI-layer dependencies.
	private static func loadConnection(id: UUID) -> RemoteConnection? {
		guard
			let data = UserDefaults.standard.data(forKey: RemoteConnectionsStore.defaultsKey),
			let connections = try? JSONDecoder().decode([RemoteConnection].self, from: data)
		else { return nil }
		return connections.first { $0.id == id }
	}
}
