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

/// The app's only top-level screen: a single file browser rooted at "/" — a real
/// filesystem path, not limited to Filzer's own container. Disks and Bookmarks are
/// how you get to other locations, both reachable from this screen's toolbar.
///
/// The biometric lock itself isn't presented here — see `AppLockGate`, which shows
/// its own top-level `UIWindow` rather than a SwiftUI `.fullScreenCover`.
struct RootBrowserShell: View {
	@EnvironmentObject private var settings: SettingsStore
	@StateObject private var lockGate = AppLockGate()

	var body: some View {
		NavigationView {
			FileBrowserView(rootURL: URL(fileURLWithPath: "/"), isRoot: true)
		}
		.navigationViewStyle(.stack)
		.preferredColorScheme(settings.theme.colorScheme)
		.onAppear {
			lockGate.configure(settings: settings)
		}
	}
}
