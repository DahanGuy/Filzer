import SwiftUI

extension AppTheme {
	var colorScheme: ColorScheme? {
		switch self {
		case .system: return nil
		case .light: return .light
		case .dark: return .dark
		}
	}
}

/// The app's tab-bar shell: Home / Bookmarks / Search / Settings — the sandboxed
/// equivalent of Filza's Home, Favorites, Search, and Settings icon-bar entries.
struct RootTabView: View {
	@EnvironmentObject private var settings: SettingsStore
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var lockGate = AppLockGate()

	var body: some View {
		TabView {
			HomeView()
				.tabItem { Label("Home", systemImage: "house.fill") }

			BookmarksView()
				.tabItem { Label("Bookmarks", systemImage: "bookmark.fill") }

			SearchView()
				.tabItem { Label("Search", systemImage: "magnifyingglass") }

			SettingsView()
				.tabItem { Label("Settings", systemImage: "gearshape.fill") }
		}
		.preferredColorScheme(settings.theme.colorScheme)
		.onAppear {
			if settings.biometricLockEnabled { lockGate.isLocked = true }
		}
		.onChange(of: scenePhase) { newPhase in
			lockGate.handleScenePhaseChange(newPhase, settings: settings)
		}
		.fullScreenCover(isPresented: $lockGate.isLocked) {
			LockScreenView(lockGate: lockGate)
		}
	}
}
