import SwiftUI
import PartyUI

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

#Preview {
	ContentView()
}
