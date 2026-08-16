import Foundation

/// Shared "read one directory level" building block used by the browsing operation
/// itself and every recursive traversal (size calculation, search, recursive
/// permission apply) so they all inherit the same symlink-safe classification from
/// `FileNode.make`.
enum DirectoryLister {
	static func children(of directory: URL, includeHidden: Bool) throws -> [FileNode] {
		let fileManager = FileManager.default
		let names = try fileManager.contentsOfDirectory(atPath: directory.path)
		let visibleNames = includeHidden ? names : names.filter { !$0.hasPrefix(".") }
		var nodes: [FileNode] = []
		nodes.reserveCapacity(visibleNames.count)
		for name in visibleNames {
			let childURL = directory.appendingPathComponent(name)
			if let node = try? FileNode.make(at: childURL) {
				nodes.append(node)
			}
		}
		if nodes.isEmpty && !visibleNames.isEmpty {
			throw FileSystemError.accessDenied(directory)
		}
		return nodes
	}
}
