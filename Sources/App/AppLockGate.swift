import SwiftUI
import UIKit

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
