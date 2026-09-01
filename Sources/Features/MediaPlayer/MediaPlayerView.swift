import AVKit
import PartyUI
import SwiftUI

struct MediaPlayerView: View {
	let url: URL

	@State private var player: AVPlayer
	@State private var metadata: MediaMetadata?

	init(url: URL) {
		self.url = url
		_player = State(initialValue: AVPlayer(url: url))
	}

	var body: some View {
		VStack(spacing: 0) {
			VideoPlayer(player: player)
			if let metadata {
				metadataStrip(metadata)
			}
		}
		.navigationTitle(url.lastPathComponent)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					presentShareSheet(with: url)
				} label: {
					Image(systemName: "square.and.arrow.up")
				}
			}
		}
		.task {
			metadata = await MediaMetadataReader.mediaMetadata(at: url)
		}
		.onDisappear { player.pause() }
	}

	@ViewBuilder
	private func metadataStrip(_ metadata: MediaMetadata) -> some View {
		if metadata.duration != nil || metadata.videoDimensions != nil || metadata.sampleRate != nil {
			HStack(spacing: 8) {
				if let duration = metadata.duration {
					InfoBadge(text: durationText(duration), icon: "clock")
				}
				if let dimensions = metadata.videoDimensions {
					InfoBadge(text: "\(Int(dimensions.width)) × \(Int(dimensions.height))", icon: "aspectratio")
				}
				if let sampleRate = metadata.sampleRate {
					InfoBadge(text: "\(Int(sampleRate)) Hz", icon: "waveform")
				}
				Spacer()
			}
			.padding(.horizontal)
			.padding(.vertical, 8)
		}
	}

	private func durationText(_ duration: TimeInterval) -> String {
		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .positional
		formatter.zeroFormattingBehavior = .pad
		formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
		return formatter.string(from: duration) ?? "-"
	}
}
