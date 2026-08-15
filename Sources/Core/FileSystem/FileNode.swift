import Foundation

/// Immutable snapshot of a single filesystem entry as reported by a `FileSystemEngine`.
///
/// `FileNode` never mutates in place — every file operation returns fresh nodes,
/// which keeps SwiftUI's diffing simple and avoids stale-state bugs after a move/rename.
struct FileNode: Identifiable, Hashable {
	enum Kind: Hashable {
		case file
		case directory
		case symbolicLink
	}

	let url: URL
	let name: String
	let kind: Kind
	let size: Int64
	let createdAt: Date?
	let modifiedAt: Date?
	let posixPermissions: Int16
	let ownerAccountName: String?
	let groupOwnerAccountName: String?
	/// Resolved target of a symbolic link. `nil` for every other kind.
	let symbolicLinkDestination: URL?
	/// Whether a symlink's target is itself a directory — meaningless for every other
	/// kind (defaults `false`). A cheap `fileExists(atPath:isDirectory:)` check, not a
	/// full recursive `FileNode.make` re-classification of the target (which risks
	/// statting deep chains just to render a listing) — used so folder-symlinks sort
	/// and navigate the same as real folders instead of being lumped in with files.
	let symbolicLinkTargetIsDirectory: Bool
	let isHidden: Bool

	var id: URL { url }
	var pathExtension: String { url.pathExtension }
	var isDirectory: Bool { kind == .directory }
	var isSymbolicLink: Bool { kind == .symbolicLink }
	/// Whether this node should group with folders in a listing — real directories,
	/// plus symlinks whose target is itself a directory.
	var sortsAsDirectory: Bool { isDirectory || (isSymbolicLink && symbolicLinkTargetIsDirectory) }

	/// Builds a snapshot for a single path.
	///
	/// Symlinks are detected via `destinationOfSymbolicLink` *before* reading any other
	/// attribute. That call is the only unambiguous way Foundation offers to tell a link
	/// apart from the file it points to — `attributesOfItem(atPath:)` follows the link and
	/// would misreport a symlink-to-directory as a plain directory. Classifying links up
	/// front is also what keeps every recursive traversal in this app (size, search,
	/// delete) cycle-safe without extra bookkeeping: a symlink is always a leaf.
	static func make(at url: URL) throws -> FileNode {
		let fm = FileManager.default
		let path = url.path
		let name = url.lastPathComponent
		let isHidden = name.hasPrefix(".")

		if let destinationPath = try? fm.destinationOfSymbolicLink(atPath: path) {
			let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
			let destinationURL = destinationPath.hasPrefix("/")
				? URL(fileURLWithPath: destinationPath)
				: URL(fileURLWithPath: destinationPath, relativeTo: url.deletingLastPathComponent())
			let standardizedDestination = destinationURL.standardizedFileURL
			var isTargetDirectory: ObjCBool = false
			let targetIsDirectory = fm.fileExists(atPath: standardizedDestination.path, isDirectory: &isTargetDirectory) && isTargetDirectory.boolValue
			return FileNode(
				url: url, name: name, kind: .symbolicLink,
				size: (attrs[.size] as? NSNumber)?.int64Value ?? 0,
				createdAt: attrs[.creationDate] as? Date,
				modifiedAt: attrs[.modificationDate] as? Date,
				posixPermissions: (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0,
				ownerAccountName: attrs[.ownerAccountName] as? String,
				groupOwnerAccountName: attrs[.groupOwnerAccountName] as? String,
				symbolicLinkDestination: standardizedDestination,
				symbolicLinkTargetIsDirectory: targetIsDirectory,
				isHidden: isHidden
			)
		}

		let attrs = try fm.attributesOfItem(atPath: path)
		let kind: Kind = (attrs[.type] as? FileAttributeType) == .typeDirectory ? .directory : .file
		return FileNode(
			url: url, name: name, kind: kind,
			size: (attrs[.size] as? NSNumber)?.int64Value ?? 0,
			createdAt: attrs[.creationDate] as? Date,
			modifiedAt: attrs[.modificationDate] as? Date,
			posixPermissions: (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0,
			ownerAccountName: attrs[.ownerAccountName] as? String,
			groupOwnerAccountName: attrs[.groupOwnerAccountName] as? String,
			symbolicLinkDestination: nil,
			symbolicLinkTargetIsDirectory: false,
			isHidden: isHidden
		)
	}
}

/// Synthesizes nodes for remote (WebDAV/FTP/SMB) items, which have no POSIX
/// permissions or ownership — `SandboxedFileSystemEngine` is the only caller.
extension FileNode {
	static func remote(url: URL, item: RemoteItem) -> FileNode {
		FileNode(
			url: url, name: item.name, kind: item.isDirectory ? .directory : .file,
			size: item.size,
			createdAt: nil,
			modifiedAt: item.modifiedAt,
			posixPermissions: item.isDirectory ? 0o755 : 0o644,
			ownerAccountName: nil,
			groupOwnerAccountName: nil,
			symbolicLinkDestination: nil,
			symbolicLinkTargetIsDirectory: false,
			isHidden: item.name.hasPrefix(".")
		)
	}

	/// A connection's own root — always a directory, and with no listable parent to
	/// stat it against (unlike every other remote path).
	static func remoteRoot(url: URL) -> FileNode {
		let name = url.lastPathComponent
		return FileNode(
			url: url, name: name.isEmpty ? "/" : name, kind: .directory,
			size: 0,
			createdAt: nil,
			modifiedAt: nil,
			posixPermissions: 0o755,
			ownerAccountName: nil,
			groupOwnerAccountName: nil,
			symbolicLinkDestination: nil,
			symbolicLinkTargetIsDirectory: false,
			isHidden: false
		)
	}
}

/// A single entry inside a browsable archive (zip, rar, tar, gzip, bzip2, xz, 7z),
/// reported without extracting the archive to disk.
struct ArchiveEntry: Identifiable, Hashable {
	let path: String
	let isDirectory: Bool
	let uncompressedSize: Int64
	let compressedSize: Int64

	var id: String { path }
	var name: String { (path as NSString).lastPathComponent }
}

/// Free/total space for the volume backing a given URL.
struct VolumeInfo: Hashable {
	let totalCapacity: Int64
	let availableCapacity: Int64
	var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
}
