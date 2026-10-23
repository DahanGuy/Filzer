import Foundation

enum RootHelperProtocol {
	static let executableName = "FilzerRootHelper"
}

struct RootNodeRecord: Codable {
	var name: String
	var kind: String
	var size: Int64
	var createdAt: Double?
	var modifiedAt: Double?
	var posixPermissions: Int16
	var ownerAccountName: String?
	var groupOwnerAccountName: String?
	var symbolicLinkDestination: String?
	var symbolicLinkTargetIsDirectory: Bool
	var isHidden: Bool
}

struct RootErrorRecord: Codable {
	var code: Int32
	var message: String
}

extension RootNodeRecord {
	init(node: FileNode) {
		name = node.name
		switch node.kind {
		case .file: kind = "file"
		case .directory: kind = "directory"
		case .symbolicLink: kind = "symlink"
		}
		size = node.size
		createdAt = node.createdAt?.timeIntervalSince1970
		modifiedAt = node.modifiedAt?.timeIntervalSince1970
		posixPermissions = node.posixPermissions
		ownerAccountName = node.ownerAccountName
		groupOwnerAccountName = node.groupOwnerAccountName
		symbolicLinkDestination = node.symbolicLinkDestination?.path
		symbolicLinkTargetIsDirectory = node.symbolicLinkTargetIsDirectory
		isHidden = node.isHidden
	}

	func node(at url: URL) -> FileNode {
		let nodeKind: FileNode.Kind
		switch kind {
		case "directory": nodeKind = .directory
		case "symlink": nodeKind = .symbolicLink
		default: nodeKind = .file
		}
		return FileNode(
			url: url, name: name, kind: nodeKind,
			size: size,
			createdAt: createdAt.map(Date.init(timeIntervalSince1970:)),
			modifiedAt: modifiedAt.map(Date.init(timeIntervalSince1970:)),
			posixPermissions: posixPermissions,
			ownerAccountName: ownerAccountName,
			groupOwnerAccountName: groupOwnerAccountName,
			symbolicLinkDestination: symbolicLinkDestination.map { URL(fileURLWithPath: $0) },
			symbolicLinkTargetIsDirectory: symbolicLinkTargetIsDirectory,
			isHidden: isHidden
		)
	}
}
