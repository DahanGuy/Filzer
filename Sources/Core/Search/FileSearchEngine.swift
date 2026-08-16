import Foundation

enum FileSearchEngine {
	static func search(root: URL, query: String, includeHidden: Bool) throws -> [FileNode] {
		guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
		var results: [FileNode] = []
		let rootChildren = try DirectoryLister.children(of: root, includeHidden: includeHidden)
		for child in rootChildren {
			try Task.checkCancellation()
			if child.name.localizedCaseInsensitiveContains(query) {
				results.append(child)
			}
			if child.kind == .directory {
				try walkSubdirectory(child.url, query: query, includeHidden: includeHidden, into: &results)
			}
		}
		return results
	}

	private static func walkSubdirectory(_ directory: URL, query: String, includeHidden: Bool, into results: inout [FileNode]) throws {
		try Task.checkCancellation()
		guard let children = try? DirectoryLister.children(of: directory, includeHidden: includeHidden) else {
			return
		}
		for child in children {
			try Task.checkCancellation()
			if child.name.localizedCaseInsensitiveContains(query) {
				results.append(child)
			}
			if child.kind == .directory {
				try walkSubdirectory(child.url, query: query, includeHidden: includeHidden, into: &results)
			}
		}
	}
}
