import Foundation
import SwiftUI

/// Drives the optional biometric app-lock: locks on background (if enabled), and
/// re-locks on return to foreground once `lockTimeoutSeconds` has elapsed.
@MainActor
final class AppLockGate: ObservableObject {
	@Published var isLocked = false

	private var backgroundedAt: Date?

	func handleScenePhaseChange(_ phase: ScenePhase, settings: SettingsStore) {
		switch phase {
		case .background:
			backgroundedAt = Date()
			if settings.biometricLockEnabled { isLocked = true }
		case .active:
			guard settings.biometricLockEnabled, !isLocked, let backgroundedAt else { return }
			if Date().timeIntervalSince(backgroundedAt) >= Double(settings.lockTimeoutSeconds) {
				isLocked = true
			}
		default:
			break
		}
	}

	func unlock(settings: SettingsStore) async {
		guard settings.biometricLockEnabled else {
			isLocked = false
			return
		}
		if await BiometricLock.authenticate(reason: "Unlock Filzer") {
			isLocked = false
			backgroundedAt = nil
		}
	}
}
