import SwiftUI

struct FileAssociationsSettingsView: View {
	@EnvironmentObject private var fileAssociations: FileAssociationsStore
	@State private var isPresentingAdd = false

	private var sortedExtensions: [String] {
		fileAssociations.associations.keys.sorted()
	}

	var body: some View {
		List {
			if sortedExtensions.isEmpty {
				EmptyStateView(
					icon: "doc.badge.gearshape",
					title: "No Overrides",
					message: "Add an extension to always open it with a specific viewer."
				)
			} else {
				ForEach(sortedExtensions, id: \.self) { fileExtension in
					HStack {
						Text(".\(fileExtension)")
						Spacer()
						Text(fileAssociations.associations[fileExtension]?.title ?? "")
							.foregroundColor(.secondary)
					}
				}
				.onDelete(perform: delete)
			}
		}
		.navigationTitle("File Associations")
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					isPresentingAdd = true
				} label: {
					Image(systemName: "plus")
				}
			}
		}
		.sheet(isPresented: $isPresentingAdd) {
			AddFileAssociationSheet(fileAssociations: fileAssociations)
		}
	}

	private func delete(at offsets: IndexSet) {
		for index in offsets {
			fileAssociations.setViewer(nil, forExtension: sortedExtensions[index])
		}
	}
}

private struct AddFileAssociationSheet: View {
	@ObservedObject var fileAssociations: FileAssociationsStore
	@Environment(\.presentationMode) private var presentationMode
	@State private var fileExtension = ""
	@State private var viewerKind: ViewerKind = .text

	var body: some View {
		NavigationView {
			Form {
				Section {
					TextField("Extension (e.g. txt)", text: $fileExtension)
						.autocapitalization(.none)
						.disableAutocorrection(true)
				}
				Section {
					Picker("Viewer", selection: $viewerKind) {
						ForEach(ViewerKind.allCases) { kind in
							Text(kind.title).tag(kind)
						}
					}
				}
			}
			.navigationTitle("Add Association")
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button("Cancel") { presentationMode.wrappedValue.dismiss() }
				}
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Save") {
						fileAssociations.setViewer(viewerKind, forExtension: fileExtension)
						presentationMode.wrappedValue.dismiss()
					}
					.disabled(fileExtension.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
		}
		.navigationViewStyle(.stack)
	}
}
