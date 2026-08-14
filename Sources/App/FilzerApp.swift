import SwiftUI

@main
struct FilzerApp: App {
	@StateObject private var settings = SettingsStore()
	@StateObject private var bookmarks = BookmarksStore()
	@StateObject private var recents = RecentsStore()
	@StateObject private var clipboard = ClipboardStore()
	@StateObject private var trash = TrashStore()
	@StateObject private var fileAssociations = FileAssociationsStore()

	var body: some Scene {
		WindowGroup {
			RootTabView()
				.environmentObject(settings)
				.environmentObject(bookmarks)
				.environmentObject(recents)
				.environmentObject(clipboard)
				.environmentObject(trash)
				.environmentObject(fileAssociations)
		}
	}
}
