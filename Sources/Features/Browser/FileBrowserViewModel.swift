import Combine
import Foundation

/// Drives a single `FileBrowserView` instance: the directory listing, multi-select
/// state, and every mutating action (new/rename/duplicate/delete/paste/compress/links).
/// Every mutation reloads the listing afterward so the view never has to reconcile
/// stale state by hand.
@MainActor
final class FileBrowserViewModel: ObservableObject {
	@Published private(set) var nodes: [FileNode] = []
	@Published var isLoading = false
	/// Set only by `reload()` — shown inline as an empty-state message, never as a
	/// popup (navigating into an inaccessible sandboxed path is an expected, frequent
	/// event here, not something worth interrupting the user for).
	@Published private(set) var loadErrorMessage: String?
	/// Set by mutating actions (create/rename/delete/paste/…) — shown via `.errorAlert`.
	@Published var errorMessage: String?
	@Published var isSelecting = false
	@Published var selection: Set<URL> = []

	let rootURL: URL
	var includeHidden = false
	var sortDescriptor = FileSortDescriptor.default

	init(rootURL: URL) {
		self.rootURL = rootURL
	}

	func reload() async {
		isLoading = true
		defer { isLoading = false }
		do {
			let children = try await FileSystem.current.listDirectory(at: rootURL, includeHidden: includeHidden)
			nodes = children.sorted(by: sortDescriptor.comparator())
			loadErrorMessage = nil
		} catch {
			nodes = []
			loadErrorMessage = error.localizedDescription
		}
	}

	// MARK: - Selection

	func toggleSelection(of node: FileNode) {
		if selection.contains(node.url) {
			selection.remove(node.url)
		} else {
			selection.insert(node.url)
		}
	}

	func endSelecting() {
		isSelecting = false
		selection.removeAll()
	}

	// MARK: - Mutating actions

	func createFolder(name: String) async {
		await run { try await FileSystem.current.createDirectory(at: self.rootURL.appendingPathComponent(name)) }
	}

	func createFile(name: String) async {
		await run { try await FileSystem.current.createFile(at: self.rootURL.appendingPathComponent(name)) }
	}

	func rename(_ node: FileNode, to newName: String) async {
		await run { try await FileSystem.current.rename(node.url, to: newName) }
	}

	func duplicate(_ node: FileNode) async {
		let destination = rootURL.appendingPathComponent(Self.duplicateName(for: node.name, existing: Set(nodes.map(\.name))))
		await run { try await FileSystem.current.copyItem(from: node.url, to: destination) }
	}

	func createSymbolicLink(name: String, target: URL) async {
		await run { try await FileSystem.current.createSymbolicLink(at: self.rootURL.appendingPathComponent(name), destination: target) }
	}

	func createHardLink(name: String, target: URL) async {
		await run { try await FileSystem.current.createHardLink(at: self.rootURL.appendingPathComponent(name), destination: target) }
	}

	/// Filzer never keeps its own Trash — deletion is permanent for anything in its own
	/// sandbox. For an externally-bookmarked location, whatever the OS/document
	/// provider does with a deleted item (e.g. iCloud Drive's own "Recently Deleted",
	/// visible only in the system Files app) is outside Filzer's control or visibility.
	func delete(_ urls: [URL]) async {
		do {
			try await FileSystem.current.delete(urls)
			selection.subtract(urls)
			await reload()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func paste(clipboard: ClipboardStore) async {
		guard let payload = clipboard.payload, !payload.urls.isEmpty else { return }
		do {
			switch payload.operation {
			case .copy:
				try await FileSystem.current.copyItems(payload.urls, toDirectory: rootURL)
			case .move:
				try await FileSystem.current.moveItems(payload.urls, toDirectory: rootURL)
				clipboard.clear()
			}
			await reload()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	/// Extracts an archive in-place into a new sibling folder named after it — for any
	/// format `ArchiveFormat` recognizes, not just `.zip`.
	func extractHere(_ node: FileNode) async {
		let name = Self.uniqueFolderName(baseName: ArchiveFormat.baseName(for: node.url), existingNames: Set(nodes.map(\.name)))
		let destination = rootURL.appendingPathComponent(name)
		await run { try await FileSystem.current.extractArchive(node.url, toDirectory: destination) }
	}

	func importItems(_ urls: [URL]) async {
		for url in urls {
			let destination = rootURL.appendingPathComponent(url.lastPathComponent)
			await SecurityScopedBookmark.withSecurityScopedAccess(to: url) {
				await self.run { try await FileSystem.current.copyItem(from: url, to: destination) }
			}
		}
	}

	func compress(_ urls: [URL]) async {
		guard !urls.isEmpty else { return }
		let base = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive"
		let name = Self.uniqueFileName(baseName: base, extension: "zip", existingNames: Set(nodes.map(\.name)))
		let destination = rootURL.appendingPathComponent(name)
		await run { try await FileSystem.current.compressItems(urls, to: destination) }
	}

	func setPermissions(_ urls: [URL], posixPermissions: Int16, recursive: Bool) async {
		await run { try await FileSystem.current.setPermissions(urls, posixPermissions: posixPermissions, recursive: recursive) }
	}

	// MARK: - Helpers

	private func run(_ operation: @escaping () async throws -> Void) async {
		do {
			try await operation()
			await reload()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	static func duplicateName(for name: String, existing: Set<String>) -> String {
		let url = URL(fileURLWithPath: name)
		let ext = url.pathExtension
		let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
		var candidate = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
		var counter = 2
		while existing.contains(candidate) {
			candidate = ext.isEmpty ? "\(base) copy \(counter)" : "\(base) copy \(counter).\(ext)"
			counter += 1
		}
		return candidate
	}

	private static func uniqueFileName(baseName: String, extension ext: String, existingNames: Set<String>) -> String {
		var candidate = "\(baseName).\(ext)"
		var counter = 2
		while existingNames.contains(candidate) {
			candidate = "\(baseName) \(counter).\(ext)"
			counter += 1
		}
		return candidate
	}

	private static func uniqueFolderName(baseName: String, existingNames: Set<String>) -> String {
		var candidate = baseName
		var counter = 2
		while existingNames.contains(candidate) {
			candidate = "\(baseName) \(counter)"
			counter += 1
		}
		return candidate
	}
}
