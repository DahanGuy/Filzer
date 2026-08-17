import SwiftUI

struct FileRowContextMenuContent: View {
	let node: FileNode
	let isBookmarked: Bool
	let onInfo: () -> Void
	let onOpenAs: (ViewerKind) -> Void
	let onRename: () -> Void
	let onDuplicate: () -> Void
	let onCopy: () -> Void
	let onMove: () -> Void
	let onCompress: (ArchiveFormat) -> Void
	let onExtractHere: () -> Void
	let onShare: () -> Void
	let onCopyPath: () -> Void
	let onToggleBookmark: () -> Void
	let onCreateSymlink: () -> Void
	let onCreateHardlink: () -> Void
	let onDelete: () -> Void

	var body: some View {
		Group {
			Button(action: onInfo) {
				Label("Info", systemImage: "info.circle")
			}

			if !node.isDirectory {
				Menu {
					ForEach(ViewerKind.allCases) { kind in
						Button(kind.title) { onOpenAs(kind) }
					}
				} label: {
					Label("Open As", systemImage: "doc.badge.gearshape")
				}
			}

			Button(action: onRename) {
				Label("Rename", systemImage: "pencil")
			}
			Button(action: onDuplicate) {
				Label("Duplicate", systemImage: "plus.square.on.square")
			}
			Button(action: onCopy) {
				Label("Copy", systemImage: "doc.on.doc")
			}
			Button(action: onMove) {
				Label("Cut", systemImage: "scissors")
			}

			if ArchiveFormat.isArchive(node.url) {
				Button(action: onExtractHere) {
					Label("Extract Here", systemImage: "archivebox")
				}
			}
			Menu {
				ForEach(ArchiveFormat.creatable, id: \.fileExtension) { format in
					Button(format.title) { onCompress(format) }
				}
			} label: {
				Label("Compress", systemImage: "doc.zipper")
			}

			Button(action: onShare) {
				Label("Share", systemImage: "square.and.arrow.up")
			}
			Button(action: onCopyPath) {
				Label("Copy Path", systemImage: "doc.on.clipboard")
			}
			Button(action: onToggleBookmark) {
				Label(isBookmarked ? "Remove Bookmark" : "Add Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
			}

			Menu {
				Button("Symbolic Link", action: onCreateSymlink)
				Button("Hard Link", action: onCreateHardlink)
			} label: {
				Label("Create Link", systemImage: "link")
			}

			Divider()

			Button(role: .destructive, action: onDelete) {
				Label("Delete", systemImage: "trash")
			}
		}
	}
}
