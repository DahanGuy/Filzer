import SwiftUI

@main
struct FilzerApp: App {
	@StateObject private var settings = SettingsStore()
	@StateObject private var bookmarks = BookmarksStore()
	@StateObject private var recents = RecentsStore()
	@StateObject private var clipboard = ClipboardStore()
	@StateObject private var fileAssociations = FileAssociationsStore()
	@StateObject private var remoteConnections = RemoteConnectionsStore()

	var body: some Scene {
		WindowGroup {
			RootBrowserShell()
				.environmentObject(settings)
				.environmentObject(bookmarks)
				.environmentObject(recents)
				.environmentObject(clipboard)
				.environmentObject(fileAssociations)
				.environmentObject(remoteConnections)
		}
	}
}
