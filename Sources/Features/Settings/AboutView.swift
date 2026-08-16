import PartyUI
import SwiftUI

struct AboutView: View {
	var body: some View {
		List {
			Section {
				AppInfoCell(build: "Beta")
			}

			Section(header: HeaderLabel(text: "Credits", icon: "star")) {
				LinkCreditCell(
					name: "PartyUI",
					description: "The design system the app was built with.",
					url: "https://github.com/jailbreakdotparty/PartyUI"
				)
				LinkCreditCell(
					name: "ZIPFoundation",
					description: "Effortless ZIP Handling in Swift",
					url: "https://github.com/weichsel/ZIPFoundation"
				)
				LinkCreditCell(
					name: "SWCompression",
					description: "A Swift framework for working with compression, archives and containers.",
					url: "https://github.com/tsolomko/SWCompression"
				)
				LinkCreditCell(
					name: "Unrar.swift",
					description: "Swift library wraps unrar C++ library provided by rarlib.",
					url: "https://github.com/mtgto/Unrar.swift"
				)
				LinkCreditCell(
					name: "AMSMB2",
					description: "Swift framework to connect SMB2/3 shares",
					url: "https://github.com/amosavian/AMSMB2"
				)
			}
		}
		.navigationTitle("About")
	}
}
