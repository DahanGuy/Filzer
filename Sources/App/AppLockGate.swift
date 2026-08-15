import SwiftUI
import UIKit

/// Drives the optional biometric app-lock by showing `LockScreenView` in its own
/// top-level `UIWindow` instead of a SwiftUI `.fullScreenCover`.
///
/// A `.fullScreenCover` has to animate in, and if the app is swiped away fast enough
/// that slide-up transition can still be mid-flight - or queued behind whatever
/// popover/sheet/alert already happened to be open - when the App Switcher actually
/// captures its preview snapshot, letting file contents through. A separate window at
/// a level above everything else, shown by flipping `isHidden` (never animated, and
/// never waiting on any other presentation to dismiss first), appears instantly no
/// matter what was on screen.
///
/// It's also driven by raw `UIApplication.willResignActiveNotification`/
/// `didBecomeActiveNotification` rather than SwiftUI's `scenePhase`: those fire
/// synchronously from `UIApplicationDelegate` callbacks, ahead of SwiftUI's own
/// dispatch-batched view updates, which is exactly the margin that matters here.
@MainActor
final class AppLockGate: ObservableObject {
	@Published var isLocked = false

	private var settings: SettingsStore?
	private var backgroundedAt: Date?
	private var overlayWindow: UIWindow?
	private var observers: [NSObjectProtocol] = []

	deinit {
		observers.forEach(NotificationCenter.default.removeObserver)
	}

	/// Wires up notification observers and performs the cold-launch lock check. Safe
	/// to call multiple times — only the first call does anything.
	func configure(settings: SettingsStore) {
		guard self.settings == nil else { return }
		self.settings = settings

		observers = [
			NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.handleWillResignActive() }
			},
			NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.handleDidBecomeActive() }
			},
		]

		if settings.biometricLockEnabled {
			isLocked = true
			showOverlayInstantly()
		}
	}

	private func handleWillResignActive() {
		guard let settings, settings.biometricLockEnabled else { return }
		backgroundedAt = backgroundedAt ?? Date()
		isLocked = true
		showOverlayInstantly()
	}

	private func handleDidBecomeActive() {
		guard let settings, settings.biometricLockEnabled, let backgroundedAt else { return }
		if Date().timeIntervalSince(backgroundedAt) < Double(settings.lockTimeoutSeconds) {
			isLocked = false
			self.backgroundedAt = nil
			hideOverlayInstantly()
		}
		// Otherwise stays locked - the overlay's own LockScreenView.task already
		// prompts Face ID/Touch ID as soon as it's on screen.
	}

	private func showOverlayInstantly() {
		guard overlayWindow == nil, let settings else { return }
		guard
			let scene = UIApplication.shared.connectedScenes
				.first(where: { $0.activationState != .background }) as? UIWindowScene
		else { return }

		let window = UIWindow(windowScene: scene)
		window.windowLevel = .alert + 1
		window.backgroundColor = .systemBackground
		let hosting = UIHostingController(
			rootView: LockScreenView(lockGate: self)
				.environmentObject(settings)
				.preferredColorScheme(settings.theme.colorScheme)
		)
		hosting.view.backgroundColor = .systemBackground
		window.rootViewController = hosting
		window.isHidden = false
		overlayWindow = window
	}

	private func hideOverlayInstantly() {
		overlayWindow?.isHidden = true
		overlayWindow = nil
	}

	func unlock(settings: SettingsStore) async {
		guard settings.biometricLockEnabled else {
			isLocked = false
			hideOverlayInstantly()
			return
		}
		if await BiometricLock.authenticate(reason: "Unlock Filzer") {
			isLocked = false
			backgroundedAt = nil
			hideOverlayInstantly()
		}
	}
}
