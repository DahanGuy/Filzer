import SwiftUI

/// Filza-style empty states ("This folder is empty", "No recents", "No bookmarks", …).
struct EmptyStateView: View {
	let icon: String
	let title: String
	var message: String?

	var body: some View {
		VStack(spacing: 10) {
			Image(systemName: icon)
				.font(.system(size: 40))
				.foregroundStyle(.tertiary)
			Text(title)
				.font(.headline)
				.foregroundStyle(.secondary)
			if let message {
				Text(message)
					.font(.subheadline)
					.foregroundStyle(.tertiary)
					.multilineTextAlignment(.center)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}
}
