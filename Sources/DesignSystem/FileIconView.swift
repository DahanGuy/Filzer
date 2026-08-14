import ImageIO
import SwiftUI
import UIKit

/// A file/folder's row icon — an SF Symbol tinted by category, upgraded to a real
/// downsized thumbnail for images once one loads.
struct FileIconView: View {
	let node: FileNode

	@State private var thumbnail: UIImage?

	var body: some View {
		Group {
			if let thumbnail {
				Image(uiImage: thumbnail)
					.resizable()
					.aspectRatio(contentMode: .fill)
					.frame(width: Theme.rowIconSize, height: Theme.rowIconSize)
					.clipShape(RoundedRectangle(cornerRadius: Theme.rowIconCornerRadius))
			} else {
				Image(systemName: FileClassifier.systemImageName(for: node))
					.font(.system(size: 18))
					.foregroundStyle(Theme.color(for: FileClassifier.category(for: node)))
					.frame(width: Theme.rowIconSize, height: Theme.rowIconSize)
			}
		}
		.task(id: node.url) {
			thumbnail = await Self.loadThumbnail(for: node)
		}
	}

	private static func loadThumbnail(for node: FileNode) async -> UIImage? {
		guard FileClassifier.category(for: node) == .image else { return nil }
		let url = node.url
		return await Task.detached(priority: .utility) {
			guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
			let options: [CFString: Any] = [
				kCGImageSourceCreateThumbnailFromImageAlways: true,
				kCGImageSourceThumbnailMaxPixelSize: 128,
				kCGImageSourceCreateThumbnailWithTransform: true,
			]
			guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
			return UIImage(cgImage: cgImage)
		}.value
	}
}
