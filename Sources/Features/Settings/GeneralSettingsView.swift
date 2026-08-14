import SwiftUI

/// General preferences: which folder Home lands on by default, and the app's
/// color-scheme override.
struct GeneralSettingsView: View {
	@EnvironmentObject private var settings: SettingsStore
	@EnvironmentObject private var bookmarks: BookmarksStore

	var body: some View {
		List {
			Section(footer: Text("The folder Home opens to on launch.")) {
				Picker("Home Directory", selection: $settings.homeBookmarkID) {
					Text("Filzer").tag(UUID?.none)
					ForEach(bookmarks.entries) { entry in
						Text(entry.displayName).tag(Optional(entry.id))
					}
				}
			}

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
