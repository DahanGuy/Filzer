import Combine
import Foundation

enum ViewMode: String, Codable, CaseIterable, Identifiable {
	case list
	case grid
	var id: String { rawValue }
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

@MainActor
final class SettingsStore: ObservableObject {
	private enum Keys {
		static let showHiddenFiles = "Filzer.Settings.ShowHiddenFiles"
		static let viewMode = "Filzer.Settings.ViewMode"
		static let theme = "Filzer.Settings.Theme"
		static let sortField = "Filzer.Settings.SortField"
		static let sortAscending = "Filzer.Settings.SortAscending"
		static let biometricLockEnabled = "Filzer.Settings.BiometricLockEnabled"
		static let lockTimeoutSeconds = "Filzer.Settings.LockTimeoutSeconds"
		static let recursiveSearch = "Filzer.Settings.RecursiveSearch"
	}

	@Published var showHiddenFiles: Bool { didSet { defaults.set(showHiddenFiles, forKey: Keys.showHiddenFiles) } }
	@Published var viewMode: ViewMode { didSet { defaults.set(viewMode.rawValue, forKey: Keys.viewMode) } }
	@Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Keys.theme) } }
	@Published var biometricLockEnabled: Bool { didSet { defaults.set(biometricLockEnabled, forKey: Keys.biometricLockEnabled) } }
	@Published var lockTimeoutSeconds: Int { didSet { defaults.set(lockTimeoutSeconds, forKey: Keys.lockTimeoutSeconds) } }
	@Published var recursiveSearch: Bool { didSet { defaults.set(recursiveSearch, forKey: Keys.recursiveSearch) } }

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
		theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
		biometricLockEnabled = defaults.object(forKey: Keys.biometricLockEnabled) as? Bool ?? false
		lockTimeoutSeconds = defaults.object(forKey: Keys.lockTimeoutSeconds) as? Int ?? 60
		recursiveSearch = defaults.object(forKey: Keys.recursiveSearch) as? Bool ?? true
		let field = FileSortField(rawValue: defaults.string(forKey: Keys.sortField) ?? "") ?? .name
		let ascending = defaults.object(forKey: Keys.sortAscending) as? Bool ?? true
		sortDescriptor = FileSortDescriptor(field: field, ascending: ascending)
	}
}
