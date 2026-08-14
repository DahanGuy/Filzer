import SwiftUI

/// A compact "Used X of Y" capacity bar for Filzer's own sandbox volume, shown at the
/// bottom of Home. Uses `volumeInfo(for:)` rather than any per-file size math since the
/// figure being shown is disk capacity, not folder contents.
struct StorageUsageView: View {
	@State private var volumeInfo: VolumeInfo?
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			if let volumeInfo {
				GeometryReader { proxy in
					ZStack(alignment: .leading) {
						Rectangle()
							.fill(Color(.systemFill))
						Rectangle()
							.fill(Color.accentColor)
							.frame(width: usedWidth(in: proxy.size.width, volumeInfo: volumeInfo))
					}
				}
				.frame(height: 8)
				.clipShape(RoundedRectangle(cornerRadius: 4))

				Text("Used \(ByteCountFormat.string(for: volumeInfo.usedCapacity)) of \(ByteCountFormat.string(for: volumeInfo.totalCapacity))")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				Text("Loading storage…")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
		.task { await loadVolumeInfo() }
		.errorAlert($errorMessage)
	}

	private func usedWidth(in totalWidth: CGFloat, volumeInfo: VolumeInfo) -> CGFloat {
		guard volumeInfo.totalCapacity > 0 else { return 0 }
		let fraction = CGFloat(volumeInfo.usedCapacity) / CGFloat(volumeInfo.totalCapacity)
		return totalWidth * min(max(fraction, 0), 1)
	}

	private func loadVolumeInfo() async {
		do {
			volumeInfo = try await FileSystem.current.volumeInfo(for: SandboxRoots.documents)
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
