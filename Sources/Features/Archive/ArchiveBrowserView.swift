import PartyUI
import SwiftUI

struct ArchiveBrowserView: View {
	let url: URL

	@State private var password: String?

	var body: some View {
		ArchiveBrowserLevelView(archiveURL: url, prefix: "", title: url.lastPathComponent, password: $password)
	}
}

struct ArchiveBrowserLevelView: View {
	let archiveURL: URL
	let prefix: String
	let title: String
	@Binding var password: String?

	@State private var entries: [ArchiveEntry] = []
	@State private var isLoading = true
	@State private var errorMessage: String?
	@State private var extractingEntryID: String?
	@State private var pendingNode: FileNode?
	@State private var isExtractingAll = false

	@State private var showingPasswordPrompt = false
	@State private var passwordInput = ""
	@State private var pendingRetry: (() -> Void)?

	var body: some View {
		Group {
			if isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				let rows = ArchiveTree.rows(in: entries, under: prefix)
				if rows.isEmpty {
					EmptyStateView(icon: "doc.zipper", title: "Empty Folder")
				} else {
					List(rows) { row in
						rowContent(for: row)
					}
					.listStyle(.plain)
				}
			}
		}
		.navigationTitle(title)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				if isExtractingAll {
					ProgressView()
				} else {
					Button("Extract All") { extractAll() }
				}
			}
		}
		.task { await loadEntries() }
		.errorAlert($errorMessage)
		.alert("Password Required", isPresented: $showingPasswordPrompt) {
			SecureField("Password", text: $passwordInput)
			Button("Cancel", role: .cancel) { pendingRetry = nil }
			Button("Unlock") {
				password = passwordInput
				let retry = pendingRetry
				pendingRetry = nil
				retry?()
			}
		} message: {
			Text("\"\(archiveURL.lastPathComponent)\" is password-protected.")
		}
		.background(
			NavigationLink(destination: pendingNodeDestination, isActive: pendingNodeActiveBinding) { EmptyView() }
		)
	}

	@ViewBuilder
	private func rowContent(for row: ArchiveRow) -> some View {
		if row.entry.isDirectory {
			NavigationLink(
				destination: ArchiveBrowserLevelView(archiveURL: archiveURL, prefix: row.entry.path, title: row.entry.name, password: $password)
			) {
				ArchiveRowView(entry: row.entry)
			}
		} else {
			Button {
				extract(row.entry)
			} label: {
				HStack {
					ArchiveRowView(entry: row.entry)
					if extractingEntryID == row.id {
						ProgressView()
					}
				}
			}
			.disabled(extractingEntryID != nil)
			.buttonStyle(.plain)
		}
	}

	@ViewBuilder
	private var pendingNodeDestination: some View {
		if let pendingNode {
			FileViewerRoute(node: pendingNode)
		} else {
			EmptyView()
		}
	}

	private var pendingNodeActiveBinding: Binding<Bool> {
		Binding(get: { pendingNode != nil }, set: { if !$0 { pendingNode = nil } })
	}

	private func handleArchiveError(_ error: Error, retry: @escaping () -> Void) {
		if case FileSystemError.archivePasswordRequired = error {
			passwordInput = password ?? ""
			pendingRetry = retry
			showingPasswordPrompt = true
		} else {
			errorMessage = error.localizedDescription
		}
	}

	private func loadEntries() async {
		isLoading = true
		do {
			entries = try await FileSystem.current.listArchiveEntries(archiveURL, password: password)
		} catch {
			handleArchiveError(error) { Task { await loadEntries() } }
		}
		isLoading = false
	}

	private func extract(_ entry: ArchiveEntry) {
		extractingEntryID = entry.id
		Task {
			defer { extractingEntryID = nil }
			do {
				let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
				let destination = scratchDirectory.appendingPathComponent(entry.name)
				try await FileSystem.current.createDirectory(at: scratchDirectory)
				try await FileSystem.current.extractArchiveEntry(entry.path, from: archiveURL, to: destination, password: password)
				pendingNode = try FileNode.make(at: destination)
			} catch {
				handleArchiveError(error) { extract(entry) }
			}
		}
	}

	private func extractAll() {
		isExtractingAll = true
		Task {
			defer { isExtractingAll = false }
			do {
				let folderName = ArchiveFormat.baseName(for: archiveURL)
				let destination = archiveURL.deletingLastPathComponent().appendingPathComponent(folderName)
				try await FileSystem.current.extractArchive(archiveURL, toDirectory: destination, password: password)
				Alertinator.shared.alert(title: "Extraction Complete", body: "Extracted to \"\(destination.lastPathComponent)\".")
			} catch {
				handleArchiveError(error) { extractAll() }
			}
		}
	}
}

private struct ArchiveRowView: View {
	let entry: ArchiveEntry

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
				.font(.system(size: 18))
				.foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
				.frame(width: Theme.rowIconSize, height: Theme.rowIconSize)

			VStack(alignment: .leading, spacing: 2) {
				Text(entry.name)
					.font(.body)
					.lineLimit(1)
					.truncationMode(.middle)
					.foregroundStyle(Color(.label))

				Text(entry.isDirectory ? "Folder" : ByteCountFormat.string(for: entry.uncompressedSize))
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Spacer(minLength: 0)
		}
		.contentShape(Rectangle())
	}
}
