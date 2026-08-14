import SwiftUI
// PartyUI (github.com/jailbreakdotparty/PartyUI) is vendored under Vendor/PartyUI
// and compiled straight into this module by the Makefile, so its public types
// (HeaderLabel, SectionPlatter, FancyButtonStyle, ...) are usable with no import.

struct ContentView: View {
	var body: some View {
		VStack(spacing: 20) {
			HeaderLabel(text: "Filzer", icon: "globe")
				.font(.title2.bold())

			Text("Hello, world!")
				.modifier(SectionPlatter())

			Button("Get Started") {}
				.buttonStyle(FancyButtonStyle())
		}
		.padding()
	}
}
