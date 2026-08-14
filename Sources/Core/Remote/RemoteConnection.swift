import Foundation

/// A configured network location — WebDAV, FTP, SMB, or an OAuth-backed cloud account.
enum RemoteConnectionKind: String, Codable, CaseIterable, Identifiable {
	case webDAV
	case ftp
	case smb
	case dropbox
	case googleDrive
	case oneDrive

	var id: String { rawValue }

	var title: String {
		switch self {
		case .webDAV: return "WebDAV"
		case .ftp: return "FTP"
		case .smb: return "SMB"
		case .dropbox: return "Dropbox"
		case .googleDrive: return "Google Drive"
		case .oneDrive: return "OneDrive"
		}
	}

	var systemImageName: String {
		switch self {
		case .webDAV: return "cloud"
		case .ftp: return "arrow.up.arrow.down.circle"
		case .smb: return "network"
		case .dropbox: return "shippingbox"
		case .googleDrive: return "triangle"
		case .oneDrive: return "cloud.fill"
		}
	}

	var defaultPort: Int {
		switch self {
		case .webDAV: return 443
		case .ftp: return 21
		case .smb: return 445
		case .dropbox, .googleDrive, .oneDrive: return 443
		}
	}

	/// Whether "Secure Connection" (HTTPS/FTPS) is offered as a toggle when adding a
	/// connection of this kind — SMB2/3 negotiates its own transport security, and the
	/// cloud kinds are always HTTPS, so the toggle only applies to WebDAV/FTP.
	var supportsSecureToggle: Bool {
		self == .webDAV || self == .ftp
	}

	/// OAuth-backed kinds sign in through the provider's own web page with a
	/// user-supplied Client ID, instead of a host/port/username/password form —
	/// `AddRemoteLocationView` branches its whole form on this.
	var isOAuthBased: Bool {
		switch self {
		case .dropbox, .googleDrive, .oneDrive: return true
		case .webDAV, .ftp, .smb: return false
		}
	}
}

/// A configured network location a user has added. Credentials are never stored here:
/// WebDAV/FTP/SMB passwords and OAuth tokens both live in the Keychain (`KeychainStore`
/// / `OAuthTokenStore`, both keyed by `id.uuidString`), so this type is safe to persist
/// as plain `UserDefaults` JSON.
struct RemoteConnection: Codable, Identifiable, Equatable {
	let id: UUID
	var kind: RemoteConnectionKind
	var displayName: String
	/// Host/port/username/useSecureConnection apply only to `WebDAV`/`FTP`/`SMB` —
	/// unused (left as the type's defaults) for OAuth-backed kinds.
	var host: String
	var port: Int
	var username: String
	/// HTTPS for WebDAV, FTPS for FTP. Ignored for SMB and the OAuth kinds.
	var useSecureConnection: Bool
	/// The path/share browsing starts at. For SMB this is `"ShareName/optional/path"`;
	/// for WebDAV/FTP it's a normal remote path such as `"/"` or `"/dav/files"`; for
	/// the OAuth kinds it's a path within the user's own cloud storage, normally `"/"`.
	var basePath: String
	/// The user's own OAuth app Client ID — `nil` for `WebDAV`/`FTP`/`SMB`. Filzer
	/// never ships with one: a redistributed, unsigned IPA can't hold a client secret
	/// safely, and each provider's redirect URI is tied to a specific registered app.
	var clientID: String?

	init(
		id: UUID = UUID(),
		kind: RemoteConnectionKind,
		displayName: String,
		host: String = "",
		port: Int = 0,
		username: String = "",
		useSecureConnection: Bool = true,
		basePath: String = "/",
		clientID: String? = nil
	) {
		self.id = id
		self.kind = kind
		self.displayName = displayName
		self.host = host
		self.port = port
		self.username = username
		self.useSecureConnection = useSecureConnection
		self.basePath = basePath
		self.clientID = clientID
	}

	/// The root URL this connection browses to — pass to `FileBrowserView(rootURL:)`.
	var rootURL: URL {
		RemoteURL.url(connectionID: id, path: basePath)
	}
}
