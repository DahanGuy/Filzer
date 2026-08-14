import Foundation

/// Parsed metadata for an `.ipa` app archive — Filzer's read-only "App Inspector".
/// There is deliberately no install/execution path anywhere in this type or its
/// callers; it exists purely to answer "what is this app" without ever running it.
struct IPASummary {
	let displayName: String
	let bundleIdentifier: String
	let version: String
	let buildNumber: String
	let minimumOSVersion: String?
	let executableName: String?
	/// Best-effort app icon PNG data. `nil` when the app ships icons only inside a
	/// compiled `Assets.car` (the modern default), which Filzer doesn't parse.
	let iconData: Data?
}

enum IPAInspector {
	enum InspectorError: LocalizedError {
		case noAppBundleFound
		case missingInfoPlist

		var errorDescription: String? {
			switch self {
			case .noAppBundleFound: return "This doesn't look like a valid IPA — no Payload/*.app folder was found."
			case .missingInfoPlist: return "This IPA's Info.plist couldn't be read."
			}
		}
	}

	/// Reads only the handful of entries this needs out of the archive — an IPA can be
	/// hundreds of megabytes, and Filzer only wants a few kilobytes of plist and icon.
	static func summarize(ipaURL: URL) async throws -> IPASummary {
		let entries = try await FileSystem.current.listArchiveEntries(ipaURL)
		guard let appFolder = entries.first(where: { $0.isDirectory && $0.path.hasPrefix("Payload/") && $0.path.hasSuffix(".app/") })?.path else {
			throw InspectorError.noAppBundleFound
		}
		guard let infoPlistEntry = entries.first(where: { $0.path == appFolder + "Info.plist" }) else {
			throw InspectorError.missingInfoPlist
		}

		let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: scratchDirectory) }

		let infoPlistURL = scratchDirectory.appendingPathComponent("Info.plist")
		try await FileSystem.current.extractArchiveEntry(infoPlistEntry.path, from: ipaURL, to: infoPlistURL)
		guard
			let infoPlistData = try? Data(contentsOf: infoPlistURL),
			let info = try? PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil) as? [String: Any]
		else {
			throw InspectorError.missingInfoPlist
		}

		let iconData = try? await loadIconData(appFolder: appFolder, ipaURL: ipaURL, entries: entries, scratchDirectory: scratchDirectory)

		return IPASummary(
			displayName: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ipaURL.deletingPathExtension().lastPathComponent,
			bundleIdentifier: (info["CFBundleIdentifier"] as? String) ?? "Unknown",
			version: (info["CFBundleShortVersionString"] as? String) ?? "Unknown",
			buildNumber: (info["CFBundleVersion"] as? String) ?? "Unknown",
			minimumOSVersion: info["MinimumOSVersion"] as? String,
			executableName: info["CFBundleExecutable"] as? String,
			iconData: iconData
		)
	}

	/// Picks the largest loose `AppIcon*.png` sitting directly in the app bundle, on
	/// the assumption that a bigger file is a higher-resolution icon.
	private static func loadIconData(appFolder: String, ipaURL: URL, entries: [ArchiveEntry], scratchDirectory: URL) async throws -> Data? {
		let iconEntries = entries.filter {
			!$0.isDirectory && $0.path.hasPrefix(appFolder) && $0.name.contains("AppIcon") && $0.name.hasSuffix(".png")
		}
		guard let largest = iconEntries.max(by: { $0.uncompressedSize < $1.uncompressedSize }) else { return nil }
		let iconURL = scratchDirectory.appendingPathComponent("icon.png")
		try await FileSystem.current.extractArchiveEntry(largest.path, from: ipaURL, to: iconURL)
		return try Data(contentsOf: iconURL)
	}
}
