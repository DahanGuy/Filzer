import PartyUI
import SwiftUI

/// Add-bookmark form — a plain typed path and an optional name, not a document picker
/// (Bookmarks pins any path Filzer can reach; "Added Folders" in Disks is the
/// document-picker flow for paths the app has no innate access to).
struct AddBookmarkView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var bookmarks: BookmarksStore

	@State private var path: String
	@State private var name = ""

	/// `initialPath` prefills to the folder that was open when Bookmarks was invoked.
	init(initialPath: String) {
		_path = State(initialValue: initialPath)
	}

	var body: some View {
		Form {
			Section(header: HeaderLabel(text: "Location", icon: "folder")) {
				TextField("/path/to/folder", text: $path)
					.autocapitalization(.none)
					.disableAutocorrection(true)
			}

			Section(header: HeaderLabel(text: "Name", icon: "tag"), footer: Text("Leave blank to use the path's folder name.")) {
				TextField(defaultName, text: $name)
			}
		}
		.navigationTitle("Add Bookmark")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
			ToolbarItem(placement: .navigationBarTrailing) { Button("Save", action: save).disabled(trimmedPath.isEmpty) }
		}
	}

	private var trimmedPath: String { path.trimmingCharacters(in: .whitespacesAndNewlines) }

	private var defaultName: String {
		trimmedPath.isEmpty ? "Name" : (URL(fileURLWithPath: trimmedPath).lastPathComponent)
	}

	private func save() {
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		bookmarks.add(url: URL(fileURLWithPath: trimmedPath), displayName: trimmedName.isEmpty ? nil : trimmedName)
		dismiss()
	}
}
