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
