import SwiftUI

/// Single navigation destination every screen (Browser, Bookmarks, Search, Trash,
/// Archive browser) pushes to when a file is opened. Centralizes viewer routing and
/// Recents tracking so individual viewers stay free of that concern.
struct FileViewerRoute: View {
	let node: FileNode
	/// Overrides the routing decision — used by the context menu's "Open As" submenu.
	var forcedKind: ViewerKind?

	@EnvironmentObject private var fileAssociations: FileAssociationsStore
	@EnvironmentObject private var recents: RecentsStore

	var body: some View {
		viewer
			.onAppear { recents.recordOpen(of: node.url) }
	}

	@ViewBuilder
	private var viewer: some View {
		switch forcedKind ?? fileAssociations.viewer(for: node) {
		case .text: TextEditorView(url: node.url)
		case .hex: HexEditorView(url: node.url)
		case .image: ImageViewerView(url: node.url)
		case .media: MediaPlayerView(url: node.url)
		case .web: WebViewerView(url: node.url)
		case .propertyList: PlistEditorView(url: node.url)
		case .sqlite: SQLiteViewerView(url: node.url)
		case .archive: ArchiveBrowserView(url: node.url)
		case .quickLook: QuickLookView(url: node.url)
		}
	}
}
