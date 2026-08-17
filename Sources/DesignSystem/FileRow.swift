import SwiftUI

struct FileRow: View {
	let node: FileNode
	var subtitleOverride: String?
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
				.opacity(node.isHidden ? 0.65 : 1)

			VStack(alignment: .leading, spacing: 2) {
				Text(node.name)
					.font(.body)
					.lineLimit(1)
					.truncationMode(.middle)
					.foregroundStyle(node.isHidden ? Color(.secondaryLabel) : Color(.label))

				Text(subtitleOverride ?? defaultSubtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.opacity(node.isHidden ? 0.85 : 1)

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
