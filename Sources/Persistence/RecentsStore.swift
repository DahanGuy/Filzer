import Combine
import Foundation

struct RecentEntry: Codable, Identifiable, Equatable {
	let id: UUID
	var url: URL
	var openedAt: Date

	init(id: UUID = UUID(), url: URL, openedAt: Date = Date()) {
		self.id = id
		self.url = url
		self.openedAt = openedAt
	}
}

/// Tracks recently-opened files (Filza's Recents section), most recent first.
@MainActor
final class RecentsStore: ObservableObject {
	@Published private(set) var entries: [RecentEntry] = []

	private let defaultsKey = "Filzer.Recents"
	private let limit = 50

	init() {
		load()
	}

	func recordOpen(of url: URL) {
		entries.removeAll { $0.url == url }
		entries.insert(RecentEntry(url: url), at: 0)
		if entries.count > limit {
			entries.removeLast(entries.count - limit)
		}
		save()
	}

	func remove(_ entry: RecentEntry) {
		entries.removeAll { $0.id == entry.id }
		save()
	}

	func clear() {
		entries.removeAll()
		save()
	}

	private func load() {
		guard
			let data = UserDefaults.standard.data(forKey: defaultsKey),
			let decoded = try? JSONDecoder().decode([RecentEntry].self, from: data)
		else { return }
		entries = decoded
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(entries) else { return }
		UserDefaults.standard.set(data, forKey: defaultsKey)
	}
}
