import SwiftUI

/// Filza-style "Recently Deleted" screen for items moved to `TrashStore.directory`.
/// Pushed from Home's own `NavigationView`, so this view does not open one of its own.
struct TrashView: View {
	@EnvironmentObject private var trash: TrashStore

	@State private var errorMessage: String?
	@State private var showingEmptyConfirmation = false

	var body: some View {
		Group {
			if trash.items.isEmpty {
				EmptyStateView(icon: "trash", title: "Trash Is Empty")
			} else {
				List {
					ForEach(trash.items) { node in
						row(for: node)
					}
				}
			}
		}
		.navigationTitle("Trash")
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button("Empty Trash") {
					showingEmptyConfirmation = true
				}
				.disabled(trash.items.isEmpty)
			}
		}
		.confirmationDialog(
			"Permanently erase everything in Trash?",
			isPresented: $showingEmptyConfirmation,
			titleVisibility: .visible
		) {
			Button("Empty Trash", role: .destructive) {
				emptyTrash()
			}
			Button("Cancel", role: .cancel) {}
		}
		.task { await trash.refresh() }
		.errorAlert($errorMessage)
	}

	/// `FileRow` shows `node.name` directly, but Trash stores items under an internal
	/// `UUID_name` filename to avoid collisions — so this substitutes the user-facing
	/// name via `trash.displayName(for:)` on a display-only copy rather than teaching
	/// `FileRow` about Trash's naming scheme.
	private func row(for node: FileNode) -> some View {
		let displayNode = FileNode(
			url: node.url,
			name: trash.displayName(for: node),
			kind: node.kind,
			size: node.size,
			createdAt: node.createdAt,
			modifiedAt: node.modifiedAt,
			posixPermissions: node.posixPermissions,
			ownerAccountName: node.ownerAccountName,
			groupOwnerAccountName: node.groupOwnerAccountName,
			symbolicLinkDestination: node.symbolicLinkDestination,
			isHidden: node.isHidden
		)
		return FileRow(node: displayNode, subtitleOverride: ByteCountFormat.string(for: node.size))
			.swipeActions(edge: .trailing) {
				Button("Delete Forever", role: .destructive) {
					deleteForever(node)
				}
				Button("Put Back") {
					restore(node)
				}
				.tint(.accentColor)
			}
	}

	private func restore(_ node: FileNode) {
		Task {
			do {
				try await trash.restore(node)
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}

	private func deleteForever(_ node: FileNode) {
		Task {
			do {
				try await FileSystem.current.delete([node.url])
				await trash.refresh()
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}

	private func emptyTrash() {
		Task {
			do {
				try await trash.emptyTrash()
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}
}
