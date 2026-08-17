import Foundation

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
	case ipa
	case mobileProvision

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
		case .archive: return "Archive Viewer"
		case .quickLook: return "Quick Look"
		case .ipa: return "App Inspector"
		case .mobileProvision: return "Provisioning Profile"
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
		case .ipa: return "app.badge"
		case .mobileProvision: return "checkmark.seal"
		}
	}

	var requiresLocalFile: Bool {
		switch self {
		case .media, .web, .sqlite, .quickLook, .archive, .ipa: return true
		case .text, .hex, .image, .propertyList, .mobileProvision: return false
		}
	}

	static func defaultViewer(for node: FileNode) -> ViewerKind {
		let extensionLowercased = node.pathExtension.lowercased()
		if extensionLowercased == "ipa" { return .ipa }
		if extensionLowercased == "mobileprovision" { return .mobileProvision }
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
