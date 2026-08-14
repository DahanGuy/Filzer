import Foundation

/// One row in the zip browser's virtual folder tree. Wraps an `ArchiveEntry` rather
/// than a `FileNode` — entries living inside a zip have no real URL on disk until
/// they're explicitly extracted, so they can't be forced into the `FileNode` shape.
struct ArchiveRow: Identifiable, Hashable {
	let entry: ArchiveEntry
	var id: String { entry.id }
}

/// Groups a zip's flat `[ArchiveEntry]` listing into a virtual folder tree without
/// ever extracting anything to disk.
enum ArchiveTree {
	/// Returns the folders and files that sit directly under `prefix` (the empty
	/// string for the zip's root, otherwise a `"folder/sub/"`-style path with a
	/// trailing slash). Folders are synthesized from path components on the fly for
	/// zips that omit explicit directory records, then merged with any explicit
	/// directory entry at the same path so real metadata wins. Folders sort before
	/// files; both sort alphabetically.
	static func rows(in entries: [ArchiveEntry], under prefix: String) -> [ArchiveRow] {
		var folders: [String: ArchiveEntry] = [:]
		var files: [ArchiveEntry] = []

		for entry in entries {
			guard entry.path.hasPrefix(prefix), entry.path != prefix else { continue }
			let remainder = entry.path.dropFirst(prefix.count)
			guard !remainder.isEmpty else { continue }

			if let slashIndex = remainder.firstIndex(of: "/") {
				let childName = String(remainder[remainder.startIndex..<slashIndex])
				guard !childName.isEmpty else { continue }
				let childPath = prefix + childName + "/"
				let isExplicitDirectoryRecord = remainder.index(after: slashIndex) == remainder.endIndex
				if isExplicitDirectoryRecord {
					folders[childPath] = entry
				} else if folders[childPath] == nil {
					folders[childPath] = ArchiveEntry(path: childPath, isDirectory: true, uncompressedSize: 0, compressedSize: 0)
				}
			} else if entry.isDirectory {
				// A directory record without a trailing slash — treat its name as the child.
				folders[prefix + String(remainder) + "/"] = entry
			} else {
				files.append(entry)
			}
		}

		let folderRows = folders.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		let fileRows = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		return (folderRows + fileRows).map(ArchiveRow.init)
	}
}
