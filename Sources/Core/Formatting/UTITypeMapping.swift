import Foundation
import UniformTypeIdentifiers

enum FileCategory {
	case folder
	case symbolicLink
	case image
	case video
	case audio
	case text
	case propertyList
	case archive
	case sqlite
	case pdf
	case webPage
	case other
}

enum FileClassifier {
	static func category(for node: FileNode) -> FileCategory {
		if node.isSymbolicLink { return .symbolicLink }
		if node.isDirectory { return .folder }
		if ArchiveFormat.isArchive(node.url) { return .archive }

		let ext = node.pathExtension.lowercased()
		switch ext {
		case "plist": return .propertyList
		case "sqlite", "sqlite3", "db", "db3": return .sqlite
		case "pdf": return .pdf
		case "html", "htm": return .webPage
		default: break
		}

		guard let type = UTType(filenameExtension: ext) else { return .other }
		if type.conforms(to: .image) { return .image }
		if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return .video }
		if type.conforms(to: .audio) { return .audio }
		if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) { return .text }
		return .other
	}

	static func systemImageName(for node: FileNode) -> String {
		switch category(for: node) {
		case .folder: return "folder.fill"
		case .symbolicLink: return "link"
		case .image: return "photo.fill"
		case .video: return "film.fill"
		case .audio: return "music.note"
		case .text: return "doc.text.fill"
		case .propertyList: return "list.bullet.rectangle.fill"
		case .archive: return "doc.zipper"
		case .sqlite: return "cylinder.split.1x2.fill"
		case .pdf: return "doc.richtext.fill"
		case .webPage: return "globe"
		case .other: return "doc.fill"
		}
	}

	static func associationKey(for node: FileNode) -> String {
		node.pathExtension.lowercased()
	}
}
