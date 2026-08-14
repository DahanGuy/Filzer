import SwiftUI

/// General preferences: the app's color-scheme override.
struct GeneralSettingsView: View {
	@EnvironmentObject private var settings: SettingsStore

	var body: some View {
		List {
			Section {
				Picker("Appearance", selection: $settings.theme) {
					ForEach(AppTheme.allCases) { theme in
						Text(theme.title).tag(theme)
					}
				}
			}
		}
		.navigationTitle("General")
	}
}
