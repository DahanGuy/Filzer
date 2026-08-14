import Foundation

/// Parses `.mobileprovision` files for read-only display. These are a plist wrapped in
/// a CMS (PKCS#7) signature envelope; Filzer never installs a profile or verifies a
/// signature, so there's no reason to decode CMS. The plist is stored as plain ASCII
/// text inside the binary envelope, so locating it by byte range is reliable and
/// avoids pulling in a CMS/ASN.1 dependency for a single read-only viewer.
enum MobileProvisionParser {
	enum ParserError: LocalizedError {
		case malformed

		var errorDescription: String? {
			"This doesn't look like a valid provisioning profile."
		}
	}

	struct Profile {
		let name: String?
		let appIDName: String?
		let teamName: String?
		let teamIdentifiers: [String]
		let uuid: String?
		let creationDate: Date?
		let expirationDate: Date?
		let platforms: [String]
		let provisionsAllDevices: Bool
		let provisionedDeviceCount: Int?
		/// Stringified for display only — entitlement values are a mix of bools,
		/// strings, and arrays, and this viewer never needs to round-trip them.
		let entitlements: [(key: String, value: String)]
	}

	static func parse(_ data: Data) throws -> Profile {
		guard
			let startRange = data.range(of: Data("<?xml".utf8)),
			let endRange = data.range(of: Data("</plist>".utf8), options: [], in: startRange.upperBound..<data.endIndex)
		else {
			throw ParserError.malformed
		}
		let plistData = data[startRange.lowerBound..<endRange.upperBound]
		guard let info = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
			throw ParserError.malformed
		}

		let entitlements = (info["Entitlements"] as? [String: Any]) ?? [:]

		return Profile(
			name: info["Name"] as? String,
			appIDName: info["AppIDName"] as? String,
			teamName: info["TeamName"] as? String,
			teamIdentifiers: info["TeamIdentifier"] as? [String] ?? [],
			uuid: info["UUID"] as? String,
			creationDate: info["CreationDate"] as? Date,
			expirationDate: info["ExpirationDate"] as? Date,
			platforms: info["Platform"] as? [String] ?? [],
			provisionsAllDevices: info["ProvisionsAllDevices"] as? Bool ?? false,
			provisionedDeviceCount: (info["ProvisionedDevices"] as? [String])?.count,
			entitlements: entitlements.keys.sorted().map { ($0, String(describing: entitlements[$0] ?? "")) }
		)
	}
}
