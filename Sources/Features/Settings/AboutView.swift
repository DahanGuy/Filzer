import PartyUI
import SwiftUI

/// App version info plus credits for the open-source libraries Filzer is built on.
struct AboutView: View {
	var body: some View {
		List {
			Section {
				AppInfoCell(build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
			}

			Section(header: HeaderLabel(text: "Credits", icon: "star")) {
				LinkCreditCell(
					name: "PartyUI",
					description: "The design system Filzer's rows, toggles, and buttons are built with.",
					url: "https://github.com/jailbreakdotparty/PartyUI"
				)
				LinkCreditCell(
					name: "ZIPFoundation",
					description: "Reads and writes the zip archives behind Filzer's compress/extract tools.",
					url: "https://github.com/weichsel/ZIPFoundation"
				)
			}
		}
		.navigationTitle("About")
	}
}
