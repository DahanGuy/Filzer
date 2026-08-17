import PartyUI
import SwiftUI

struct LockScreenView: View {
	@ObservedObject var lockGate: AppLockGate
	@EnvironmentObject private var settings: SettingsStore

	var body: some View {
		VStack(spacing: 20) {
			Spacer()
			Image(systemName: "lock.fill")
				.font(.system(size: 44))
				.foregroundStyle(Color.accentColor)
			Text("Filzer is Locked")
				.font(.title2.bold())
			Spacer()
			Button {
				Task { await lockGate.unlock(settings: settings) }
			} label: {
				ButtonLabel(text: "Unlock", icon: "faceid")
			}
			.buttonStyle(FancyButtonStyle())
			.padding(.horizontal, 32)
		}
		.padding(.bottom, 40)
		.background(Color(.systemBackground))
		.task {
			await lockGate.unlock(settings: settings)
		}
	}
}
