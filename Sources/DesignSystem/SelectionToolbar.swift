import PartyUI
import SwiftUI

/// The bottom action bar shown while multi-select ("Edit") mode is active.
struct SelectionToolbar: View {
	let selectionCount: Int
	let onCopy: () -> Void
	let onMove: () -> Void
	let onCompress: () -> Void
	let onShare: () -> Void
	let onDelete: () -> Void

	var body: some View {
		HStack(spacing: 0) {
			actionButton("Copy", icon: "doc.on.doc", action: onCopy)
			actionButton("Move", icon: "folder", action: onMove)
			actionButton("Zip", icon: "doc.zipper", action: onCompress)
			actionButton("Share", icon: "square.and.arrow.up", action: onShare)
			actionButton("Delete", icon: "trash", isDestructive: true, action: onDelete)
		}
		.disabled(selectionCount == 0)
		.modifier(OverlayBackground())
	}

	@ViewBuilder
	private func actionButton(_ title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 4) {
				Image(systemName: icon).font(.system(size: 19))
				Text(title).font(.caption2)
			}
			.frame(maxWidth: .infinity)
		}
		.foregroundStyle(isDestructive ? Color.red : Color.accentColor)
	}
}
