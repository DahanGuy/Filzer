import Foundation

/// Every archive format Filzer can extract. Creation is always `.zip`, matching Filza's
/// own "Create ZIP" behavior — none of the others are meant to be authored, only opened.
enum ArchiveFormat {
	case zip
	case rar
	case tar
	case tarGz
	case gzip
	case bzip2
	case xz
	case sevenZip

	static func detect(from url: URL) -> ArchiveFormat {
		let name = url.lastPathComponent.lowercased()
		if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
			return .tarGz
		}
		switch url.pathExtension.lowercased() {
		case "rar": return .rar
		case "tar": return .tar
		case "gz": return .gzip
		case "bz2", "tbz2": return .bzip2
		case "xz": return .xz
		case "7z": return .sevenZip
		default: return .zip
		}
	}

	/// Whether `url`'s name looks like a supported archive — the single source of
	/// truth `FileClassifier` (icon/viewer routing) and the "Extract Here" context
	/// menu action both defer to, so a newly-supported format only needs listing once.
	static func isArchive(_ url: URL) -> Bool {
		let name = url.lastPathComponent.lowercased()
		if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return true }
		switch url.pathExtension.lowercased() {
		case "zip", "rar", "tar", "gz", "bz2", "tbz2", "xz", "7z": return true
		default: return false
		}
	}

	/// The archive's name with its extension(s) stripped, for naming an "Extract
	/// Here"/"Extract All" destination folder — e.g. `archive.tar.gz` -> `archive`, not
	/// `archive.tar` (which plain `deletingPathExtension()` would produce).
	static func baseName(for url: URL) -> String {
		let name = url.lastPathComponent
		let lowercased = name.lowercased()
		if lowercased.hasSuffix(".tar.gz") {
			return String(name.dropLast(".tar.gz".count))
		}
		if lowercased.hasSuffix(".tgz") {
			return String(name.dropLast(".tgz".count))
		}
		return url.deletingPathExtension().lastPathComponent
	}
}
