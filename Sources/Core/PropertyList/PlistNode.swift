import Foundation

struct PlistDictionaryEntry: Equatable, Identifiable {
	let id: UUID
	var key: String
	var value: PlistNode

	init(id: UUID = UUID(), key: String, value: PlistNode) {
		self.id = id
		self.key = key
		self.value = value
	}
}

struct PlistArrayEntry: Equatable, Identifiable {
	let id: UUID
	var value: PlistNode

	init(id: UUID = UUID(), value: PlistNode) {
		self.id = id
		self.value = value
	}
}

enum PlistNode: Equatable {
	case string(String)
	case number(Double)
	case boolean(Bool)
	case date(Date)
	case data(Data)
	case array([PlistArrayEntry])
	case dictionary([PlistDictionaryEntry])

	enum Kind: String, CaseIterable, Identifiable {
		case string, number, boolean, date, data, array, dictionary
		var id: String { rawValue }
		var title: String { rawValue.capitalized }
	}

	var kind: Kind {
		switch self {
		case .string: return .string
		case .number: return .number
		case .boolean: return .boolean
		case .date: return .date
		case .data: return .data
		case .array: return .array
		case .dictionary: return .dictionary
		}
	}

	static func defaultValue(for kind: Kind) -> PlistNode {
		switch kind {
		case .string: return .string("")
		case .number: return .number(0)
		case .boolean: return .boolean(false)
		case .date: return .date(Date())
		case .data: return .data(Data())
		case .array: return .array([])
		case .dictionary: return .dictionary([])
		}
	}

	var previewText: String {
		switch self {
		case .string(let value): return value
		case .number(let value): return String(value)
		case .boolean(let value): return value ? "YES" : "NO"
		case .date(let value): return value.formatted()
		case .data(let value): return "\(value.count) byte\(value.count == 1 ? "" : "s")"
		case .array(let entries): return "\(entries.count) item\(entries.count == 1 ? "" : "s")"
		case .dictionary(let entries): return "\(entries.count) key\(entries.count == 1 ? "" : "s")"
		}
	}
}
