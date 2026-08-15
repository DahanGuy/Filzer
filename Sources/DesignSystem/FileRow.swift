import SwiftUI

/// The standard file/folder row used by the browser, bookmarks, search, trash, and the
/// zip viewer. Selection UI is opt-in via `selection` so single-select contexts (e.g.
/// Bookmarks) don't pay for it.
struct FileRow: View {
	let node: FileNode
	var subtitleOverride: String?
	/// Non-nil puts the row in multi-select mode with a leading checkmark.
	var selection: Bool?

	var body: some View {
		HStack(spacing: 12) {
			if let selection {
				Image(systemName: selection ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(selection ? Color.accentColor : Color(.tertiaryLabel))
					.imageScale(.large)
					.frame(width: 22)
			}

			FileIconView(node: node)
				.opacity(node.isHidden ? 0.5 : 1)

			VStack(alignment: .leading, spacing: 2) {
				Text(node.name)
					.font(.body)
					.lineLimit(1)
					.truncationMode(.middle)
					.foregroundStyle(node.isHidden ? Color(.tertiaryLabel) : Color(.label))

				Text(subtitleOverride ?? defaultSubtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.opacity(node.isHidden ? 0.7 : 1)

			Spacer(minLength: 0)

			if node.isSymbolicLink {
				Image(systemName: "link")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
		.contentShape(Rectangle())
	}

	private var defaultSubtitle: String {
		var parts: [String] = []
		parts.append(node.isDirectory ? "Folder" : ByteCountFormat.string(for: node.size))
		if let date = node.modifiedAt {
			parts.append(date.formatted(date: .abbreviated, time: .shortened))
		}
		return parts.joined(separator: " \u{2022} ")
	}
}
