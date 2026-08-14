import PartyUI
import SwiftUI

/// The Disks flyout — Filzer's storage-capacity readout plus every top-level browsable
/// root: the app's own sandbox container, and any configured WebDAV/FTP/SMB network
/// locations. A sandboxed app has no other disks to show.
struct DisksFlyoutView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var remoteConnections: RemoteConnectionsStore

	@State private var volumeInfo: VolumeInfo?
	@State private var showingAddRemote = false
	@State private var errorMessage: String?

	var body: some View {
		List {
			Section(header: HeaderLabel(text: "Storage", icon: "internaldrive")) {
				storageUsageRow
			}

			Section(header: HeaderLabel(text: "Local", icon: "iphone")) {
				NavigationLink(destination: FileBrowserView(rootURL: URL(fileURLWithPath: NSHomeDirectory()), displayName: "Filzer")) {
					NavigationLabel(text: "Filzer", icon: "internaldrive.fill")
				}
			}

			Section(header: HeaderLabel(text: "Network Locations", icon: "network")) {
				if remoteConnections.connections.isEmpty {
					Text("No network locations added")
						.foregroundStyle(.secondary)
				} else {
					ForEach(remoteConnections.connections) { connection in
						NavigationLink(destination: FileBrowserView(rootURL: connection.rootURL, displayName: connection.displayName)) {
							NavigationLabel(text: connection.displayName, icon: connection.kind.systemImageName)
						}
					}
					.onDelete { offsets in
						for index in offsets { remoteConnections.remove(remoteConnections.connections[index]) }
					}
				}
			}
		}
		.navigationTitle("Disks")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
			ToolbarItem(placement: .navigationBarTrailing) {
				Button { showingAddRemote = true } label: { Image(systemName: "plus") }
			}
		}
		.sheet(isPresented: $showingAddRemote) {
			NavigationView { AddRemoteLocationView() }
				.navigationViewStyle(.stack)
		}
		.task { await loadVolumeInfo() }
		.errorAlert($errorMessage)
	}

	@ViewBuilder
	private var storageUsageRow: some View {
		if let volumeInfo {
			VStack(alignment: .leading, spacing: 8) {
				GeometryReader { geometry in
					ZStack(alignment: .leading) {
						Capsule().fill(Color(.systemGray5))
						Capsule()
							.fill(Color.accentColor)
							.frame(width: geometry.size.width * usedFraction(volumeInfo))
					}
				}
				.frame(height: 10)

				Text("Used \(ByteCountFormat.string(for: volumeInfo.usedCapacity)) of \(ByteCountFormat.string(for: volumeInfo.totalCapacity))")
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			.padding(.vertical, 4)
		} else {
			ProgressView()
		}
	}

	private func usedFraction(_ info: VolumeInfo) -> CGFloat {
		guard info.totalCapacity > 0 else { return 0 }
		return CGFloat(Double(info.usedCapacity) / Double(info.totalCapacity))
	}

	private func loadVolumeInfo() async {
		do {
			volumeInfo = try await FileSystem.current.volumeInfo(for: URL(fileURLWithPath: NSHomeDirectory()))
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
