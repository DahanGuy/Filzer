import UIKit

/// Sileo registers the `sileo://` scheme and handles `.deb` files shared with it, but it has no URL that
/// installs a local package. The package is handed over through the share sheet instead.
enum SileoInstaller {
	@MainActor
	static func isInstalled() -> Bool {
		guard let url = URL(string: "sileo://") else { return false }
		return UIApplication.shared.canOpenURL(url)
	}

	@MainActor
	static func install(_ debURL: URL) -> Bool {
		guard topPresentedViewController() != nil else { return false }
		presentMultiShareSheet(for: [debURL])
		return true
	}
}
