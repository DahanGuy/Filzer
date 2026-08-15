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
	/// Security-scoped access for every "Added Folder" is started once here (or the
	/// moment one is added) and kept alive for the app's whole lifetime, keyed by
	/// entry id — far simpler and less error-prone than starting/stopping it around
	/// every individual browse/search/mutate call, and it's what lets *every* engine
	/// operation anywhere in the app (including a recursive search walking down into
	/// one) treat an Added Folder exactly like any other reachable path.
	private var accessScopedURLs: [UUID: URL] = [:]

	init() {
		load()
		for entry in entries where entry.securityScopedBookmarkData != nil {
			startAccess(for: entry)
		}
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
		if entry.securityScopedBookmarkData != nil {
			startAccess(for: entry)
		}
		return entry
	}

	func remove(_ entry: BookmarkEntry) {
		stopAccess(for: entry)
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

	/// Resolves an externally-bookmarked entry back to a usable URL. Returns the same
	/// instance security-scoped access was started on (see `accessScopedURLs`) so every
	/// caller shares one already-authorized URL instead of re-resolving (and needing to
	/// re-wrap access around) a fresh one per call; in-sandbox entries need no such
	/// wrapping and just return their own `url`.
	func resolvedURL(for entry: BookmarkEntry) -> URL {
		accessScopedURLs[entry.id] ?? entry.url
	}

	/// Starts (and remembers) security-scoped access for one "Added Folder" entry. A
	/// no-op for plain in-sandbox bookmarks and for a bookmark that's already active.
	private func startAccess(for entry: BookmarkEntry) {
		guard accessScopedURLs[entry.id] == nil,
			let data = entry.securityScopedBookmarkData,
			let resolved = try? SecurityScopedBookmark.resolve(data),
			resolved.url.startAccessingSecurityScopedResource()
		else { return }
		accessScopedURLs[entry.id] = resolved.url
	}

	private func stopAccess(for entry: BookmarkEntry) {
		guard let url = accessScopedURLs.removeValue(forKey: entry.id) else { return }
		url.stopAccessingSecurityScopedResource()
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
