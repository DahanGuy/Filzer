import SwiftUI

/// General preferences: the app's color-scheme override and whether search recurses
/// into subfolders.
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

			Section(
				header: Text("Search"),
				footer: Text("When on, search also looks inside every subfolder of the one you're searching from, not just its own listing.")
			) {
				Toggle("Search Subfolders", isOn: $settings.recursiveSearch)
			}
		}
		.navigationTitle("General")
	}
}
