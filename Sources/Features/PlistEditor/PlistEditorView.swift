import Foundation
import SwiftUI

struct PlistEditorView: View {
	let url: URL

	@State private var root: PlistNode?
	@State private var format: PropertyListSerialization.PropertyListFormat = .xml
	@State private var isDirty = false
	@State private var isLoading = true
	@State private var isSaving = false
	@State private var errorMessage: String?
	@State private var isInvalidPlist = false
	@State private var showingOverwriteAlert = false

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
				VStack(spacing: 16) {
					EmptyStateView(
						icon: "exclamationmark.triangle",
						title: "Couldn't Open Property List",
						message: isInvalidPlist ? PlistCodec.CodecError.malformedPlist.errorDescription : nil
					)
					if isInvalidPlist {
						Button("Overwrite with Empty Plist\u{2026}", role: .destructive) { showingOverwriteAlert = true }
					}
				}
			}
		}
		.alert("Not a Valid Property List", isPresented: $showingOverwriteAlert) {
			Button("Overwrite with Empty Plist", role: .destructive) { Task { await overwriteWithEmptyPlist() } }
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("\(url.lastPathComponent) isn't a valid property list. Overwriting replaces everything in the file with a new, empty property list, and its current contents will be lost.")
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
			isInvalidPlist = false
		} catch PlistCodec.CodecError.malformedPlist {
			isInvalidPlist = true
			showingOverwriteAlert = true
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func overwriteWithEmptyPlist() async {
		do {
			let data = try PlistCodec.encode(.dictionary([]), format: .xml)
			try await FileSystem.current.writeFile(at: url, data: data)
			await load()
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
