import CoreFoundation
import Foundation

enum PlistCodec {
	enum CodecError: LocalizedError {
		case unsupportedValue
		case malformedPlist

		var errorDescription: String? {
			switch self {
			case .unsupportedValue:
				return "This property list contains a value Filzer can't display."
			case .malformedPlist:
				return "This isn't a valid property list."
			}
		}
	}

	static func decode(_ data: Data) throws -> (root: PlistNode, format: PropertyListSerialization.PropertyListFormat) {
		var format: PropertyListSerialization.PropertyListFormat = .xml
		guard let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) else {
			throw CodecError.malformedPlist
		}
		return (try decodeAny(raw), format)
	}

	static func encode(_ node: PlistNode, format: PropertyListSerialization.PropertyListFormat) throws -> Data {
		let raw = encodeAny(node)
		guard PropertyListSerialization.propertyList(raw, isValidFor: format) else {
			throw CodecError.unsupportedValue
		}
		return try PropertyListSerialization.data(fromPropertyList: raw, format: format, options: 0)
	}

	private static func decodeAny(_ value: Any) throws -> PlistNode {
		switch value {
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return .boolean(number.boolValue)
			}
			return .number(number.doubleValue)
		case let string as String:
			return .string(string)
		case let date as Date:
			return .date(date)
		case let data as Data:
			return .data(data)
		case let array as [Any]:
			return .array(try array.map { PlistArrayEntry(value: try decodeAny($0)) })
		case let dictionary as [String: Any]:
			let entries = try dictionary
				.map { key, value in PlistDictionaryEntry(key: key, value: try decodeAny(value)) }
				.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
			return .dictionary(entries)
		default:
			throw CodecError.unsupportedValue
		}
	}

	private static func encodeAny(_ node: PlistNode) -> Any {
		switch node {
		case .string(let value): return value
		case .number(let value): return value
		case .boolean(let value): return value
		case .date(let value): return value
		case .data(let value): return value
		case .array(let entries): return entries.map { encodeAny($0.value) }
		case .dictionary(let entries):
			var dictionary: [String: Any] = [:]
			for entry in entries { dictionary[entry.key] = encodeAny(entry.value) }
			return dictionary
		}
	}
}
