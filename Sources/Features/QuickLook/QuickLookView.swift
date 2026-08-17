import QuickLook
import SwiftUI

struct QuickLookView: View {
	let url: URL

	var body: some View {
		QuickLookRepresentable(url: url)
			.navigationTitle(url.lastPathComponent)
			.navigationBarTitleDisplayMode(.inline)
	}
}

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
