import PartyUI
import SwiftUI

/// Filza's "Zip Viewer", generalized to every format `ArchiveFormat` recognizes
/// (zip/rar/tar/gzip/bzip2/xz/7z) — browses an archive's contents as a virtual folder
/// tree without extracting the whole thing to disk. This is just the root-level entry
/// point `FileViewerRoute` pushes to; the actual browsing happens in
/// `ArchiveBrowserLevelView`, which recurses into itself as the user drills into
/// nested folders. `password` is hoisted here (not local to each level) and passed
/// down as a binding so unlocking a password-protected RAR once, at any depth, covers
/// every level of the same archive instead of re-prompting per folder.
struct ArchiveBrowserView: View {
	let url: URL

	@State private var password: String?

	var body: some View {
		ArchiveBrowserLevelView(archiveURL: url, prefix: "", title: url.lastPathComponent, password: $password)
	}
}

/// One level of an archive's virtual folder tree: everything whose path sits directly
/// under `prefix`. Files are only ever pulled out of the archive (to a scratch temp
/// directory) when the user taps one; folders just recurse into another level of this
/// same view with a deeper `prefix`.
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

	// MARK: - Row rendering

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

	// MARK: - Programmatic navigation to an extracted file

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

	// MARK: - Loading and extraction

	/// Routes a failure to the password prompt (retrying the same operation once one's
	/// supplied) when the archive needs one, or to the plain error alert otherwise.
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

	/// Extracts a single entry into an isolated scratch directory (so same-named files
	/// from different zips never collide) and previews the result.
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

	/// Extracts the whole archive into a sibling folder named after it (minus its
	/// extension(s)), e.g. `archive.tar.gz` -> `archive/`.
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

/// A single row inside the zip's virtual tree — a folder or file that still lives
/// inside the archive, so it's rendered from an `ArchiveEntry` rather than `FileRow`
/// (which requires a real on-disk `FileNode`).
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
