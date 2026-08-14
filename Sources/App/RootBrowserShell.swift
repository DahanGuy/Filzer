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

/// The app's only top-level screen: a single file browser rooted at
/// `settings.launchPath` (configurable in Settings > General, "/" by default) — a
/// real filesystem path, not limited to Filzer's own container. Disks, Bookmarks, and
/// "Go to Path" are how you get to other locations, all reachable from this screen's
/// toolbar.
struct RootBrowserShell: View {
	@EnvironmentObject private var settings: SettingsStore
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var lockGate = AppLockGate()

	var body: some View {
		NavigationView {
			FileBrowserView(rootURL: URL(fileURLWithPath: settings.launchPath), displayName: settings.launchPath, isRoot: true)
		}
		.navigationViewStyle(.stack)
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
