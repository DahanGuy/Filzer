import PartyUI
import SwiftUI

/// Persistent banner shown whenever `ClipboardStore` holds items — Filza's "N item(s)
/// in Pasteboard. Tap here to Paste."
struct PasteboardBanner: View {
	let count: Int
	let operation: ClipboardOperation
	let onPaste: () -> Void
	let onClear: () -> Void

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: operation == .copy ? "doc.on.doc" : "scissors")
				.foregroundStyle(Color.accentColor)

			Text("\(count) item\(count == 1 ? "" : "s") ready to \(operation == .copy ? "copy" : "move")")
				.font(.subheadline)
				.lineLimit(1)

			Spacer(minLength: 8)

			Button("Paste", action: onPaste)
				.buttonStyle(GetButtonStyle())

			Button(action: onClear) {
				Image(systemName: "xmark.circle.fill")
					.foregroundStyle(.secondary)
			}
		}
		.modifier(SectionPlatter())
		.padding(.horizontal)
		.padding(.bottom, 8)
	}
}
