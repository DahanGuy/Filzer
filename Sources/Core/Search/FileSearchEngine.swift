import Foundation

/// Recursive, cancellable filename search rooted at a single directory. Runs on
/// whatever executor the calling `Task` is scheduled on; callers wanting to keep the
/// main actor free should call this from a background-priority `Task`.
enum FileSearchEngine {
	static func search(root: URL, query: String, includeHidden: Bool) throws -> [FileNode] {
		guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
		var results: [FileNode] = []
		try walk(root, query: query, includeHidden: includeHidden, into: &results)
		return results
	}

	private static func walk(_ directory: URL, query: String, includeHidden: Bool, into results: inout [FileNode]) throws {
		try Task.checkCancellation()
		// A permission-denied (or otherwise unreadable) subfolder should never abort
		// the whole search - just skip that one subtree silently and keep going.
		guard let children = try? DirectoryLister.children(of: directory, includeHidden: includeHidden) else {
			return
		}
		for child in children {
			try Task.checkCancellation()
			if child.name.localizedCaseInsensitiveContains(query) {
				results.append(child)
			}
			// `child.kind == .directory` only for real directories — symlinks (even ones
			// pointing at a directory) are classified `.symbolicLink` by `FileNode.make`,
			// so this recursion can never enter a cycle through a linked directory.
			if child.kind == .directory {
				try walk(child.url, query: query, includeHidden: includeHidden, into: &results)
			}
		}
	}
}
