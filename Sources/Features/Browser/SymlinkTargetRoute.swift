import SwiftUI

/// Pushed when the user taps a symbolic link. `FileNode.make` always classifies a link
/// itself as `.symbolicLink` regardless of what it points to (a link is a leaf, so
/// recursive traversals never risk a cycle) — so whether the *target* is a folder to
/// browse into or a file to view isn't known until the link is dereferenced here, one
/// level, fresh.
struct SymlinkTargetRoute: View {
	let node: FileNode

	@State private var resolvedNode: FileNode?
	@State private var errorMessage: String?

	var body: some View {
		Group {
			if let resolvedNode {
				destination(for: resolvedNode)
			} else if let errorMessage {
				EmptyStateView(icon: "questionmark.folder", title: "Broken Link", message: errorMessage)
			} else {
				ProgressView()
			}
		}
		.task { await resolve() }
	}

	@ViewBuilder
	private func destination(for resolved: FileNode) -> some View {
		if resolved.isDirectory {
			FileBrowserView(rootURL: resolved.url, displayName: node.name)
		} else {
			FileViewerRoute(node: resolved)
		}
	}

	private func resolve() async {
		guard let target = node.symbolicLinkDestination else {
			errorMessage = "This link has no destination."
			return
		}
		do {
			resolvedNode = try await FileSystem.current.nodeInfo(at: target)
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
