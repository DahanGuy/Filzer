import Combine
import Foundation

/// A pinned location — either inside Filzer's own sandbox (`securityScopedBookmarkData
/// == nil`) or an externally-picked folder/file the user added via the document picker
/// (needs security-scoped access resolved before every use).
struct BookmarkEntry: Codable, Identifiable, Equatable {
	let id: UUID
	var url: URL
	var displayName: String
	var securityScopedBookmarkData: Data?

	init(id: UUID = UUID(), url: URL, displayName: String, securityScopedBookmarkData: Data? = nil) {
		self.id = id
		self.url = url
		self.displayName = displayName
		self.securityScopedBookmarkData = securityScopedBookmarkData
	}
}

@MainActor
final class BookmarksStore: ObservableObject {
	@Published private(set) var entries: [BookmarkEntry] = []

	private let defaultsKey = "Filzer.Bookmarks"

	init() {
		load()
	}

	func isBookmarked(_ url: URL) -> Bool {
		entries.contains { $0.url.standardizedFileURL == url.standardizedFileURL }
	}

	@discardableResult
	func add(url: URL, displayName: String? = nil, securityScopedBookmarkData: Data? = nil) -> BookmarkEntry? {
		guard !isBookmarked(url) else { return nil }
		let entry = BookmarkEntry(
			url: url,
			displayName: displayName ?? url.lastPathComponent,
			securityScopedBookmarkData: securityScopedBookmarkData
		)
		entries.append(entry)
		save()
		return entry
	}

	func remove(_ entry: BookmarkEntry) {
		entries.removeAll { $0.id == entry.id }
		save()
	}

	func toggle(url: URL, displayName: String) {
		if let existing = entries.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
			remove(existing)
		} else {
			add(url: url, displayName: displayName)
		}
	}

	func move(fromOffsets source: IndexSet, toOffset destination: Int) {
		entries.move(fromOffsets: source, toOffset: destination)
		save()
	}

	/// Reorders just the plain (non-externally-picked) bookmarks shown in the
	/// Bookmarks flyout, leaving every "Added Folder" entry (shown in Disks instead,
	/// `securityScopedBookmarkData != nil`) at its existing position in the full
	/// underlying array — `.onMove` in a filtered `List` only knows filtered-list
	/// offsets, so the reordered subsequence is merged back in by walking `entries`
	/// and taking the next plain entry from `newPlainOrder` wherever one was.
	func reorderPlainEntries(to newPlainOrder: [BookmarkEntry]) {
		var remaining = newPlainOrder[...]
		entries = entries.map { entry in
			guard entry.securityScopedBookmarkData == nil, let next = remaining.first else { return entry }
			remaining.removeFirst()
			return next
		}
		save()
	}

	/// Resolves an externally-bookmarked entry back to a usable URL. Callers must wrap
	/// filesystem access in `SecurityScopedBookmark.withSecurityScopedAccess` when
	/// `securityScopedBookmarkData` is non-nil; in-sandbox entries need no such wrapping.
	func resolvedURL(for entry: BookmarkEntry) -> URL {
		guard let data = entry.securityScopedBookmarkData, let resolved = try? SecurityScopedBookmark.resolve(data) else {
			return entry.url
		}
		return resolved.url
	}

	private func load() {
		guard
			let data = UserDefaults.standard.data(forKey: defaultsKey),
			let decoded = try? JSONDecoder().decode([BookmarkEntry].self, from: data)
		else { return }
		entries = decoded
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(entries) else { return }
		UserDefaults.standard.set(data, forKey: defaultsKey)
	}
}
