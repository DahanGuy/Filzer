import Foundation

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
	let symbolicLinkDestination: URL?
	let symbolicLinkTargetIsDirectory: Bool
	let isHidden: Bool

	var id: URL { url }
	var pathExtension: String { url.pathExtension }
	var isDirectory: Bool { kind == .directory }
	var isSymbolicLink: Bool { kind == .symbolicLink }
	var sortsAsDirectory: Bool { isDirectory || (isSymbolicLink && symbolicLinkTargetIsDirectory) }

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

struct ArchiveEntry: Identifiable, Hashable {
	let path: String
	let isDirectory: Bool
	let uncompressedSize: Int64
	let compressedSize: Int64

	var id: String { path }
	var name: String { (path as NSString).lastPathComponent }
}

struct VolumeInfo: Hashable {
	let totalCapacity: Int64
	let availableCapacity: Int64
	var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
}
