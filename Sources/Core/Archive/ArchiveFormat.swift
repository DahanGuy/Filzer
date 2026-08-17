import Foundation

enum ArchiveFormat {
	case zip
	case rar
	case tar
	case tarGz
	case tarBz2
	case gzip
	case bzip2
	case xz
	case sevenZip

	static func detect(from url: URL) -> ArchiveFormat {
		let name = url.lastPathComponent.lowercased()
		if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
			return .tarGz
		}
		if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") {
			return .tarBz2
		}
		switch url.pathExtension.lowercased() {
		case "zip": return .zip
		case "rar": return .rar
		case "tar": return .tar
		case "gz": return .gzip
		case "bz2": return .bzip2
		case "xz": return .xz
		case "7z": return .sevenZip
		default: return .zip
		}
	}

	static func isArchive(_ url: URL) -> Bool {
		let name = url.lastPathComponent.lowercased()
		if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return true }
		if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") { return true }
		switch url.pathExtension.lowercased() {
		case "zip", "rar", "tar", "gz", "bz2", "xz", "7z": return true
		default: return false
		}
	}

	static func baseName(for url: URL) -> String {
		let name = url.lastPathComponent
		let lowercased = name.lowercased()
		if lowercased.hasSuffix(".tar.gz") {
			return String(name.dropLast(".tar.gz".count))
		}
		if lowercased.hasSuffix(".tgz") {
			return String(name.dropLast(".tgz".count))
		}
		if lowercased.hasSuffix(".tar.bz2") {
			return String(name.dropLast(".tar.bz2".count))
		}
		if lowercased.hasSuffix(".tbz2") {
			return String(name.dropLast(".tbz2".count))
		}
		return url.deletingPathExtension().lastPathComponent
	}

	static let creatable: [ArchiveFormat] = [.zip, .tar, .tarGz, .tarBz2]

	var title: String {
		switch self {
		case .zip: return "Zip"
		case .rar: return "RAR"
		case .tar: return "Tar"
		case .tarGz: return "Tar.gz"
		case .tarBz2: return "Tar.bz2"
		case .gzip: return "Gzip"
		case .bzip2: return "Bzip2"
		case .xz: return "XZ"
		case .sevenZip: return "7-Zip"
		}
	}

	var fileExtension: String {
		switch self {
		case .zip: return "zip"
		case .rar: return "rar"
		case .tar: return "tar"
		case .tarGz: return "tar.gz"
		case .tarBz2: return "tar.bz2"
		case .gzip: return "gz"
		case .bzip2: return "bz2"
		case .xz: return "xz"
		case .sevenZip: return "7z"
		}
	}
}
