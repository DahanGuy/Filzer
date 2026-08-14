import Foundation

/// Every internal viewer/editor Filzer can open a file in. `FileBrowserView` routes to
/// one of these on tap; the context menu's "Open As" lets the user override the choice
/// for a single instance, and `FileAssociationsStore` lets them override it permanently
/// per extension.
enum ViewerKind: String, CaseIterable, Identifiable, Codable {
	case text
	case hex
	case image
	case media
	case web
	case propertyList
	case sqlite
	case archive
	case quickLook

	var id: String { rawValue }

	var title: String {
		switch self {
		case .text: return "Text Editor"
		case .hex: return "Hex Editor"
		case .image: return "Image Viewer"
		case .media: return "Media Player"
		case .web: return "Web Viewer"
		case .propertyList: return "Property List Editor"
		case .sqlite: return "SQLite Editor"
		case .archive: return "Zip Viewer"
		case .quickLook: return "Quick Look"
		}
	}

	var systemImageName: String {
		switch self {
		case .text: return "doc.text"
		case .hex: return "number"
		case .image: return "photo"
		case .media: return "play.circle"
		case .web: return "globe"
		case .propertyList: return "list.bullet.rectangle"
		case .sqlite: return "cylinder.split.1x2"
		case .archive: return "doc.zipper"
		case .quickLook: return "eye"
		}
	}

	/// The viewer Filzer picks for a file before consulting `FileAssociationsStore`.
	static func defaultViewer(for node: FileNode) -> ViewerKind {
		switch FileClassifier.category(for: node) {
		case .folder, .symbolicLink: return .quickLook
		case .image: return .image
		case .video, .audio: return .media
		case .text: return .text
		case .propertyList: return .propertyList
		case .archive: return .archive
		case .sqlite: return .sqlite
		case .webPage: return .web
		case .pdf, .other: return .quickLook
		}
	}
}
