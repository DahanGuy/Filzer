import PartyUI
import SwiftUI

struct GeneralSettingsView: View {
	@EnvironmentObject private var settings: SettingsStore
	@State private var rootAccessStatus: RootAccessStatus?

	private var rootAccessFooter: String {
		switch rootAccessStatus {
		case .active?:
			return "Filzer is running file operations as root, so protected folders are readable and editable. New items take the owner of the folder they're created in."
		case .unavailable(let reason)?:
			return "Root access isn't available, so Filzer is using regular (mobile) access. \(reason)"
		case .disabled?:
			return "Filzer is using regular (mobile) access."
		case nil:
			return "When enabled, Filzer runs file operations as root for access to protected folders. If root isn't available it falls back to regular (mobile) access."
		}
	}

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

			Section(
				header: HeaderLabel(text: "Privileges", icon: "lock.open"),
				footer: Text(rootAccessFooter)
			) {
				PlainToggle(text: "Run as Root", icon: "lock.open", isOn: $settings.useRootAccess)
			}
		}
		.task(id: settings.useRootAccess) {
			rootAccessStatus = await RootAccess.shared.status()
		}
		.navigationTitle("General")
	}
}
