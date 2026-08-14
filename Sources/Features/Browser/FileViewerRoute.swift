import SwiftUI

/// Single navigation destination every screen (Browser, Bookmarks, Recents, Archive
/// browser) pushes to when a file is opened. Centralizes viewer routing, Recents
/// tracking, and — for viewer kinds that bypass `FileSystemEngine` and touch a system
/// framework directly (`ViewerKind.requiresLocalFile`) — materializing remote content
/// to a real local file first, since AVKit/WKWebView/sqlite3/the archive libraries
/// cannot be handed a `filzer-remote://` URL.
struct FileViewerRoute: View {
	let node: FileNode
	/// Overrides the routing decision — used by the context menu's "Open As" submenu.
	var forcedKind: ViewerKind?

	@EnvironmentObject private var fileAssociations: FileAssociationsStore
	@EnvironmentObject private var recents: RecentsStore

	@State private var materializedURL: URL?
	@State private var isTemporary = false
	@State private var errorMessage: String?

	private var kind: ViewerKind { forcedKind ?? fileAssociations.viewer(for: node) }

	var body: some View {
		Group {
			if kind.requiresLocalFile {
				if let materializedURL {
					viewer(url: materializedURL)
				} else if let errorMessage {
					EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn't Open File", message: errorMessage)
				} else {
					ProgressView()
				}
			} else {
				viewer(url: node.url)
			}
		}
		.onAppear { recents.recordOpen(of: node.url) }
		.task {
			guard kind.requiresLocalFile, materializedURL == nil else { return }
			do {
				let (url, temporary) = try await FileSystem.current.materializeLocally(node.url)
				materializedURL = url
				isTemporary = temporary
			} catch {
				errorMessage = error.localizedDescription
			}
		}
		.onDisappear {
			guard isTemporary, let materializedURL else { return }
			try? FileManager.default.removeItem(at: materializedURL.deletingLastPathComponent())
		}
	}

	@ViewBuilder
	private func viewer(url: URL) -> some View {
		switch kind {
		case .text: TextEditorView(url: url)
		case .hex: HexEditorView(url: url)
		case .image: ImageViewerView(url: url)
		case .media: MediaPlayerView(url: url)
		case .web: WebViewerView(url: url)
		case .propertyList: PlistEditorView(url: url)
		case .sqlite: SQLiteViewerView(url: url)
		case .archive: ArchiveBrowserView(url: url)
		case .quickLook: QuickLookView(url: url)
		case .ipa: IPAInspectorView(url: url)
		case .mobileProvision: MobileProvisionView(url: url)
		}
	}
}
