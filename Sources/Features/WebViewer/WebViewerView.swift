import PartyUI
import SwiftUI
import WebKit

struct WebViewerView: View {
	let url: URL

	@State private var isLoading = true
	@State private var reloadToken = UUID()

	var body: some View {
		ZStack {
			WebContentView(url: url, reloadToken: reloadToken, isLoading: $isLoading)
			if isLoading {
				ProgressView()
			}
		}
		.navigationTitle(url.lastPathComponent)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					presentShareSheet(with: url)
				} label: {
					Image(systemName: "square.and.arrow.up")
				}
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					isLoading = true
					reloadToken = UUID()
				} label: {
					Image(systemName: "arrow.clockwise")
				}
			}
		}
	}
}

private struct WebContentView: UIViewRepresentable {
	let url: URL
	let reloadToken: UUID
	@Binding var isLoading: Bool

	func makeUIView(context: Context) -> WKWebView {
		let webView = WKWebView()
		webView.navigationDelegate = context.coordinator
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		guard context.coordinator.loadedToken != reloadToken else { return }
		context.coordinator.loadedToken = reloadToken
		webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(isLoading: $isLoading)
	}

	final class Coordinator: NSObject, WKNavigationDelegate {
		var loadedToken: UUID?
		@Binding var isLoading: Bool

		init(isLoading: Binding<Bool>) {
			_isLoading = isLoading
		}

		func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
			isLoading = false
		}

		func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
			isLoading = false
		}

		func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
			isLoading = false
		}
	}
}
