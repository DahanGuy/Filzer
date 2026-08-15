import PartyUI
import SwiftUI

/// Add/edit-bookmark form — a plain typed path and an optional name, not a document
/// picker (Bookmarks pins any path Filzer can reach; "Added Folders" in Disks is the
/// document-picker flow for paths the app has no innate access to).
struct AddBookmarkView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var bookmarks: BookmarksStore

	/// Non-nil when editing an existing plain bookmark in place instead of adding a
	/// new one.
	private let editingEntry: BookmarkEntry?

	@State private var path: String
	@State private var name: String

	/// `initialPath` prefills to the folder that was open when Bookmarks was invoked.
	init(initialPath: String) {
		editingEntry = nil
		_path = State(initialValue: initialPath)
		_name = State(initialValue: "")
	}

	/// Edits `entry` in place - both fields prefill from its current values.
	init(editing entry: BookmarkEntry) {
		editingEntry = entry
		_path = State(initialValue: entry.url.path)
		_name = State(initialValue: entry.displayName)
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
		.navigationTitle(editingEntry == nil ? "Add Bookmark" : "Edit Bookmark")
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
		let resolvedName = trimmedName.isEmpty ? URL(fileURLWithPath: trimmedPath).lastPathComponent : trimmedName
		if let editingEntry {
			bookmarks.update(editingEntry, url: URL(fileURLWithPath: trimmedPath), displayName: resolvedName)
		} else {
			bookmarks.add(url: URL(fileURLWithPath: trimmedPath), displayName: resolvedName)
		}
		dismiss()
	}
}
