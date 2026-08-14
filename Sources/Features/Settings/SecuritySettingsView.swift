import PartyUI
import SwiftUI

/// Biometric app-lock configuration. Hidden entirely (replaced with an
/// explanatory empty state) on devices where `BiometricLock` has nothing to offer.
struct SecuritySettingsView: View {
	@EnvironmentObject private var settings: SettingsStore
	@State private var availability: BiometricLock.Availability = .unavailable

	var body: some View {
		Group {
			switch availability {
			case .unavailable:
				EmptyStateView(
					icon: "lock.slash",
					title: "Biometric Lock Unavailable",
					message: "This device has no Face ID, Touch ID, or passcode configured, so Filzer can't lock behind one."
				)
			case .available(let kind):
				List {
					Section {
						PlainToggle(text: lockToggleText(for: kind), isOn: $settings.biometricLockEnabled)
						if settings.biometricLockEnabled {
							Picker("Lock After", selection: $settings.lockTimeoutSeconds) {
								Text("Immediately").tag(0)
								Text("30 Seconds").tag(30)
								Text("1 Minute").tag(60)
								Text("5 Minutes").tag(300)
							}
						}
					}
				}
			}
		}
		.navigationTitle("Security")
		.task {
			availability = BiometricLock.availability()
		}
	}

	private func lockToggleText(for kind: BiometricLock.Kind) -> String {
		switch kind {
		case .faceID: return "Face ID"
		case .touchID: return "Touch ID"
		case .passcodeOnly: return "Passcode"
		}
	}
}
