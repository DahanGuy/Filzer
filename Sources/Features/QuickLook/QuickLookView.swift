import QuickLook
import SwiftUI

/// Fallback viewer for anything without a bespoke editor (PDFs, Office docs, unknown
/// types) — wraps `QLPreviewController`, which already ships its own share/print/markup
/// toolbar, so this stays a thin `UIViewControllerRepresentable` shim.
struct QuickLookView: View {
	let url: URL

	var body: some View {
		QuickLookRepresentable(url: url)
			.navigationTitle(url.lastPathComponent)
			.navigationBarTitleDisplayMode(.inline)
	}
}

/// Bridges `QLPreviewController` into SwiftUI. The data source only ever has one item —
/// the file at `url` — so the coordinator is a minimal, stateless adapter.
private struct QuickLookRepresentable: UIViewControllerRepresentable {
	let url: URL

	func makeCoordinator() -> Coordinator {
		Coordinator(url: url)
	}

	func makeUIViewController(context: Context) -> QLPreviewController {
		let previewController = QLPreviewController()
		previewController.dataSource = context.coordinator
		return previewController
	}

	func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
		// The previewed URL never changes for the lifetime of this view; nothing to sync.
	}

	final class Coordinator: NSObject, QLPreviewControllerDataSource {
		let url: URL

		init(url: URL) {
			self.url = url
		}

		func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
			1
		}

		func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
			url as QLPreviewItem
		}
	}
}
