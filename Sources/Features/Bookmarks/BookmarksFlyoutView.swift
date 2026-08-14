import SwiftUI

/// The Bookmarks flyout — a reorderable list of pinned paths, added by typing a path
/// (see `AddBookmarkView`) or from any row's context menu. Externally-picked "Added
/// Folders" (via the document picker, needing a security-scoped bookmark) live in the
/// Disks flyout instead — see `plainEntries` below for the split. Each row resolves
/// its live `FileNode` on appear so renamed/deleted targets are reflected instead of
/// trusting stale data.
struct BookmarksFlyoutView: View {
	/// The folder that was open in the presenting `FileBrowserView` — prefills
	/// `AddBookmarkView`'s path field.
	let currentPath: String
	/// Called when a bookmarked *folder* is tapped, instead of pushing it inside this
	/// flyout's own navigation stack — the presenter dismisses this popover and opens
	/// the folder in its own (main) screen. File bookmarks are unaffected: they still
	/// push a viewer within this flyout, matching "view then dismiss".
	let onNavigate: (URL, String?) -> Void

	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var bookmarks: BookmarksStore

	/// Resolved node per bookmark, keyed by `BookmarkEntry.id`. `nil` for an id not yet
	/// resolved; an id present with no node in `nodes` after resolution means the
	/// bookmarked target is missing.
	@State private var nodes: [UUID: FileNode] = [:]
	@State private var showingAddBookmark = false

	/// Plain bookmarks only — externally-picked "Added Folders" (which carry a
	/// security-scoped bookmark) are Disks' concern, not this screen's.
	private var plainEntries: [BookmarkEntry] {
		bookmarks.entries.filter { $0.securityScopedBookmarkData == nil }
	}

	var body: some View {
		Group {
			if plainEntries.isEmpty {
				EmptyStateView(
					icon: "bookmark",
					title: "No Bookmarks",
					message: "Bookmark a path with the + button, or from any file's context menu."
				)
			} else {
				List {
					ForEach(plainEntries) { entry in
						row(for: entry)
					}
					.onMove(perform: move)
				}
			}
		}
		.navigationTitle("Bookmarks")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
			ToolbarItem(placement: .navigationBarTrailing) {
				HStack(spacing: 18) {
					EditButton()
					Button { showingAddBookmark = true } label: { Image(systemName: "plus") }
				}
			}
		}
		.sheet(isPresented: $showingAddBookmark) {
			NavigationView { AddBookmarkView(initialPath: currentPath) }
				.navigationViewStyle(.stack)
		}
	}

	@ViewBuilder
	private func row(for entry: BookmarkEntry) -> some View {
		Group {
			if let node = nodes[entry.id] {
				if node.isDirectory {
					Button {
						onNavigate(node.url, entry.displayName)
						dismiss()
					} label: {
						FileRow(node: node)
					}
					.buttonStyle(.plain)
				} else {
					NavigationLink(destination: FileViewerRoute(node: node)) {
						FileRow(node: node)
					}
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

	/// Resolves an entry's live `FileNode`.
	private func resolveNode(for entry: BookmarkEntry) async {
		nodes[entry.id] = try? await FileSystem.current.nodeInfo(at: entry.url)
	}

	/// `.onMove` gives offsets within `plainEntries` (the filtered, visible
	/// subsequence) — reorder that subsequence in memory, then hand the result to
	/// `BookmarksStore` to merge back into the full array.
	private func move(fromOffsets source: IndexSet, toOffset destination: Int) {
		var reordered = plainEntries
		reordered.move(fromOffsets: source, toOffset: destination)
		bookmarks.reorderPlainEntries(to: reordered)
	}
}
