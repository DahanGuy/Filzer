import Foundation

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
		return nodes
	}
}
