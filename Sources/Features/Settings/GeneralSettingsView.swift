import PartyUI
import SwiftUI

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
				header: HeaderLabel(text: "Search", icon: "text.magnifyingglass"),
				footer: Text("When enabled, search also looks inside every subfolder of the one you're searching from.")
			) {
				PlainToggle(text: "Search Subfolders", icon: "arrow.triangle.branch", isOn: $settings.recursiveSearch)
			}
		}
		.navigationTitle("General")
	}
}
