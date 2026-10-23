import UIKit

/// Sileo registers the `sileo://` scheme and opens `.deb` files shared with it, but it has no URL that
/// installs a local package. The package is handed over through the iOS "Open In" menu instead.
enum SileoInstaller {
	@MainActor
	static func isInstalled() -> Bool {
		guard let url = URL(string: "sileo://") else { return false }
		return UIApplication.shared.canOpenURL(url)
	}

	@MainActor
	static func install(_ debURL: URL) -> Bool {
		OpenInPresenter.shared.present(debURL)
	}
}

@MainActor
final class OpenInPresenter: NSObject, UIDocumentInteractionControllerDelegate {
	static let shared = OpenInPresenter()

	private var controller: UIDocumentInteractionController?

	func present(_ fileURL: URL) -> Bool {
		guard let topController = topPresentedViewController() else { return false }
		let controller = UIDocumentInteractionController(url: fileURL)
		controller.delegate = self
		self.controller = controller

		let sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
		let presented = controller.presentOpenInMenu(from: sourceRect, in: topController.view, animated: true)
		if !presented { self.controller = nil }
		return presented
	}

	func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
		self.controller = nil
	}
}
