import Foundation

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

	var supportsSecureToggle: Bool {
		self == .webDAV || self == .ftp
	}

	var isOAuthBased: Bool {
		switch self {
		case .dropbox, .googleDrive, .oneDrive: return true
		case .webDAV, .ftp, .smb: return false
		}
	}
}

struct RemoteConnection: Codable, Identifiable, Equatable {
	let id: UUID
	var kind: RemoteConnectionKind
	var displayName: String
	var host: String
	var port: Int
	var username: String
	var useSecureConnection: Bool
	var basePath: String
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

	var rootURL: URL {
		RemoteURL.url(connectionID: id, path: basePath)
	}
}
