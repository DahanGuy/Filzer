import Combine
import Foundation

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

	func update(_ entry: BookmarkEntry, url: URL, displayName: String) {
		guard entry.securityScopedBookmarkData == nil, let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
		entries[index].url = url
		entries[index].displayName = displayName
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

	func reorderPlainEntries(to newPlainOrder: [BookmarkEntry]) {
		var remaining = newPlainOrder[...]
		entries = entries.map { entry in
			guard entry.securityScopedBookmarkData == nil, let next = remaining.first else { return entry }
			remaining.removeFirst()
			return next
		}
		save()
	}

	func resolvedURL(for entry: BookmarkEntry) -> URL {
		accessScopedURLs[entry.id] ?? entry.url
	}

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
