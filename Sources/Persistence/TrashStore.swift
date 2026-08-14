import Combine
import Foundation

/// A soft-delete folder inside Filzer's own `Library` directory (invisible to normal
/// browsing), mirroring Filza's Trash + "Put back" flow — the sandboxed-safe equivalent
/// since there's no OS-level Trash for an app's own container.
@MainActor
final class TrashStore: ObservableObject {
	@Published private(set) var items: [FileNode] = []

	static let directory: URL = {
		let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
		let trash = library.appendingPathComponent("Filzer Trash", isDirectory: true)
		try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
		return trash
	}()

	private let originalLocationsKey = "Filzer.Trash.OriginalLocations"

	func refresh() async {
		items = (try? await FileSystem.current.listDirectory(at: Self.directory, includeHidden: true)) ?? []
	}

	/// Moves `urls` into Trash, remembering each item's original location for restore.
	func moveToTrash(_ urls: [URL]) async throws {
		for url in urls {
			let trashName = "\(UUID().uuidString)_\(url.lastPathComponent)"
			let destination = Self.directory.appendingPathComponent(trashName)
			try await FileSystem.current.moveItem(from: url, to: destination)
			recordOriginalLocation(trashName: trashName, originalURL: url)
		}
		await refresh()
	}

	/// Restores a trashed item to where it was deleted from.
	func restore(_ node: FileNode) async throws {
		guard let originalURL = originalLocation(trashName: node.name) else {
			throw FileSystemError.operationFailed("Filzer doesn't remember where \"\(displayName(for: node))\" came from.")
		}
		try await FileSystem.current.moveItem(from: node.url, to: originalURL)
		clearOriginalLocation(trashName: node.name)
		await refresh()
	}

	func emptyTrash() async throws {
		let urls = items.map(\.url)
		guard !urls.isEmpty else { return }
		try await FileSystem.current.delete(urls)
		for node in items { clearOriginalLocation(trashName: node.name) }
		await refresh()
	}

	/// The name to show the user instead of the internal `UUID_name` trash filename.
	func displayName(for node: FileNode) -> String {
		guard let underscoreRange = node.name.range(of: "_"),
			  UUID(uuidString: String(node.name[node.name.startIndex..<underscoreRange.lowerBound])) != nil
		else { return node.name }
		return String(node.name[underscoreRange.upperBound...])
	}

	// MARK: - Original-location bookkeeping

	private func recordOriginalLocation(trashName: String, originalURL: URL) {
		var map = originalLocations
		map[trashName] = originalURL
		originalLocations = map
	}

	private func originalLocation(trashName: String) -> URL? {
		originalLocations[trashName]
	}

	private func clearOriginalLocation(trashName: String) {
		var map = originalLocations
		map.removeValue(forKey: trashName)
		originalLocations = map
	}

	private var originalLocations: [String: URL] {
		get {
			guard
				let data = UserDefaults.standard.data(forKey: originalLocationsKey),
				let decoded = try? JSONDecoder().decode([String: URL].self, from: data)
			else { return [:] }
			return decoded
		}
		set {
			guard let data = try? JSONEncoder().encode(newValue) else { return }
			UserDefaults.standard.set(data, forKey: originalLocationsKey)
		}
	}
}
