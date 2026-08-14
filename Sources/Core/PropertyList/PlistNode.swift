import Foundation

/// A single key/value entry in a `.dictionary` node. A struct (not a tuple) so
/// `PlistEditorView`'s `List` can diff and animate individual rows by `id`.
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

/// A single entry in an `.array` node, wrapped for stable `List` identity across reorders.
struct PlistArrayEntry: Equatable, Identifiable {
	let id: UUID
	var value: PlistNode

	init(id: UUID = UUID(), value: PlistNode) {
		self.id = id
		self.value = value
	}
}

/// An in-memory property-list value tree. Filza's Property List Editor treats XML and
/// binary plists identically once parsed — so does this type; the on-disk format is
/// only a detail of `PlistCodec`.
enum PlistNode: Equatable {
	case string(String)
	case number(Double)
	case boolean(Bool)
	case date(Date)
	case data(Data)
	case array([PlistArrayEntry])
	case dictionary([PlistDictionaryEntry])

	/// The case name shown in the "Change Type" picker, and used to build a sensible
	/// default value when the user switches a node to this type.
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

	/// A short, single-line description used as a row's trailing value/subtitle.
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
