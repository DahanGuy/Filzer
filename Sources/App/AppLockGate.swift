import Foundation
import SwiftUI

/// Drives the optional biometric app-lock. Two separate concerns, deliberately not
/// conflated:
/// - **Hiding content from the App Switcher.** `isLocked` goes true the instant the
///   scene leaves `.active` (`.inactive`, not `.background` - `.inactive` is what
///   fires *before* the App Switcher's preview snapshot is captured; waiting for
///   `.background` would already be too late to cover anything sensitive on screen).
///   This happens unconditionally whenever the lock is enabled, regardless of
///   `lockTimeoutSeconds`.
/// - **Whether returning needs Face ID/Touch ID.** Decided separately on `.active`,
///   by comparing elapsed time against `lockTimeoutSeconds`: within the grace period,
///   the cover clears on its own; past it, it stays up until `unlock(settings:)`
///   succeeds.
@MainActor
final class AppLockGate: ObservableObject {
	@Published var isLocked = false

	private var backgroundedAt: Date?

	func handleScenePhaseChange(_ phase: ScenePhase, settings: SettingsStore) {
		guard settings.biometricLockEnabled else { return }
		switch phase {
		case .inactive, .background:
			backgroundedAt = backgroundedAt ?? Date()
			isLocked = true
		case .active:
			guard let backgroundedAt else { return }
			if Date().timeIntervalSince(backgroundedAt) < Double(settings.lockTimeoutSeconds) {
				isLocked = false
				self.backgroundedAt = nil
			}
		@unknown default:
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
