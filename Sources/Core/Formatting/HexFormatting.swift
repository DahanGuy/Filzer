import Foundation

enum HexFormatting {
	static let bytesPerRow = 16

	struct Row: Identifiable {
		let offset: Int
		let bytes: [UInt8]
		var id: Int { offset }

		var offsetString: String { String(format: "%08X", offset) }

		var hexString: String {
			var parts: [String] = []
			parts.reserveCapacity(HexFormatting.bytesPerRow)
			for index in 0..<HexFormatting.bytesPerRow {
				parts.append(index < bytes.count ? String(format: "%02X", bytes[index]) : "  ")
			}
			return parts.joined(separator: " ")
		}

		var asciiString: String {
			String(bytes.map { byte in
				(0x20...0x7e).contains(byte) ? Character(UnicodeScalar(byte)) : "."
			})
		}
	}

	static func rows(for data: Data, startOffset: Int = 0) -> [Row] {
		var rows: [Row] = []
		var index = data.startIndex
		var offset = startOffset
		while index < data.endIndex {
			let end = data.index(index, offsetBy: bytesPerRow, limitedBy: data.endIndex) ?? data.endIndex
			rows.append(Row(offset: offset, bytes: Array(data[index..<end])))
			offset += bytesPerRow
			index = end
		}
		return rows
	}

	static func bytes(fromHexString text: String) -> [UInt8]? {
		let cleaned = text.filter { !$0.isWhitespace }
		guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2) else { return nil }
		var bytes: [UInt8] = []
		bytes.reserveCapacity(cleaned.count / 2)
		var index = cleaned.startIndex
		while index < cleaned.endIndex {
			let next = cleaned.index(index, offsetBy: 2)
			guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
			bytes.append(byte)
			index = next
		}
		return bytes
	}
}
