import Foundation

struct ArchiveRow: Identifiable, Hashable {
	let entry: ArchiveEntry
	var id: String { entry.id }
}

enum ArchiveTree {
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
