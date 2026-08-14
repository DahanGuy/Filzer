import Foundation
import SwiftUI

/// Filza's Property List Editor: opens binary or XML plists (transparently, via
/// `PlistCodec`) as a navigable outline. The root itself is rendered as an ordinary
/// `PlistNodeRow` labeled with the file's name, so dictionary/array editing logic never
/// has to be duplicated between "the root" and "a nested node."
struct PlistEditorView: View {
	let url: URL

	@State private var root: PlistNode?
	@State private var format: PropertyListSerialization.PropertyListFormat = .xml
	@State private var isDirty = false
	@State private var isLoading = true
	@State private var isSaving = false
	@State private var errorMessage: String?

	var body: some View {
		Group {
			if isLoading {
				ProgressView()
			} else if root != nil {
				List {
					PlistNodeRow(node: rootBinding, title: url.deletingPathExtension().lastPathComponent, onRename: nil, onDelete: nil)
				}
				.listStyle(.plain)
			} else {
				EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn't Open Property List")
			}
		}
		.navigationTitle(url.lastPathComponent)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) {
				EditButton()
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				Button("Save") { Task { await save() } }
					.disabled(!isDirty || isSaving)
			}
		}
		.task { await load() }
		.errorAlert($errorMessage)
	}

	private var rootBinding: Binding<PlistNode> {
		Binding(
			get: { root ?? .dictionary([]) },
			set: { root = $0; isDirty = true }
		)
	}

	private func load() async {
		isLoading = true
		defer { isLoading = false }
		do {
			let data = try await FileSystem.current.readFile(at: url)
			let decoded = try PlistCodec.decode(data)
			root = decoded.root
			format = decoded.format
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func save() async {
		guard let root else { return }
		isSaving = true
		defer { isSaving = false }
		do {
			let data = try PlistCodec.encode(root, format: format)
			try await FileSystem.current.writeFile(at: url, data: data)
			isDirty = false
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
