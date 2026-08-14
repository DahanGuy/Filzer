import PartyUI
import SwiftUI

/// The Settings flyout: quick browsing toggles live inline, everything else
/// (General, Security, File Associations, Backup/Restore, About) is a sub-screen.
struct SettingsView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var settings: SettingsStore

	var body: some View {
		NavigationView {
			List {
				Section(header: HeaderLabel(text: "Browsing", icon: "folder")) {
					PlainToggle(text: "Show Hidden Files", isOn: $settings.showHiddenFiles)
					Picker("View Mode", selection: $settings.viewMode) {
						Text("List").tag(ViewMode.list)
						Text("Grid").tag(ViewMode.grid)
					}
					.pickerStyle(.segmented)
					Picker("Font Size", selection: $settings.fontSize) {
						Text("Small").tag(RowFontSize.small)
						Text("Normal").tag(RowFontSize.normal)
					}
					.pickerStyle(.segmented)
				}

				Section(header: HeaderLabel(text: "Preferences", icon: "gearshape")) {
					NavigationLink(destination: GeneralSettingsView()) {
						NavigationLabel(text: "General", icon: "gear")
					}
					NavigationLink(destination: SecuritySettingsView()) {
						NavigationLabel(text: "Security", icon: "lock")
					}
					NavigationLink(destination: FileAssociationsSettingsView()) {
						NavigationLabel(text: "File Associations", icon: "doc.badge.gearshape")
					}
					NavigationLink(destination: BackupRestoreView()) {
						NavigationLabel(text: "Backup & Restore", icon: "arrow.triangle.2.circlepath")
					}
					NavigationLink(destination: AboutView()) {
						NavigationLabel(text: "About", icon: "info.circle")
					}
				}
			}
			.navigationTitle("Settings")
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
			}
		}
		.navigationViewStyle(.stack)
	}
}
