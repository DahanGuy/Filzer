import SwiftUI

struct BookmarksFlyoutView: View {
	let currentPath: String
	let onNavigate: (URL, String?) -> Void

	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var bookmarks: BookmarksStore

	@State private var nodes: [UUID: FileNode] = [:]
	@State private var showingAddBookmark = false
	@State private var editingEntry: BookmarkEntry?

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
		.sheet(item: $editingEntry) { entry in
			NavigationView { AddBookmarkView(editing: entry) }
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
			Button {
				editingEntry = entry
			} label: {
				Label("Edit", systemImage: "pencil")
			}
			.tint(.orange)
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

	private func resolveNode(for entry: BookmarkEntry) async {
		nodes[entry.id] = try? await FileSystem.current.nodeInfo(at: entry.url)
	}

	private func move(fromOffsets source: IndexSet, toOffset destination: Int) {
		var reordered = plainEntries
		reordered.move(fromOffsets: source, toOffset: destination)
		bookmarks.reorderPlainEntries(to: reordered)
	}
}
