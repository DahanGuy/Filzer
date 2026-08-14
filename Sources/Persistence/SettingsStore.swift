import Combine
import Foundation

enum ViewMode: String, Codable, CaseIterable, Identifiable {
	case list
	case grid
	var id: String { rawValue }
}

enum RowFontSize: String, Codable, CaseIterable, Identifiable {
	case small
	case normal
	var id: String { rawValue }
	var title: String { self == .small ? "Small" : "Normal" }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
	case system
	case light
	case dark
	var id: String { rawValue }
	var title: String {
		switch self {
		case .system: return "System"
		case .light: return "Light"
		case .dark: return "Dark"
		}
	}
}

/// A JSON-friendly snapshot of every preference, for the Settings > Backup/Restore
/// export-to-file / import-from-file flow.
struct SettingsSnapshot: Codable {
	var showHiddenFiles: Bool
	var viewMode: ViewMode
	var fontSize: RowFontSize
	var theme: AppTheme
	var sortField: FileSortField
	var sortAscending: Bool
	var biometricLockEnabled: Bool
	var lockTimeoutSeconds: Int
}

/// App-wide preferences, backed by `UserDefaults`. Every property persists itself on
/// change via `didSet` — call sites just assign, same as any other `@Published` value.
@MainActor
final class SettingsStore: ObservableObject {
	private enum Keys {
		static let showHiddenFiles = "Filzer.Settings.ShowHiddenFiles"
		static let viewMode = "Filzer.Settings.ViewMode"
		static let fontSize = "Filzer.Settings.FontSize"
		static let theme = "Filzer.Settings.Theme"
		static let sortField = "Filzer.Settings.SortField"
		static let sortAscending = "Filzer.Settings.SortAscending"
		static let biometricLockEnabled = "Filzer.Settings.BiometricLockEnabled"
		static let lockTimeoutSeconds = "Filzer.Settings.LockTimeoutSeconds"
	}

	@Published var showHiddenFiles: Bool { didSet { defaults.set(showHiddenFiles, forKey: Keys.showHiddenFiles) } }
	@Published var viewMode: ViewMode { didSet { defaults.set(viewMode.rawValue, forKey: Keys.viewMode) } }
	@Published var fontSize: RowFontSize { didSet { defaults.set(fontSize.rawValue, forKey: Keys.fontSize) } }
	@Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Keys.theme) } }
	@Published var biometricLockEnabled: Bool { didSet { defaults.set(biometricLockEnabled, forKey: Keys.biometricLockEnabled) } }
	@Published var lockTimeoutSeconds: Int { didSet { defaults.set(lockTimeoutSeconds, forKey: Keys.lockTimeoutSeconds) } }

	@Published var sortDescriptor: FileSortDescriptor {
		didSet {
			defaults.set(sortDescriptor.field.rawValue, forKey: Keys.sortField)
			defaults.set(sortDescriptor.ascending, forKey: Keys.sortAscending)
		}
	}

	private let defaults: UserDefaults

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		showHiddenFiles = defaults.object(forKey: Keys.showHiddenFiles) as? Bool ?? false
		viewMode = ViewMode(rawValue: defaults.string(forKey: Keys.viewMode) ?? "") ?? .list
		fontSize = RowFontSize(rawValue: defaults.string(forKey: Keys.fontSize) ?? "") ?? .normal
		theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
		biometricLockEnabled = defaults.object(forKey: Keys.biometricLockEnabled) as? Bool ?? false
		lockTimeoutSeconds = defaults.object(forKey: Keys.lockTimeoutSeconds) as? Int ?? 60
		let field = FileSortField(rawValue: defaults.string(forKey: Keys.sortField) ?? "") ?? .name
		let ascending = defaults.object(forKey: Keys.sortAscending) as? Bool ?? true
		sortDescriptor = FileSortDescriptor(field: field, ascending: ascending)
	}

	var snapshot: SettingsSnapshot {
		SettingsSnapshot(
			showHiddenFiles: showHiddenFiles,
			viewMode: viewMode,
			fontSize: fontSize,
			theme: theme,
			sortField: sortDescriptor.field,
			sortAscending: sortDescriptor.ascending,
			biometricLockEnabled: biometricLockEnabled,
			lockTimeoutSeconds: lockTimeoutSeconds
		)
	}

	func apply(_ snapshot: SettingsSnapshot) {
		showHiddenFiles = snapshot.showHiddenFiles
		viewMode = snapshot.viewMode
		fontSize = snapshot.fontSize
		theme = snapshot.theme
		sortDescriptor = FileSortDescriptor(field: snapshot.sortField, ascending: snapshot.sortAscending)
		biometricLockEnabled = snapshot.biometricLockEnabled
		lockTimeoutSeconds = snapshot.lockTimeoutSeconds
	}

	/// Encodes every preference for the Backup/Restore "export to file" action. The
	/// caller writes the returned bytes through `FileSystemEngine` — this store never
	/// touches the filesystem directly.
	func exportData() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(snapshot)
	}

	func importData(_ data: Data) throws {
		apply(try JSONDecoder().decode(SettingsSnapshot.self, from: data))
	}
}
