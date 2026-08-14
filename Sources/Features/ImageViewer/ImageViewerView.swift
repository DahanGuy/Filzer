import PartyUI
import SwiftUI
import UIKit

/// Full-screen image viewer with pinch-to-zoom/pan and a bottom info strip. Reads
/// bytes through `FileSystem.current` (never `UIImage(contentsOfFile:)`) so it works
/// uniformly whether `url` lives in the sandbox or behind a security-scoped bookmark.
struct ImageViewerView: View {
	let url: URL

	@State private var image: UIImage?
	@State private var isLoading = true
	@State private var dimensions: CGSize?
	@State private var fileSize: Int64?
	@State private var errorMessage: String?

	@State private var scale: CGFloat = 1
	@GestureState private var pinchScale: CGFloat = 1
	@State private var offset: CGSize = .zero
	@GestureState private var dragOffset: CGSize = .zero

	private let minScale: CGFloat = 1
	private let maxScale: CGFloat = 5

	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()
			content
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
		.task { await load() }
		.errorAlert($errorMessage)
	}

	@ViewBuilder
	private var content: some View {
		if let image {
			VStack(spacing: 0) {
				imageCanvas(image)
				if dimensions != nil || fileSize != nil {
					infoStrip
				}
			}
		} else if isLoading {
			ProgressView()
				.tint(.white)
		} else {
			EmptyStateView(
				icon: "exclamationmark.triangle",
				title: "Can't Display Image",
				message: "This file couldn't be decoded as an image."
			)
		}
	}

	private func imageCanvas(_ image: UIImage) -> some View {
		GeometryReader { geometry in
			Image(uiImage: image)
				.resizable()
				.scaledToFit()
				.frame(width: geometry.size.width, height: geometry.size.height)
				.scaleEffect(currentScale)
				.offset(currentOffset)
				.gesture(zoomAndPanGesture)
				.onTapGesture(count: 2) { resetZoom() }
		}
	}

	// MARK: - Gestures

	/// Magnification and drag are recognized together so a user can pinch-zoom and
	/// pan in one continuous motion, matching Photos.app's viewer behavior.
	private var zoomAndPanGesture: some Gesture {
		MagnificationGesture()
			.updating($pinchScale) { value, state, _ in state = value }
			.onEnded { value in
				scale = min(max(scale * value, minScale), maxScale)
			}
			.simultaneously(with:
				DragGesture()
					.updating($dragOffset) { value, state, _ in state = value.translation }
					.onEnded { value in
						offset.width += value.translation.width
						offset.height += value.translation.height
					}
			)
	}

	private var currentScale: CGFloat {
		min(max(scale * pinchScale, minScale), maxScale)
	}

	private var currentOffset: CGSize {
		CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height)
	}

	private func resetZoom() {
		withAnimation {
			scale = minScale
			offset = .zero
		}
	}

	// MARK: - Info strip

	private var infoStrip: some View {
		HStack {
			if let dimensions {
				Text("\(Int(dimensions.width)) × \(Int(dimensions.height))")
			}
			Spacer()
			if let fileSize {
				Text(ByteCountFormat.string(for: fileSize))
			}
		}
		.font(.footnote)
		.foregroundStyle(.white.opacity(0.85))
		.padding(.horizontal)
		.padding(.vertical, 8)
		.background(Color.black.opacity(0.6))
	}

	// MARK: - Loading

	private func load() async {
		dimensions = MediaMetadataReader.imageDimensions(at: url)
		do {
			let data = try await FileSystem.current.readFile(at: url)
			guard let decoded = UIImage(data: data) else {
				isLoading = false
				return
			}
			image = decoded
			if let node = try? await FileSystem.current.nodeInfo(at: url) {
				fileSize = node.size
			}
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}
}
