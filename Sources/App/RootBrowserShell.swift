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

/// The app's only top-level screen: a single file browser rooted at "/" — the whole
/// filesystem, not a curated list of locations. Most of it will be inaccessible (this
/// is a sandboxed app), which is expected; Disks, Bookmarks, and "Go to Path" are how
/// you actually get somewhere useful, all reachable from this one screen's toolbar.
struct RootBrowserShell: View {
	@EnvironmentObject private var settings: SettingsStore
	@Environment(\.scenePhase) private var scenePhase
	@StateObject private var lockGate = AppLockGate()

	var body: some View {
		NavigationView {
			FileBrowserView(rootURL: URL(fileURLWithPath: "/"), displayName: "/", isRoot: true)
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
