import SwiftUI

/// General preferences: the app's color-scheme override, and the absolute path
/// `RootBrowserShell` opens to on launch.
struct GeneralSettingsView: View {
	@EnvironmentObject private var settings: SettingsStore
	@State private var launchPath: String = ""

	var body: some View {
		List {
			Section {
				Picker("Appearance", selection: $settings.theme) {
					ForEach(AppTheme.allCases) { theme in
						Text(theme.title).tag(theme)
					}
				}
			}

			Section(
				header: Text("Launch Location"),
				footer: Text("The absolute path Filzer opens to on launch, e.g. /private/var/mobile.")
			) {
				TextField("/", text: $launchPath)
					.autocapitalization(.none)
					.disableAutocorrection(true)
					.onChange(of: launchPath) { _ in commitLaunchPath() }
			}
		}
		.navigationTitle("General")
		.onAppear { launchPath = settings.launchPath }
	}

	private func commitLaunchPath() {
		let trimmed = launchPath.trimmingCharacters(in: .whitespacesAndNewlines)
		settings.launchPath = trimmed.isEmpty ? "/" : trimmed
	}
}
