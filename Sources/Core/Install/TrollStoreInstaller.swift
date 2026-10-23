import UIKit

enum TrollStoreInstaller {
	private static let knownLocations = [
		"/Applications/TrollStore.app",
		"/var/jb/Applications/TrollStore.app"
	]
	private static let bundleContainersPath = "/var/containers/Bundle/Application"

	/// `apple-magnifier://` is registered by the stock Magnifier app too, so `canOpenURL` can't tell
	/// whether TrollStore is installed. Look for its bundle on disk instead.
	static func isInstalled() async -> Bool {
		await Task.detached(priority: .utility) {
			let fileManager = FileManager.default
			if knownLocations.contains(where: { fileManager.fileExists(atPath: $0) }) { return true }
			let containers = (try? fileManager.contentsOfDirectory(atPath: bundleContainersPath)) ?? []
			return containers.contains { fileManager.fileExists(atPath: "\(bundleContainersPath)/\($0)/TrollStore.app") }
		}.value
	}

	static func installURL(for fileURL: URL) -> URL? {
		guard let encoded = fileURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
		return URL(string: "apple-magnifier://install?url=\(encoded)")
	}

	@MainActor
	static func install(_ fileURL: URL) async -> Bool {
		guard let url = installURL(for: fileURL) else { return false }
		return await UIApplication.shared.open(url)
	}
}
