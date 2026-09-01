import PartyUI
import SwiftUI
import UniformTypeIdentifiers

struct DisksFlyoutView: View {
	let onNavigate: (URL, String?) -> Void

	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var bookmarks: BookmarksStore
	@EnvironmentObject private var remoteConnections: RemoteConnectionsStore

	@State private var volumeInfo: VolumeInfo?
	@State private var showingAddFolder = false
	@State private var showingAddRemote = false
	@State private var errorMessage: String?

	private var addedFolders: [BookmarkEntry] {
		bookmarks.entries.filter { $0.securityScopedBookmarkData != nil }
	}

	var body: some View {
		List {
			Section(header: HeaderLabel(text: "Storage", icon: "internaldrive")) {
				storageUsageRow
			}

			Section(header: HeaderLabel(text: "Added Folders", icon: "folder.badge.plus")) {
				if addedFolders.isEmpty {
					Text("No folders added")
						.foregroundStyle(.secondary)
				} else {
					ForEach(addedFolders) { entry in
						Button {
							onNavigate(bookmarks.resolvedURL(for: entry), entry.displayName)
							dismiss()
						} label: {
							NavigationLabel(text: entry.displayName, icon: "folder.fill")
						}
						.buttonStyle(.plain)
					}
					.onDelete { offsets in
						for index in offsets { bookmarks.remove(addedFolders[index]) }
					}
				}
			}

			Section(header: HeaderLabel(text: "Network Locations", icon: "network")) {
				if remoteConnections.connections.isEmpty {
					Text("No network locations added")
						.foregroundStyle(.secondary)
				} else {
					ForEach(remoteConnections.connections) { connection in
						Button {
							onNavigate(connection.rootURL, connection.displayName)
							dismiss()
						} label: {
							NavigationLabel(text: connection.displayName, icon: connection.kind.systemImageName)
						}
						.buttonStyle(.plain)
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
				Menu {
					Button {
						showingAddFolder = true
					} label: {
						Label("Add Folder", systemImage: "folder.badge.plus")
					}
					Button {
						showingAddRemote = true
					} label: {
						Label("Add Network Location", systemImage: "cloud")
					}
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.fileImporter(isPresented: $showingAddFolder, allowedContentTypes: [.folder]) { result in
			Task { await addFolder(result: result) }
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
						Capsule()
							.fill(Color(.systemGray5))
						Capsule()
							.fill(barColor(for: volumeInfo))
							.frame(width: max(4, geometry.size.width * usedFraction(volumeInfo)))
					}
				}
				.frame(height: 10)
				.overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1.5))

				HStack {
					Text("Used \(ByteCountFormat.string(for: volumeInfo.usedCapacity)) of \(ByteCountFormat.string(for: volumeInfo.totalCapacity))")
					Spacer()
					Text("\(Int((usedFraction(volumeInfo) * 100).rounded()))%")
				}
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

	private func barColor(for info: VolumeInfo) -> Color {
		usedFraction(info) >= 0.9 ? .red : .accentColor
	}

	private func loadVolumeInfo() async {
		do {
			volumeInfo = try await FileSystem.current.volumeInfo(for: URL(fileURLWithPath: NSHomeDirectory()))
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func addFolder(result: Result<URL, Error>) async {
		do {
			let url = try result.get()
			let didStartAccessing = url.startAccessingSecurityScopedResource()
			defer {
				if didStartAccessing { url.stopAccessingSecurityScopedResource() }
			}
			let bookmarkData = try SecurityScopedBookmark.makeBookmark(for: url)
			bookmarks.add(url: url, securityScopedBookmarkData: bookmarkData)
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
