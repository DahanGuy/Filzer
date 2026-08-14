import Foundation

/// Persists one `OAuthTokenSet` per connection in the Keychain, alongside where
/// `RemoteConnectionsStore` already keeps WebDAV/FTP/SMB passwords — an OAuth token
/// is just as sensitive as a password and must never land in `UserDefaults`.
enum OAuthTokenStore {
	private static func key(for connectionID: UUID) -> String {
		"oauth.\(connectionID.uuidString)"
	}

	static func save(_ tokens: OAuthTokenSet, for connectionID: UUID) {
		guard let data = try? JSONEncoder().encode(tokens), let json = String(data: data, encoding: .utf8) else { return }
		KeychainStore.set(json, forKey: key(for: connectionID))
	}

	static func load(for connectionID: UUID) -> OAuthTokenSet? {
		guard let json = KeychainStore.get(key(for: connectionID)), let data = json.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(OAuthTokenSet.self, from: data)
	}

	static func remove(for connectionID: UUID) {
		KeychainStore.remove(key(for: connectionID))
	}

	static func isSignedIn(_ connectionID: UUID) -> Bool {
		load(for: connectionID) != nil
	}
}

/// Shared "get a currently-valid access token, refreshing if needed" bookkeeping —
/// every OAuth-backed `RemoteFileProvider` (Dropbox/Google Drive/OneDrive) composes
/// this instead of duplicating refresh logic three times. An `actor` so a burst of
/// concurrent requests against one connection triggers at most one refresh, not one
/// per request.
actor OAuthSessionManager {
	private let connectionID: UUID
	private let clientID: String
	private let endpoints: OAuthEndpoints
	private var cached: OAuthTokenSet?

	init(connectionID: UUID, clientID: String, endpoints: OAuthEndpoints) {
		self.connectionID = connectionID
		self.clientID = clientID
		self.endpoints = endpoints
	}

	func validAccessToken() async throws -> String {
		let current = cached ?? OAuthTokenStore.load(for: connectionID)
		guard let current else {
			throw OAuthClient.OAuthError.tokenExchangeFailed("Not signed in.")
		}
		guard current.isExpired else {
			cached = current
			return current.accessToken
		}
		guard let refreshToken = current.refreshToken else {
			throw OAuthClient.OAuthError.tokenExchangeFailed("Your signed-in session expired — sign in again.")
		}
		let refreshed = try await OAuthClient.refresh(clientID: clientID, endpoints: endpoints, refreshToken: refreshToken)
		OAuthTokenStore.save(refreshed, for: connectionID)
		cached = refreshed
		return refreshed.accessToken
	}
}
