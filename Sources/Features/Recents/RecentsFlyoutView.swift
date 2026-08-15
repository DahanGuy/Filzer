import SwiftUI

/// The Recents flyout — every file opened through `FileViewerRoute`, most recent
/// first (Filza's Recents section). A target that fails to resolve (deleted, or a
/// security-scoped location whose grant didn't survive a relaunch) still shows its
/// own row, marked inaccessible, instead of silently vanishing - the previous
/// behavior left the list looking empty or broken even though entries existed.
struct RecentsFlyoutView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var recents: RecentsStore

	/// Resolved node per entry, keyed by `RecentEntry.id`. An id present in
	/// `failedIDs` instead means resolution finished but found nothing usable.
	@State private var nodes: [UUID: FileNode] = [:]
	@State private var failedIDs: Set<UUID> = []

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
		Group {
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
			} else if failedIDs.contains(entry.id) {
				HStack(spacing: 12) {
					Image(systemName: "exclamationmark.triangle")
						.foregroundStyle(.secondary)
						.frame(width: Theme.rowIconSize, height: Theme.rowIconSize)
					VStack(alignment: .leading, spacing: 2) {
						Text(entry.url.lastPathComponent)
							.foregroundStyle(Color(.label))
						Text("No longer accessible")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			} else {
				HStack {
					ProgressView()
					Text(entry.url.lastPathComponent).foregroundStyle(.secondary)
				}
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
	}

	private func resolveNode(for entry: RecentEntry) async {
		guard nodes[entry.id] == nil, !failedIDs.contains(entry.id) else { return }
		if let node = try? await FileSystem.current.nodeInfo(at: entry.url) {
			nodes[entry.id] = node
		} else {
			failedIDs.insert(entry.id)
		}
	}
}
