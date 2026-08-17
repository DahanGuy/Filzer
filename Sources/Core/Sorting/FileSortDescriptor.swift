import Foundation

enum FileSortField: String, CaseIterable, Identifiable, Codable {
	case name
	case dateModified
	case size
	case kind

	var id: String { rawValue }

	var title: String {
		switch self {
		case .name: return "Name"
		case .dateModified: return "Date"
		case .size: return "Size"
		case .kind: return "Kind"
		}
	}
}

struct FileSortDescriptor: Codable, Equatable {
	var field: FileSortField
	var ascending: Bool

	static let `default` = FileSortDescriptor(field: .name, ascending: true)

	func comparator() -> (FileNode, FileNode) -> Bool {
		{ lhs, rhs in
			if lhs.sortsAsDirectory != rhs.sortsAsDirectory {
				return lhs.sortsAsDirectory
			}
			let primary = compare(lhs, rhs)
			if primary != 0 {
				return ascending ? primary < 0 : primary > 0
			}
			return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
		}
	}

	private func compare(_ lhs: FileNode, _ rhs: FileNode) -> Int {
		switch field {
		case .name:
			switch lhs.name.localizedStandardCompare(rhs.name) {
			case .orderedAscending: return -1
			case .orderedDescending: return 1
			case .orderedSame: return 0
			}
		case .dateModified:
			let lhsDate = lhs.modifiedAt ?? .distantPast
			let rhsDate = rhs.modifiedAt ?? .distantPast
			if lhsDate == rhsDate { return 0 }
			return lhsDate < rhsDate ? -1 : 1
		case .size:
			if lhs.size == rhs.size { return 0 }
			return lhs.size < rhs.size ? -1 : 1
		case .kind:
			switch lhs.pathExtension.localizedStandardCompare(rhs.pathExtension) {
			case .orderedAscending: return -1
			case .orderedDescending: return 1
			case .orderedSame: return 0
			}
		}
	}
}
