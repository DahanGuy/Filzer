import SwiftUI
import UniformTypeIdentifiers

/// The Bookmarks flyout — a reorderable list of pinned files/folders (in-sandbox, or
/// externally picked via the document picker and labeled "External Location", matching
/// Filza's "Add Location" convention). Each row resolves its live `FileNode` on appear
/// so renamed/deleted targets are reflected instead of trusting stale data.
struct BookmarksFlyoutView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var bookmarks: BookmarksStore

	/// Resolved node per bookmark, keyed by `BookmarkEntry.id`. `nil` for an id not yet
	/// resolved; an id present with no node in `nodes` after resolution means the
	/// bookmarked target is missing.
	@State private var nodes: [UUID: FileNode] = [:]
	@State private var showingAddLocation = false
	@State private var errorMessage: String?

	var body: some View {
		Group {
			if bookmarks.entries.isEmpty {
				EmptyStateView(
					icon: "bookmark",
					title: "No Bookmarks",
					message: "Bookmark files and folders from their context menu, or add an external location below."
				)
			} else {
				List {
					ForEach(bookmarks.entries) { entry in
						row(for: entry)
					}
					.onMove(perform: bookmarks.move(fromOffsets:toOffset:))
				}
			}
		}
		.navigationTitle("Bookmarks")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
			ToolbarItem(placement: .navigationBarTrailing) {
				HStack(spacing: 18) {
					EditButton()
					Button { showingAddLocation = true } label: { Image(systemName: "plus") }
				}
			}
		}
		.fileImporter(isPresented: $showingAddLocation, allowedContentTypes: [.folder]) { result in
			Task { await addLocation(result: result) }
		}
		.errorAlert($errorMessage)
	}

	@ViewBuilder
	private func row(for entry: BookmarkEntry) -> some View {
		Group {
			if let node = nodes[entry.id] {
				NavigationLink(destination: destination(for: node, entry: entry)) {
					FileRow(node: node)
				}
			} else {
				missingRow(for: entry)
			}
		}
		.swipeActions(edge: .trailing) {
			Button(role: .destructive) {
				bookmarks.remove(entry)
			} label: {
				Label("Delete", systemImage: "trash")
			}
		}
		.task(id: entry.id) {
			await resolveNode(for: entry)
		}
	}

	private func missingRow(for entry: BookmarkEntry) -> some View {
		HStack(spacing: 12) {
			Image(systemName: "questionmark.folder")
				.foregroundStyle(.tertiary)
				.frame(width: Theme.rowIconSize, height: Theme.rowIconSize)

			VStack(alignment: .leading, spacing: 2) {
				Text(entry.displayName)
					.foregroundStyle(Color(.label))
				Text("Missing")
					.font(.caption)
					.foregroundStyle(.red)
			}
		}
	}

	@ViewBuilder
	private func destination(for node: FileNode, entry: BookmarkEntry) -> some View {
		if node.isDirectory {
			FileBrowserView(rootURL: node.url, displayName: entry.displayName)
		} else {
			FileViewerRoute(node: node)
		}
	}

	/// Resolves an entry's live `FileNode`, starting security-scoped access first when
	/// the entry points outside Filzer's own sandbox container.
	private func resolveNode(for entry: BookmarkEntry) async {
		let url = bookmarks.resolvedURL(for: entry)
		let needsScopedAccess = entry.securityScopedBookmarkData != nil
		let didStartAccessing = needsScopedAccess ? url.startAccessingSecurityScopedResource() : false
		defer {
			if didStartAccessing { url.stopAccessingSecurityScopedResource() }
		}
		nodes[entry.id] = try? await FileSystem.current.nodeInfo(at: url)
	}

	/// "Add Location" — Filza's term for pinning a folder the app has no innate access
	/// to. The document picker grants a one-time security-scoped grant; the bookmark
	/// data persisted here is what makes that grant durable across launches.
	private func addLocation(result: Result<[URL], Error>) async {
		do {
			guard let url = try result.get().first else { return }
			let didStartAccessing = url.startAccessingSecurityScopedResource()
			defer {
				if didStartAccessing { url.stopAccessingSecurityScopedResource() }
			}
			let bookmarkData = try SecurityScopedBookmark.makeBookmark(for: url)
			bookmarks.add(url: url, displayName: "\(url.lastPathComponent) (External Location)", securityScopedBookmarkData: bookmarkData)
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
