import PartyUI
import SwiftUI

struct AboutView: View {
	var body: some View {
		List {
			Section {
				AppInfoCell(build: "Release")
			}

			Section(header: HeaderLabel(text: "Credits", icon: "star")) {
				LinkCreditCell(
					name: "PartyUI",
					description: "UI library",
					url: "https://github.com/jailbreakdotparty/PartyUI"
				)
				LinkCreditCell(
					name: "ZIPFoundation",
					description: "ZIP support",
					url: "https://github.com/weichsel/ZIPFoundation"
				)
				LinkCreditCell(
					name: "SWCompression",
					description: "TAR/GZIP/BZIP2/7Z extraction",
					url: "https://github.com/tsolomko/SWCompression"
				)
				LinkCreditCell(
					name: "Unrar.swift",
					description: "RAR extraction",
					url: "https://github.com/mtgto/Unrar.swift"
				)
				LinkCreditCell(
					name: "AMSMB2",
					description: "SMB support",
					url: "https://github.com/amosavian/AMSMB2"
				)
				LinkCreditCell(
					name: "Filza",
					description: "Inspiration",
					url: "https://www.tigisoftware.com/default/?page_id=78"
				)
			}
		}
		.navigationTitle("About")
	}
}
