import PartyUI
import SwiftUI

struct FileInfoView: View {
	let node: FileNode

	@Environment(\.dismiss) private var dismiss
	@State private var calculatedSize: Int64?
	@State private var isCalculatingSize = false
	@State private var imageDimensions: CGSize?
	@State private var mediaMetadata: MediaMetadata?
	@State private var errorMessage: String?
	@State private var showingPermissionsEditor = false

	var body: some View {
		List {
			Section(header: HeaderLabel(text: "Information", icon: "info.circle")) {
				infoRow("Name", node.name)
				infoRow("Path", node.url.path)
				infoRow("Type", typeDescription)
				sizeRow
				infoRow("Parent", node.url.deletingLastPathComponent().path)
				if let modifiedAt = node.modifiedAt {
					infoRow("Modified", modifiedAt.formatted(date: .abbreviated, time: .shortened))
				}
				if let createdAt = node.createdAt {
					infoRow("Created", createdAt.formatted(date: .abbreviated, time: .shortened))
				}
				if let destination = node.symbolicLinkDestination {
					infoRow("Destination", destination.path)
				}
			}

			if let imageDimensions {
				Section(header: HeaderLabel(text: "Image", icon: "photo")) {
					infoRow("Dimensions", "\(Int(imageDimensions.width)) \u{00d7} \(Int(imageDimensions.height))")
				}
			}

			if let mediaMetadata {
				Section(header: HeaderLabel(text: "Media", icon: "waveform")) {
					if let duration = mediaMetadata.duration {
						infoRow("Length", formattedDuration(duration))
					}
					if let videoDimensions = mediaMetadata.videoDimensions {
						infoRow("Resolution", "\(Int(videoDimensions.width)) \u{00d7} \(Int(videoDimensions.height))")
					}
					if let sampleRate = mediaMetadata.sampleRate {
						infoRow("Sample Rate", "\(Int(sampleRate)) Hz")
					}
				}
			}

			Section(header: HeaderLabel(text: "Ownership", icon: "person.2")) {
				infoRow("Owner", node.ownerAccountName ?? "\u{2014}")
				infoRow("Group", node.groupOwnerAccountName ?? "\u{2014}")
			}

			Section(header: HeaderLabel(text: "Access Permissions", icon: "lock")) {
				infoRow("Permissions", POSIXPermissions(mode: node.posixPermissions).symbolicString)
				infoRow("Octal", POSIXPermissions(mode: node.posixPermissions).octalString)
				Button("Edit Permissions\u{2026}") { showingPermissionsEditor = true }
			}
		}
		.navigationTitle("Info")
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button("Done") { dismiss() }
			}
		}
		.sheet(isPresented: $showingPermissionsEditor) {
			NavigationView { PermissionsEditorView(node: node) }
				.navigationViewStyle(.stack)
		}
		.task {
			switch FileClassifier.category(for: node) {
			case .image, .video, .audio:
				guard let (localURL, isTemporary) = try? await FileSystem.current.materializeLocally(node.url) else { return }
				defer { if isTemporary { try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent()) } }
				if FileClassifier.category(for: node) == .image {
					imageDimensions = MediaMetadataReader.imageDimensions(at: localURL)
				} else {
					mediaMetadata = await MediaMetadataReader.mediaMetadata(at: localURL)
				}
			default:
				break
			}
		}
		.errorAlert($errorMessage)
	}

	@ViewBuilder
	private var sizeRow: some View {
		if node.isDirectory {
			if let calculatedSize {
				infoRow("Size", ByteCountFormat.string(for: calculatedSize))
			} else {
				Button {
					Task { await calculateSize() }
				} label: {
					HStack {
						Text("Size").foregroundStyle(.secondary)
						Spacer()
						if isCalculatingSize {
							ProgressView()
						} else {
							Text("Calculate Size")
						}
					}
				}
			}
		} else {
			infoRow("Size", ByteCountFormat.string(for: node.size))
		}
	}

	private var typeDescription: String {
		if node.isDirectory { return "Folder" }
		if node.isSymbolicLink { return "Symbolic Link" }
		return node.pathExtension.isEmpty ? "File" : "\(node.pathExtension.uppercased()) File"
	}

	private func infoRow(_ label: String, _ value: String) -> some View {
		HStack {
			Text(label).foregroundStyle(.secondary)
			Spacer()
			Text(value).multilineTextAlignment(.trailing)
		}
	}

	private func calculateSize() async {
		isCalculatingSize = true
		defer { isCalculatingSize = false }
		do {
			calculatedSize = try await FileSystem.current.calculateSize(of: node.url)
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func formattedDuration(_ seconds: TimeInterval) -> String {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.hour, .minute, .second]
		formatter.unitsStyle = .positional
		formatter.zeroFormattingBehavior = .pad
		return formatter.string(from: seconds) ?? "\u{2014}"
	}
}
