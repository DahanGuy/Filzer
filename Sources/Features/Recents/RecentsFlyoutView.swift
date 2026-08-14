import SwiftUI

/// The Recents flyout — every file opened through `FileViewerRoute`, most recent
/// first (Filza's Recents section). Missing/deleted targets are hidden rather than
/// shown as broken rows, since unlike Bookmarks this list isn't hand-curated.
struct RecentsFlyoutView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var recents: RecentsStore

	@State private var nodes: [UUID: FileNode] = [:]

	private static let relativeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .abbreviated
		return formatter
	}()

	var body: some View {
		Group {
			if recents.entries.isEmpty {
				EmptyStateView(icon: "clock", title: "No Recent Files", message: "Files you open will show up here.")
			} else {
				List {
					ForEach(recents.entries) { entry in
						row(for: entry)
					}
				}
			}
		}
		.navigationTitle("Recents")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
			ToolbarItem(placement: .navigationBarTrailing) {
				if !recents.entries.isEmpty {
					Button("Clear") { recents.clear() }
				}
			}
		}
	}

	@ViewBuilder
	private func row(for entry: RecentEntry) -> some View {
		if let node = nodes[entry.id] {
			NavigationLink(destination: FileViewerRoute(node: node)) {
				HStack {
					FileRow(node: node)
					Spacer()
					Text(Self.relativeFormatter.localizedString(for: entry.openedAt, relativeTo: Date()))
						.font(.caption)
						.foregroundStyle(.tertiary)
				}
			}
			.swipeActions(edge: .trailing) {
				Button(role: .destructive) {
					recents.remove(entry)
				} label: {
					Label("Remove", systemImage: "trash")
				}
			}
			.task(id: entry.id) {
				await resolveNode(for: entry)
			}
		} else {
			EmptyView().task(id: entry.id) { await resolveNode(for: entry) }
		}
	}

	private func resolveNode(for entry: RecentEntry) async {
		nodes[entry.id] = try? await FileSystem.current.nodeInfo(at: entry.url)
	}
}
