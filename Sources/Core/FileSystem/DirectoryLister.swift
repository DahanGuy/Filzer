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
		// `contentsOfDirectory` only lists names - it doesn't stat any of them, so a
		// directory the sandbox denies real access to (e.g. iOS system paths like
		// `/Developer`) can still enumerate names successfully while every individual
		// `FileNode.make` above fails. Left alone that silently looks identical to a
		// genuinely empty folder; surface it as the access error it actually is instead.
		if !nodes.isEmpty || visibleNames.isEmpty {
			return nodes
		}
		throw FileSystemError.accessDenied(directory)
	}
}
