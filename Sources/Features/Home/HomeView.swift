import PartyUI
import SwiftUI
import UniformTypeIdentifiers

/// The Home tab: Filzer's own sandbox roots, any externally-picked "Add Location"
/// folders, a storage summary, and the entry point into Trash — the sandboxed
/// equivalent of Filza's Home screen root listing.
struct HomeView: View {
	@EnvironmentObject private var bookmarks: BookmarksStore
	@EnvironmentObject private var settings: SettingsStore
	@EnvironmentObject private var trash: TrashStore

	@State private var showingAddLocation = false
	@State private var errorMessage: String?

	var body: some View {
		NavigationView {
			List {
				Section(header: HeaderLabel(text: "Locations", icon: "location.fill")) {
					NavigationLink(destination: FileBrowserView(rootURL: SandboxRoots.documents, displayName: "Filzer")) {
						NavigationLabel(text: "Filzer", icon: "internaldrive.fill")
					}
					NavigationLink(destination: FileBrowserView(rootURL: SandboxRoots.library, displayName: "Library")) {
						NavigationLabel(text: "Library", icon: "folder.fill")
					}
					NavigationLink(destination: FileBrowserView(rootURL: SandboxRoots.temporary, displayName: "Temporary")) {
						NavigationLabel(text: "Temporary", icon: "clock.fill")
					}
				}

				if !externalLocations.isEmpty {
					Section(header: HeaderLabel(text: "External Locations", icon: "externaldrive.fill")) {
						ForEach(externalLocations) { entry in
							NavigationLink(destination: FileBrowserView(rootURL: bookmarks.resolvedURL(for: entry), displayName: entry.displayName)) {
								NavigationLabel(text: entry.displayName, icon: "externaldrive.fill")
							}
						}
					}
				}

				Section(header: HeaderLabel(text: "Storage", icon: "chart.pie.fill")) {
					StorageUsageView()
				}

				Section {
					NavigationLink(destination: TrashView()) {
						trashRow
					}
				}
			}
			.listStyle(.insetGrouped)
			.navigationTitle("Filzer")
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						showingAddLocation = true
					} label: {
						Image(systemName: "plus")
					}
				}
			}
			.fileImporter(isPresented: $showingAddLocation, allowedContentTypes: [.folder]) { result in
				addLocation(from: result)
			}
			.task { await trash.refresh() }
			.errorAlert($errorMessage)
		}
		.navigationViewStyle(.stack)
	}

	private var trashRow: some View {
		HStack {
			Image(systemName: "trash")
				.foregroundStyle(Color.accentColor)
				.frame(width: 24)
			Text("Trash")
			Spacer()
			if trash.items.count > 0 {
				Text("\(trash.items.count)")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.padding(.horizontal, 8)
					.padding(.vertical, 2)
					.background(Color(.systemFill), in: Capsule())
			}
		}
	}

	private var externalLocations: [BookmarkEntry] {
		bookmarks.entries.filter { $0.securityScopedBookmarkData != nil }
	}

	/// Turns a folder picked via `.fileImporter` into a durable bookmark, making a
	/// security-scoped bookmark while the picker's own temporary access grant is still
	/// alive (see the app-wide contract for why this must happen before the grant ends).
	private func addLocation(from result: Result<URL, Error>) {
		do {
			let url = try result.get()
			let bookmarkData = try SecurityScopedBookmark.withSecurityScopedAccess(to: url) {
				try SecurityScopedBookmark.makeBookmark(for: url)
			}
			bookmarks.add(url: url, displayName: url.lastPathComponent, securityScopedBookmarkData: bookmarkData)
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
