import SwiftUI

/// The "Favorites" tab — a reorderable list of pinned files/folders (in-sandbox or
/// externally picked via the document picker). Each row resolves its live `FileNode`
/// on appear so renamed/deleted targets are reflected instead of trusting stale data.
struct BookmarksView: View {
	@EnvironmentObject private var bookmarks: BookmarksStore

	/// Resolved node per bookmark, keyed by `BookmarkEntry.id`. `nil` for an id not yet
	/// resolved; an id present with no node in `nodes` after resolution means the
	/// bookmarked target is missing.
	@State private var nodes: [UUID: FileNode] = [:]

	var body: some View {
		NavigationView {
			Group {
				if bookmarks.entries.isEmpty {
					EmptyStateView(
						icon: "bookmark",
						title: "No Bookmarks",
						message: "Bookmark files and folders from their context menu to see them here."
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
				ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
			}
		}
		.navigationViewStyle(.stack)
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
}
