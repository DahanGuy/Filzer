import Foundation

/// A configured network location — WebDAV, FTP, or SMB.
enum RemoteConnectionKind: String, Codable, CaseIterable, Identifiable {
	case webDAV
	case ftp
	case smb

	var id: String { rawValue }

	var title: String {
		switch self {
		case .webDAV: return "WebDAV"
		case .ftp: return "FTP"
		case .smb: return "SMB"
		}
	}

	var systemImageName: String {
		switch self {
		case .webDAV: return "cloud"
		case .ftp: return "arrow.up.arrow.down.circle"
		case .smb: return "network"
		}
	}

	var defaultPort: Int {
		switch self {
		case .webDAV: return 443
		case .ftp: return 21
		case .smb: return 445
		}
	}

	/// Whether "Secure Connection" (HTTPS/FTPS) is offered as a toggle when adding a
	/// connection of this kind — SMB2/3 negotiates its own transport security, so the
	/// toggle doesn't apply to it.
	var supportsSecureToggle: Bool {
		self != .smb
	}
}

/// A configured network location a user has added. Credentials are never stored here;
/// they live in the Keychain (`KeychainStore`), keyed by `id.uuidString`, so this type
/// is safe to persist as plain `UserDefaults` JSON.
struct RemoteConnection: Codable, Identifiable, Equatable {
	let id: UUID
	var kind: RemoteConnectionKind
	var displayName: String
	var host: String
	var port: Int
	var username: String
	/// HTTPS for WebDAV, FTPS for FTP. Ignored for SMB.
	var useSecureConnection: Bool
	/// The path/share browsing starts at. For SMB this is `"ShareName/optional/path"`;
	/// for WebDAV/FTP it's a normal remote path such as `"/"` or `"/dav/files"`.
	var basePath: String

	init(
		id: UUID = UUID(),
		kind: RemoteConnectionKind,
		displayName: String,
		host: String,
		port: Int,
		username: String,
		useSecureConnection: Bool,
		basePath: String
	) {
		self.id = id
		self.kind = kind
		self.displayName = displayName
		self.host = host
		self.port = port
		self.username = username
		self.useSecureConnection = useSecureConnection
		self.basePath = basePath
	}

	/// The root URL this connection browses to — pass to `FileBrowserView(rootURL:)`.
	var rootURL: URL {
		RemoteURL.url(connectionID: id, path: basePath)
	}
}
