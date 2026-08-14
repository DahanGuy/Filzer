import Combine
import Foundation

/// Per-extension viewer overrides (Filza's "File associations" settings screen).
/// Falls back to `ViewerKind.defaultViewer(for:)` for any extension without an override.
@MainActor
final class FileAssociationsStore: ObservableObject {
	@Published private(set) var associations: [String: ViewerKind] = [:]

	private let defaultsKey = "Filzer.FileAssociations"

	init() {
		load()
	}

	func viewer(for node: FileNode) -> ViewerKind {
		associations[FileClassifier.associationKey(for: node)] ?? ViewerKind.defaultViewer(for: node)
	}

	func override(forExtension extension: String) -> ViewerKind? {
		associations[`extension`.lowercased()]
	}

	func setViewer(_ viewer: ViewerKind?, forExtension extension: String) {
		let key = `extension`.lowercased()
		guard !key.isEmpty else { return }
		if let viewer {
			associations[key] = viewer
		} else {
			associations.removeValue(forKey: key)
		}
		save()
	}

	private func load() {
		guard
			let data = UserDefaults.standard.data(forKey: defaultsKey),
			let decoded = try? JSONDecoder().decode([String: ViewerKind].self, from: data)
		else { return }
		associations = decoded
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(associations) else { return }
		UserDefaults.standard.set(data, forKey: defaultsKey)
	}
}
