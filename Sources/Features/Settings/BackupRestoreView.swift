import PartyUI
import SwiftUI
import UniformTypeIdentifiers

/// Export/import every `SettingsStore` preference as a small JSON file, so a
/// device's Filzer setup can be carried over to another install.
struct BackupRestoreView: View {
	@EnvironmentObject private var settings: SettingsStore
	@State private var showingImport = false
	@State private var errorMessage: String?

	var body: some View {
		List {
			Section(footer: Text("Saves every setting on this screen and the previous one to a JSON file you can share or store elsewhere.")) {
				Button {
					exportSettings()
				} label: {
					ButtonLabel(text: "Export Settings", icon: "square.and.arrow.up")
				}
				.buttonStyle(TranslucentButtonStyle())
			}

			Section(footer: Text("Replaces every current setting with the contents of a previously exported JSON file.")) {
				Button {
					showingImport = true
				} label: {
					ButtonLabel(text: "Import Settings", icon: "square.and.arrow.down")
				}
				.buttonStyle(TranslucentButtonStyle())
			}
		}
		.navigationTitle("Backup & Restore")
		.fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
			importSettings(from: result)
		}
		.errorAlert($errorMessage)
	}

	private func exportSettings() {
		Task {
			do {
				let data = try settings.exportData()
				let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Filzer Settings.json")
				try await FileSystem.current.writeFile(at: destination, data: data)
				presentShareSheet(with: destination)
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}

	private func importSettings(from result: Result<URL, Error>) {
		do {
			let pickedURL = try result.get()
			let data = try SecurityScopedBookmark.withSecurityScopedAccess(to: pickedURL) {
				try Data(contentsOf: pickedURL)
			}
			try settings.importData(data)
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
