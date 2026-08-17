import SwiftUI

enum Theme {
	static let rowIconSize: CGFloat = 30
	static let rowIconCornerRadius: CGFloat = 6
	static let sectionSpacing: CGFloat = 16

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
