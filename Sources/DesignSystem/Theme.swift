import SwiftUI

/// App-specific layout tokens shared by every screen. Corner radii deliberately reuse
/// PartyUI's own `cornerRad.component` / `cornerRad.platter` at call sites instead of
/// duplicating a second radius scale — this file only holds tokens PartyUI doesn't provide.
enum Theme {
	static let rowIconSize: CGFloat = 30
	static let rowIconCornerRadius: CGFloat = 6
	static let sectionSpacing: CGFloat = 16

	/// Tint color per `FileCategory`, used by `FileIconView` and anywhere else a
	/// category needs a consistent accent (e.g. the storage usage breakdown).
	static func color(for category: FileCategory) -> Color {
		switch category {
		case .folder: return .accentColor
		case .image, .video: return .purple
		case .audio: return .pink
		case .archive: return .orange
		case .propertyList: return .indigo
		case .sqlite: return .teal
		case .pdf: return .red
		case .webPage: return .blue
		case .symbolicLink: return .gray
		case .text, .other: return .secondary
		}
	}
}
