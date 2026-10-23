import SwiftUI
import UIKit

@MainActor
func topPresentedViewController() -> UIViewController? {
	guard
		let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
		var topController = scene.windows.first(where: \.isKeyWindow)?.rootViewController
	else { return nil }
	while let presented = topController.presentedViewController {
		topController = presented
	}
	return topController
}

@MainActor
func presentMultiShareSheet(for urls: [URL]) {
	guard !urls.isEmpty, let topController = topPresentedViewController() else { return }

	let activityController = UIActivityViewController(activityItems: urls, applicationActivities: nil)
	if let popover = activityController.popoverPresentationController {
		popover.sourceView = topController.view
		popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
		popover.permittedArrowDirections = []
	}
	topController.present(activityController, animated: true)
}
