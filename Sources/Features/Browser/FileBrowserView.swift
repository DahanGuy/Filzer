import PartyUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Filza's core screen: browses one folder with list/grid layout, sorting, multi-select
/// batch actions, and every per-item action via context menu / swipe. Pushes a fresh
/// instance of itself for subfolders and `FileViewerRoute` for files.
///
/// `isRoot` marks the single top-level instance (`RootBrowserShell`'s own root, browsing
/// "/"): only that instance shows the Disks/Bookmarks/Recents/Settings flyout buttons — every
/// pushed subfolder is a plain instance with `isRoot == false`.
struct FileBrowserView: View {
	let rootURL: URL
	var displayName: String? = nil
	var isRoot: Bool = false

	@EnvironmentObject private var settings: SettingsStore
	@EnvironmentObject private var clipboard: ClipboardStore
	@EnvironmentObject private var bookmarks: BookmarksStore

	@StateObject private var viewModel: FileBrowserViewModel
	@State private var searchQuery = ""
	@State private var searchScope: SearchScope = .thisFolder
	@State private var searchResults: [FileNode] = []
	@State private var isSearchingRoot = false
	@State private var searchTask: Task<Void, Never>?

	@State private var showingImporter = false
	@State private var infoNode: FileNode?
	@State private var openAsTarget: OpenAsTarget?
	@State private var pendingDeleteURLs: [URL] = []
	@State private var showingDeleteConfirmation = false
	@State private var goToPathTarget: URL?

	@State private var showingDisks = false
	@State private var showingBookmarks = false
	@State private var showingRecents = false
	@State private var showingSettings = false

	enum SearchScope: String, CaseIterable, Identifiable {
		case thisFolder = "This Folder"
		case root = "Root"
		var id: String { rawValue }
	}

	init(rootURL: URL, displayName: String? = nil, isRoot: Bool = false) {
		self.rootURL = rootURL
		self.displayName = displayName
		self.isRoot = isRoot
		_viewModel = StateObject(wrappedValue: FileBrowserViewModel(rootURL: rootURL))
	}

	private struct OpenAsTarget: Identifiable {
		let node: FileNode
		let kind: ViewerKind
		var id: String { node.url.path + kind.rawValue }
	}

	var body: some View {
		Group {
			if isSearchActive {
				searchResultsContent
			} else if viewModel.isLoading && viewModel.nodes.isEmpty {
				ProgressView()
			} else if viewModel.nodes.isEmpty {
				emptyStateContent
			} else {
				content
			}
		}
		.navigationTitle(displayName ?? rootURL.lastPathComponent)
		.searchable(text: $searchQuery, prompt: "Search")
		.toolbar { toolbarLeading }
		.toolbar { toolbarTrailing }
		.background(navigationLinks)
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
			"Delete \(pendingDeleteURLs.count) item\(pendingDeleteURLs.count == 1 ? "" : "s")? This can't be undone.",
			isPresented: $showingDeleteConfirmation,
			titleVisibility: .visible
		) {
			Button("Delete", role: .destructive) {
				let urls = pendingDeleteURLs
				Task {
					await viewModel.delete(urls)
					viewModel.endSelecting()
				}
			}
			Button("Cancel", role: .cancel) {}
		}
		.popover(isPresented: $showingDisks) {
			NavigationView { DisksFlyoutView() }.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingBookmarks) {
			NavigationView { BookmarksFlyoutView() }.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingRecents) {
			NavigationView { RecentsFlyoutView() }.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingSettings) {
			SettingsView()
		}
		.onChange(of: searchQuery) { _ in scheduleRootSearchIfNeeded() }
		.onChange(of: searchScope) { _ in scheduleRootSearchIfNeeded() }
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

	private var isSearchActive: Bool {
		!searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private var filteredNodes: [FileNode] {
		guard !searchQuery.isEmpty else { return viewModel.nodes }
		return viewModel.nodes.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
	}

	/// A single hidden `NavigationLink` driving programmatic push for "Go to Path" —
	/// `Alertinator.prompt`'s completion isn't inside a `NavigationLink` builder, so the
	/// push has to be wired up this way instead.
	private var navigationLinks: some View {
		NavigationLink(
			destination: goToPathDestination,
			isActive: Binding(get: { goToPathTarget != nil }, set: { if !$0 { goToPathTarget = nil } })
		) {
			EmptyView()
		}
	}

	@ViewBuilder
	private var goToPathDestination: some View {
		if let goToPathTarget {
			FileBrowserView(rootURL: goToPathTarget)
		} else {
			EmptyView()
		}
	}

	// MARK: - Empty / search states

	@ViewBuilder
	private var emptyStateContent: some View {
		if viewModel.loadErrorMessage != nil {
			EmptyStateView(
				icon: "lock",
				title: "No Access",
				message: "Filzer can't read this location. Try Disks or Bookmarks to get to somewhere accessible."
			)
		} else {
			EmptyStateView(icon: "folder", title: "This Folder Is Empty")
		}
	}

	@ViewBuilder
	private var searchResultsContent: some View {
		VStack(spacing: 0) {
			Picker("Scope", selection: $searchScope) {
				ForEach(SearchScope.allCases) { scope in
					Text(scope.rawValue).tag(scope)
				}
			}
			.pickerStyle(.segmented)
			.padding(.horizontal)
			.padding(.vertical, 8)

			switch searchScope {
			case .thisFolder:
				if filteredNodes.isEmpty {
					EmptyStateView(icon: "magnifyingglass", title: "No Results")
				} else {
					List { ForEach(filteredNodes) { row(for: $0) } }
						.listStyle(.plain)
				}
			case .root:
				if isSearchingRoot {
					ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
				} else if searchResults.isEmpty {
					EmptyStateView(icon: "magnifyingglass", title: "No Results")
				} else {
					List { ForEach(searchResults) { row(for: $0) } }
						.listStyle(.plain)
				}
			}
		}
	}

	private func scheduleRootSearchIfNeeded() {
		searchTask?.cancel()
		guard searchScope == .root, isSearchActive else {
			searchResults = []
			isSearchingRoot = false
			return
		}
		let query = searchQuery
		let root = searchRootURL
		let includeHidden = settings.showHiddenFiles
		isSearchingRoot = true
		searchTask = Task {
			try? await Task.sleep(nanoseconds: 300_000_000)
			guard !Task.isCancelled else { return }
			do {
				let results = try await FileSystem.current.search(root: root, query: query, includeHidden: includeHidden)
				guard !Task.isCancelled else { return }
				searchResults = results
			} catch {
				if !Task.isCancelled { viewModel.errorMessage = error.localizedDescription }
			}
			isSearchingRoot = false
		}
	}

	/// The nearest known accessible root above (or at) `rootURL` — Filzer's own
	/// container, or whichever bookmarked external folder contains it. Recursive search
	/// from the literal device root would always be empty (a sandboxed app can't even
	/// list "/"), so "Root" scope searches from here instead.
	private var searchRootURL: URL {
		let home = URL(fileURLWithPath: NSHomeDirectory())
		if rootURL.path.hasPrefix(home.path) { return home }
		for entry in bookmarks.entries {
			let resolved = bookmarks.resolvedURL(for: entry)
			if rootURL.path.hasPrefix(resolved.path) { return resolved }
		}
		return rootURL
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

	// MARK: - Toolbar

	@ToolbarContentBuilder
	private var toolbarLeading: some ToolbarContent {
		ToolbarItem(placement: .navigationBarLeading) {
			leadingToolbarContent
		}
	}

	@ToolbarContentBuilder
	private var toolbarTrailing: some ToolbarContent {
		ToolbarItem(placement: .navigationBarTrailing) {
			trailingToolbarContent
		}
	}

	@ViewBuilder
	private var leadingToolbarContent: some View {
		if viewModel.isSelecting {
			Button("Cancel") { viewModel.endSelecting() }
		} else if isRoot {
			HStack(spacing: 18) {
				Button { showingDisks = true } label: { Image(systemName: "externaldrive") }
				Button { showingBookmarks = true } label: { Image(systemName: "bookmark") }
				Button { showingRecents = true } label: { Image(systemName: "clock") }
				Button { showingSettings = true } label: { Image(systemName: "gearshape") }
			}
		}
	}

	@ViewBuilder
	private var trailingToolbarContent: some View {
		if viewModel.isSelecting {
			HStack(spacing: 18) {
				Button(viewModel.selection.count == filteredNodes.count ? "Deselect All" : "Select All") {
					if viewModel.selection.count == filteredNodes.count {
						viewModel.selection.removeAll()
					} else {
						viewModel.selection = Set(filteredNodes.map(\.url))
					}
				}
				batchActionsMenu
			}
		} else {
			HStack(spacing: 18) {
				Button("Select") { viewModel.isSelecting = true }
				sortMenu
				addMenu
			}
		}
	}

	private var batchActionsMenu: some View {
		Menu {
			Button {
				clipboard.set(Array(viewModel.selection), operation: .copy)
				viewModel.endSelecting()
			} label: {
				Label("Copy", systemImage: "doc.on.doc")
			}
			Button {
				clipboard.set(Array(viewModel.selection), operation: .move)
				viewModel.endSelecting()
			} label: {
				Label("Move", systemImage: "folder")
			}
			Button {
				let urls = Array(viewModel.selection)
				Task {
					await viewModel.compress(urls)
					viewModel.endSelecting()
				}
			} label: {
				Label("Compress", systemImage: "doc.zipper")
			}
			Button {
				presentMultiShareSheet(for: Array(viewModel.selection))
			} label: {
				Label("Share", systemImage: "square.and.arrow.up")
			}
			Divider()
			Button(role: .destructive) {
				pendingDeleteURLs = Array(viewModel.selection)
				showingDeleteConfirmation = true
			} label: {
				Label("Delete", systemImage: "trash")
			}
		} label: {
			Image(systemName: "ellipsis.circle")
		}
		.disabled(viewModel.selection.isEmpty)
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
			Divider()
			Button {
				promptGoToPath()
			} label: {
				Label("Go to Path\u{2026}", systemImage: "arrow.forward.to.line")
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

	private func promptGoToPath() {
		Alertinator.shared.prompt(title: "Go to Path", placeholder: "/path/to/folder", text: rootURL.path) { path in
			guard let path, !path.isEmpty else { return }
			goToPathTarget = URL(fileURLWithPath: path)
		}
	}
}
