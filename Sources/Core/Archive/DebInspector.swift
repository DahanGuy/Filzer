import Foundation
import SWCompression

struct DebField: Identifiable {
	let key: String
	let value: String
	var id: String { key }
}

struct DebSummary {
	let fields: [DebField]
	let maintainerScripts: [String]
	let isIOSPackage: Bool
	let platform: String
	let kind: String
	let fileSize: Int64

	func value(for key: String) -> String? {
		fields.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
	}

	var displayName: String {
		value(for: "Name") ?? value(for: "Package") ?? "Unknown"
	}

	var synopsis: String? {
		value(for: "Description")?.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map { String($0) }
	}
}

enum DebInspector {
	enum InspectorError: LocalizedError {
		case notADebPackage
		case missingControl
		case missingData
		case unsupportedCompression(String)
		case contentsTooLarge

		var errorDescription: String? {
			switch self {
			case .notADebPackage: return "This isn't a valid .deb package."
			case .missingControl: return "This package's control information couldn't be read."
			case .missingData: return "This package has no data archive."
			case .unsupportedCompression(let name): return "This package is compressed with \(name), which Filzer can't read yet."
			case .contentsTooLarge: return "This package is too large to open."
			}
		}
	}

	private struct ArMember {
		let name: String
		let range: Range<Int>
	}

	private static let classificationSizeLimit = 16 * 1024 * 1024
	private static let dataSizeLimit = 128 * 1024 * 1024
	private static let maintainerScriptNames = ["preinst", "postinst", "prerm", "postrm"]

	static func summarize(debURL: URL) async throws -> DebSummary {
		try await Task.detached(priority: .userInitiated) { () throws -> DebSummary in
			try loadSummary(debURL)
		}.value
	}

	/// The decompressed `data.tar` of a package, for the archive browser.
	static func dataTar(of debURL: URL) throws -> Data {
		let archive = try Data(contentsOf: debURL, options: .alwaysMapped)
		guard let dataMember = try arMembers(in: archive).first(where: { $0.name.hasPrefix("data.tar") }) else { throw InspectorError.missingData }
		guard dataMember.range.count <= dataSizeLimit else { throw InspectorError.contentsTooLarge }
		return try decompress(dataMember, in: archive)
	}

	private static func loadSummary(_ debURL: URL) throws -> DebSummary {
		let archive = try Data(contentsOf: debURL, options: .alwaysMapped)
		let members = try arMembers(in: archive)
		guard let controlMember = members.first(where: { $0.name.hasPrefix("control.tar") }) else { throw InspectorError.missingControl }

		var controlText: String?
		var foundScripts: Set<String> = []
		for entry in try TarContainer.open(container: try decompress(controlMember, in: archive)) {
			let name = normalized(entry.info.name)
			if name == "control" {
				controlText = entry.data.map { String(decoding: $0, as: UTF8.self) }
			} else if maintainerScriptNames.contains(name) {
				foundScripts.insert(name)
			}
		}
		guard let controlText else { throw InspectorError.missingControl }
		let fields = parseControl(controlText)
		guard !fields.isEmpty else { throw InspectorError.missingControl }

		var dataPaths: [String]?
		if
			let dataMember = members.first(where: { $0.name.hasPrefix("data.tar") }),
			dataMember.range.count <= classificationSizeLimit,
			let paths = try? listPaths(of: dataMember, in: archive)
		{
			dataPaths = paths
		}

		let classification = classify(fields: fields, dataPaths: dataPaths)
		return DebSummary(
			fields: fields,
			maintainerScripts: maintainerScriptNames.filter { foundScripts.contains($0) },
			isIOSPackage: classification.isIOS,
			platform: classification.platform,
			kind: classification.kind,
			fileSize: Int64(archive.count)
		)
	}

	private static func listPaths(of member: ArMember, in archive: Data) throws -> [String] {
		try TarContainer.info(container: decompress(member, in: archive))
			.map { normalized($0.name) }
			.filter { !$0.isEmpty }
	}

	// MARK: ar container

	private static func arMembers(in data: Data) throws -> [ArMember] {
		let magic = Data("!<arch>\n".utf8)
		guard data.count >= magic.count, data.prefix(magic.count) == magic else { throw InspectorError.notADebPackage }

		let headerLength = 60
		var members: [ArMember] = []
		var offset = magic.count
		while offset + headerLength <= data.count {
			let headerStart = offset
			func field(_ start: Int, _ length: Int) -> String {
				String(decoding: data[(headerStart + start)..<(headerStart + start + length)], as: UTF8.self)
					.trimmingCharacters(in: .whitespacesAndNewlines)
			}
			guard data[headerStart + 58] == 0x60, data[headerStart + 59] == 0x0A, let size = Int(field(48, 10)) else {
				throw InspectorError.notADebPackage
			}

			var name = field(0, 16)
			var bodyStart = headerStart + headerLength
			var bodyLength = size
			if name.hasPrefix("#1/"), let nameLength = Int(name.dropFirst(3)), nameLength <= size, bodyStart + nameLength <= data.count {
				name = String(decoding: data[bodyStart..<(bodyStart + nameLength)], as: UTF8.self)
					.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
				bodyStart += nameLength
				bodyLength -= nameLength
			}
			if name.hasSuffix("/") { name.removeLast() }
			guard bodyStart + bodyLength <= data.count else { throw InspectorError.notADebPackage }

			members.append(ArMember(name: name, range: bodyStart..<(bodyStart + bodyLength)))
			offset = headerStart + headerLength + size + size % 2
		}
		return members
	}

	private static func decompress(_ member: ArMember, in archive: Data) throws -> Data {
		let raw = Data(archive[member.range])
		let name = member.name.lowercased()
		if name.hasSuffix(".gz") { return try GzipArchive.unarchive(archive: raw) }
		if name.hasSuffix(".xz") { return try XZArchive.unarchive(archive: raw) }
		if name.hasSuffix(".bz2") { return try BZip2.decompress(data: raw) }
		if name.hasSuffix(".lzma") { return try LZMA.decompress(data: raw) }
		if name.hasSuffix(".zst") { throw InspectorError.unsupportedCompression("zstd") }
		return raw
	}

	// MARK: control file

	private static func parseControl(_ text: String) -> [DebField] {
		var fields: [DebField] = []
		var currentKey: String?
		var currentValue = ""

		func flush() {
			if let currentKey {
				fields.append(DebField(key: currentKey, value: currentValue.trimmingCharacters(in: .whitespacesAndNewlines)))
			}
			currentKey = nil
			currentValue = ""
		}

		for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
			if line.first == " " || line.first == "\t" {
				guard currentKey != nil else { continue }
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				currentValue += "\n" + (trimmed == "." ? "" : trimmed)
			} else if let colon = line.firstIndex(of: ":") {
				flush()
				currentKey = String(line[..<colon])
				currentValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
			} else {
				flush()
			}
		}
		flush()
		return fields
	}

	// MARK: classification

	private static func classify(fields: [DebField], dataPaths: [String]?) -> (isIOS: Bool, platform: String, kind: String) {
		func value(_ key: String) -> String {
			fields.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value.lowercased() ?? ""
		}
		let architecture = value("Architecture")
		let dependencies = value("Depends") + " " + value("Pre-Depends")
		let section = value("Section")
		let paths = dataPaths ?? []

		let rootlessPrefix = "var/jb/"
		let isRootlessLayout = paths.contains { $0.hasPrefix(rootlessPrefix) }
		let relativePaths = paths.map { $0.hasPrefix(rootlessPrefix) ? String($0.dropFirst(rootlessPrefix.count)) : $0 }

		let hasTweak = relativePaths.contains {
			$0.hasPrefix("Library/MobileSubstrate/") || $0.hasPrefix("usr/lib/TweakInject/") || $0.hasPrefix("Library/PreferenceBundles/")
		}
		let hasApp = relativePaths.contains { $0.hasPrefix("Applications/") && $0.contains(".app/") }
		let hasTheme = relativePaths.contains { $0.hasPrefix("Library/Themes/") }

		let dependencyHints = ["mobilesubstrate", "ellekit", "substitute", "preferenceloader", "libhooker", "firmware (", "firmware(", "cydia-substrate"]
		let sectionHints = ["tweak", "theme", "addon"]
		let looksLikeIOS = architecture.hasPrefix("iphoneos-")
			|| hasTweak || hasApp || hasTheme || isRootlessLayout
			|| dependencyHints.contains { dependencies.contains($0) }
			|| sectionHints.contains { section.contains($0) }

		guard looksLikeIOS else {
			return (false, architecture.hasPrefix("darwin-") ? "macOS" : "Debian / Linux", "Package")
		}

		let scheme: String
		switch architecture {
		case "iphoneos-arm": scheme = " (rootful)"
		case "iphoneos-arm64": scheme = " (rootless)"
		case "iphoneos-arm64e": scheme = " (roothide)"
		default: scheme = isRootlessLayout ? " (rootless)" : ""
		}

		let kind: String
		if hasApp { kind = "App" } else if hasTweak { kind = "Tweak" } else if hasTheme { kind = "Theme" } else { kind = "Package" }
		return (true, "iOS" + scheme, kind)
	}

	static func normalized(_ path: String) -> String {
		var result = Substring(path)
		while result.hasPrefix("./") { result = result.dropFirst(2) }
		while result.hasPrefix("/") { result = result.dropFirst() }
		return result == "." ? "" : String(result)
	}
}
