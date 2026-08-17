import AVFoundation
import CoreGraphics
import CoreMedia
import ImageIO

struct MediaMetadata {
	var duration: TimeInterval?
	var videoDimensions: CGSize?
	var sampleRate: Double?
}

enum MediaMetadataReader {
	static func imageDimensions(at url: URL) -> CGSize? {
		guard
			let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
			let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
		else {
			return nil
		}
		return CGSize(width: width, height: height)
	}

	static func mediaMetadata(at url: URL) async -> MediaMetadata {
		let asset = AVURLAsset(url: url)
		let keys = ["duration", "tracks"]
		return await withCheckedContinuation { continuation in
			asset.loadValuesAsynchronously(forKeys: keys) {
				var result = MediaMetadata()
				var error: NSError?

				if asset.statusOfValue(forKey: "duration", error: &error) == .loaded {
					let seconds = CMTimeGetSeconds(asset.duration)
					if seconds.isFinite, seconds >= 0 { result.duration = seconds }
				}

				if asset.statusOfValue(forKey: "tracks", error: &error) == .loaded {
					if let videoTrack = asset.tracks(withMediaType: .video).first {
						let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
						result.videoDimensions = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
					}
					if let audioTrack = asset.tracks(withMediaType: .audio).first,
					   let formatDescription = audioTrack.formatDescriptions.first,
					   let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription as! CMAudioFormatDescription) {
						result.sampleRate = basicDescription.pointee.mSampleRate
					}
				}

				continuation.resume(returning: result)
			}
		}
	}
}
