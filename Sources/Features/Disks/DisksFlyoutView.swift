import PartyUI
import SwiftUI
import UniformTypeIdentifiers

/// The Disks flyout — storage-capacity readout, every top-level browsable root (the
/// app's own container, plus any externally-picked "Added Folders" or configured
/// WebDAV/FTP/SMB/cloud network locations). The "+" menu covers both ways of adding a
/// new root: a document-picker folder grant, or a network/cloud connection.
struct DisksFlyoutView: View {
	/// Called when a row is tapped, instead of pushing it inside this flyout's own
	/// navigation stack — the presenter dismisses this popover and opens the location
	/// in its own (main) screen.
	let onNavigate: (URL, String?) -> Void

	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var bookmarks: BookmarksStore
	@EnvironmentObject private var remoteConnections: RemoteConnectionsStore

	@State private var volumeInfo: VolumeInfo?
	@State private var showingAddFolder = false
	@State private var showingAddRemote = false
	@State private var errorMessage: String?

	/// Externally-picked folders — a `BookmarkEntry` carrying a security-scoped
	/// bookmark, added via the document picker (plain typed-path bookmarks live in the
	/// Bookmarks flyout instead; see `BookmarksFlyoutView.plainEntries`).
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
						Label("Add Network Location", systemImage: "cloud.fill")
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
				.overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))

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

	/// Red once storage is almost full, matching the "low space" warning color every
	/// other iOS storage gauge uses.
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

	/// "Add Folder" — Filza's term for pinning a folder the app has no innate access
	/// to. The document picker grants a one-time security-scoped grant; the bookmark
	/// data persisted here is what makes that grant durable across launches.
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
