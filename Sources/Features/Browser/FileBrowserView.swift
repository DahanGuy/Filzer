import PartyUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Filza's core screen: browses one folder with list/grid layout, sorting, multi-select
/// batch actions, and every per-item action via context menu / swipe. Pushes a fresh
/// instance of itself for subfolders and `FileViewerRoute` for files.
struct FileBrowserView: View {
	let rootURL: URL
	var displayName: String? = nil

	@EnvironmentObject private var settings: SettingsStore
	@EnvironmentObject private var clipboard: ClipboardStore
	@EnvironmentObject private var trash: TrashStore
	@EnvironmentObject private var bookmarks: BookmarksStore

	@StateObject private var viewModel: FileBrowserViewModel
	@State private var searchQuery = ""
	@State private var showingImporter = false
	@State private var infoNode: FileNode?
	@State private var openAsTarget: OpenAsTarget?
	@State private var pendingDeleteURLs: [URL] = []
	@State private var showingDeleteConfirmation = false

	init(rootURL: URL, displayName: String? = nil) {
		self.rootURL = rootURL
		self.displayName = displayName
		_viewModel = StateObject(wrappedValue: FileBrowserViewModel(rootURL: rootURL))
	}

	private struct OpenAsTarget: Identifiable {
		let node: FileNode
		let kind: ViewerKind
		var id: String { node.url.path + kind.rawValue }
	}

	var body: some View {
		Group {
			if viewModel.isLoading && viewModel.nodes.isEmpty {
				ProgressView()
			} else if filteredNodes.isEmpty {
				EmptyStateView(
					icon: "folder",
					title: searchQuery.isEmpty ? "This Folder Is Empty" : "No Results",
					message: searchQuery.isEmpty ? nil : "No items match \u{201c}\(searchQuery)\u{201d}."
				)
			} else {
				content
			}
		}
		.navigationTitle(displayName ?? rootURL.lastPathComponent)
		.searchable(text: $searchQuery, prompt: "Search This Folder")
		.toolbar { toolbarContent }
		.safeAreaInset(edge: .bottom) { bottomBar }
		.sheet(item: $infoNode) { node in
			NavigationView { FileInfoView(node: node) }
				.navigationViewStyle(.stack)
		}
		.sheet(item: $openAsTarget) { target in
			NavigationView { FileViewerRoute(node: target.node, forcedKind: target.kind) }
				.navigationViewStyle(.stack)
		}
		.fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
			switch result {
			case .success(let urls):
				Task { await viewModel.importItems(urls) }
			case .failure(let error):
				viewModel.errorMessage = error.localizedDescription
			}
		}
		.confirmationDialog(
			"Delete \(pendingDeleteURLs.count) item\(pendingDeleteURLs.count == 1 ? "" : "s")?",
			isPresented: $showingDeleteConfirmation,
			titleVisibility: .visible
		) {
			Button("Delete", role: .destructive) {
				let urls = pendingDeleteURLs
				Task {
					await viewModel.delete(urls, useTrash: settings.useTrash, trash: trash)
					viewModel.endSelecting()
				}
			}
			Button("Cancel", role: .cancel) {}
		}
		.task {
			viewModel.includeHidden = settings.showHiddenFiles
			viewModel.sortDescriptor = settings.sortDescriptor
			await viewModel.reload()
		}
		.onChange(of: settings.showHiddenFiles) { newValue in
			viewModel.includeHidden = newValue
			Task { await viewModel.reload() }
		}
		.onChange(of: settings.sortDescriptor) { newValue in
			viewModel.sortDescriptor = newValue
			Task { await viewModel.reload() }
		}
		.errorAlert($viewModel.errorMessage)
	}

	private var filteredNodes: [FileNode] {
		guard !searchQuery.isEmpty else { return viewModel.nodes }
		return viewModel.nodes.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		switch settings.viewMode {
		case .list:
			List { ForEach(filteredNodes) { row(for: $0) } }
				.listStyle(.plain)
		case .grid:
			ScrollView {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 20) {
					ForEach(filteredNodes) { gridCell(for: $0) }
				}
				.padding()
			}
		}
	}

	@ViewBuilder
	private func row(for node: FileNode) -> some View {
		Group {
			if viewModel.isSelecting {
				Button {
					viewModel.toggleSelection(of: node)
				} label: {
					FileRow(node: node, fontSize: settings.fontSize, selection: viewModel.selection.contains(node.url))
				}
				.buttonStyle(.plain)
			} else if node.isDirectory {
				NavigationLink(destination: FileBrowserView(rootURL: node.url)) {
					FileRow(node: node, fontSize: settings.fontSize)
				}
			} else {
				NavigationLink(destination: FileViewerRoute(node: node)) {
					FileRow(node: node, fontSize: settings.fontSize)
				}
			}
		}
		.swipeActions(edge: .trailing) {
			if !viewModel.isSelecting {
				Button(role: .destructive) {
					pendingDeleteURLs = [node.url]
					showingDeleteConfirmation = true
				} label: {
					Label("Delete", systemImage: "trash")
				}
				Button {
					promptRename(node)
				} label: {
					Label("Rename", systemImage: "pencil")
				}
				.tint(.orange)
			}
		}
		.contextMenu {
			contextMenu(for: node)
		}
	}

	@ViewBuilder
	private func gridCell(for node: FileNode) -> some View {
		Group {
			if viewModel.isSelecting {
				Button {
					viewModel.toggleSelection(of: node)
				} label: {
					gridCellContent(node)
				}
				.buttonStyle(.plain)
			} else if node.isDirectory {
				NavigationLink(destination: FileBrowserView(rootURL: node.url)) {
					gridCellContent(node)
				}
			} else {
				NavigationLink(destination: FileViewerRoute(node: node)) {
					gridCellContent(node)
				}
			}
		}
		.contextMenu {
			contextMenu(for: node)
		}
	}

	private func gridCellContent(_ node: FileNode) -> some View {
		VStack(spacing: 6) {
			ZStack(alignment: .topTrailing) {
				FileIconView(node: node)
				if viewModel.isSelecting {
					Image(systemName: viewModel.selection.contains(node.url) ? "checkmark.circle.fill" : "circle")
						.font(.caption)
						.foregroundStyle(viewModel.selection.contains(node.url) ? Color.accentColor : Color(.tertiaryLabel))
						.offset(x: 10, y: -6)
				}
			}
			Text(node.name)
				.font(.caption)
				.lineLimit(2)
				.multilineTextAlignment(.center)
				.foregroundStyle(Color(.label))
		}
		.frame(maxWidth: .infinity)
	}

	@ViewBuilder
	private func contextMenu(for node: FileNode) -> some View {
		FileRowContextMenuContent(
			node: node,
			isBookmarked: bookmarks.isBookmarked(node.url),
			onInfo: { infoNode = node },
			onOpenAs: { openAsTarget = OpenAsTarget(node: node, kind: $0) },
			onRename: { promptRename(node) },
			onDuplicate: { Task { await viewModel.duplicate(node) } },
			onCopy: { clipboard.set([node.url], operation: .copy) },
			onMove: { clipboard.set([node.url], operation: .move) },
			onCompress: { Task { await viewModel.compress([node.url]) } },
			onExtractHere: { Task { await viewModel.extractHere(node) } },
			onShare: { presentMultiShareSheet(for: [node.url]) },
			onCopyPath: { UIPasteboard.general.string = node.url.path },
			onToggleBookmark: { bookmarks.toggle(url: node.url, displayName: node.name) },
			onCreateSymlink: { Task { await viewModel.createSymbolicLink(name: "\(node.name) symlink", target: node.url) } },
			onCreateHardlink: { Task { await viewModel.createHardLink(name: "\(node.name) link", target: node.url) } },
			onDelete: {
				pendingDeleteURLs = [node.url]
				showingDeleteConfirmation = true
			}
		)
	}

	// MARK: - Bottom bar

	@ViewBuilder
	private var bottomBar: some View {
		if viewModel.isSelecting {
			SelectionToolbar(
				selectionCount: viewModel.selection.count,
				onCopy: {
					clipboard.set(Array(viewModel.selection), operation: .copy)
					viewModel.endSelecting()
				},
				onMove: {
					clipboard.set(Array(viewModel.selection), operation: .move)
					viewModel.endSelecting()
				},
				onCompress: {
					let urls = Array(viewModel.selection)
					Task {
						await viewModel.compress(urls)
						viewModel.endSelecting()
					}
				},
				onShare: { presentMultiShareSheet(for: Array(viewModel.selection)) },
				onDelete: {
					pendingDeleteURLs = Array(viewModel.selection)
					showingDeleteConfirmation = true
				}
			)
		} else if !clipboard.isEmpty, let payload = clipboard.payload {
			PasteboardBanner(
				count: payload.urls.count,
				operation: payload.operation,
				onPaste: { Task { await viewModel.paste(clipboard: clipboard) } },
				onClear: { clipboard.clear() }
			)
		}
	}

	// MARK: - Toolbar

	@ToolbarContentBuilder
	private var toolbarContent: some ToolbarContent {
		if viewModel.isSelecting {
			ToolbarItem(placement: .navigationBarLeading) {
				Button("Cancel") { viewModel.endSelecting() }
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				Button(viewModel.selection.count == filteredNodes.count ? "Deselect All" : "Select All") {
					if viewModel.selection.count == filteredNodes.count {
						viewModel.selection.removeAll()
					} else {
						viewModel.selection = Set(filteredNodes.map(\.url))
					}
				}
			}
		} else {
			ToolbarItem(placement: .navigationBarLeading) {
				Button("Select") { viewModel.isSelecting = true }
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				HStack(spacing: 18) {
					sortMenu
					addMenu
				}
			}
		}
	}

	private var sortMenu: some View {
		Menu {
			Picker("Sort By", selection: sortFieldBinding) {
				ForEach(FileSortField.allCases) { field in
					Text(field.title).tag(field)
				}
			}
			Button {
				settings.sortDescriptor.ascending.toggle()
			} label: {
				Label(
					settings.sortDescriptor.ascending ? "Ascending" : "Descending",
					systemImage: settings.sortDescriptor.ascending ? "arrow.up" : "arrow.down"
				)
			}
			Divider()
			Button {
				settings.viewMode = settings.viewMode == .list ? .grid : .list
			} label: {
				Label(settings.viewMode == .list ? "Grid View" : "List View", systemImage: settings.viewMode == .list ? "square.grid.2x2" : "list.bullet")
			}
			Button {
				settings.showHiddenFiles.toggle()
			} label: {
				Label(settings.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files", systemImage: "eye")
			}
		} label: {
			Image(systemName: "arrow.up.arrow.down.circle")
		}
	}

	private var sortFieldBinding: Binding<FileSortField> {
		Binding(
			get: { settings.sortDescriptor.field },
			set: { settings.sortDescriptor.field = $0 }
		)
	}

	private var addMenu: some View {
		Menu {
			Button {
				promptNewFolder()
			} label: {
				Label("New Folder", systemImage: "folder.badge.plus")
			}
			Button {
				promptNewFile()
			} label: {
				Label("New File", systemImage: "doc.badge.plus")
			}
			Button {
				showingImporter = true
			} label: {
				Label("Import\u{2026}", systemImage: "square.and.arrow.down")
			}
			if !clipboard.isEmpty {
				Button {
					Task { await viewModel.paste(clipboard: clipboard) }
				} label: {
					Label("Paste \(clipboard.count) Item\(clipboard.count == 1 ? "" : "s")", systemImage: "doc.on.clipboard")
				}
			}
		} label: {
			Image(systemName: "plus.circle")
		}
	}

	// MARK: - Prompts

	private func promptNewFolder() {
		Alertinator.shared.prompt(title: "New Folder", placeholder: "Name", text: "untitled folder") { name in
			guard let name, !name.isEmpty else { return }
			await viewModel.createFolder(name: name)
		}
	}

	private func promptNewFile() {
		Alertinator.shared.prompt(title: "New File", placeholder: "Name", text: "untitled.txt") { name in
			guard let name, !name.isEmpty else { return }
			await viewModel.createFile(name: name)
		}
	}

	private func promptRename(_ node: FileNode) {
		Alertinator.shared.prompt(title: "Rename", placeholder: "Name", text: node.name) { name in
			guard let name, !name.isEmpty, name != node.name else { return }
			await viewModel.rename(node, to: name)
		}
	}
}
