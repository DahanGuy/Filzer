import PartyUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Filza's core screen: browses one folder with list/grid layout, sorting, multi-select
/// batch actions, and every per-item action via context menu / swipe. Pushes a fresh
/// instance of itself for subfolders and `FileViewerRoute` for files.
///
/// Every instance (root or a pushed subfolder) can open the Disks/Bookmarks/Recents/
/// Settings flyouts — only `isRoot` (the single top-level instance `RootBrowserShell`
/// owns) shows them on the leading side, alongside the system back button everywhere
/// else; see `leadingToolbarContent`/`trailingToolbarContent`.
struct FileBrowserView: View {
	let rootURL: URL
	var displayName: String? = nil
	var isRoot: Bool = false

	@EnvironmentObject private var settings: SettingsStore
	@EnvironmentObject private var clipboard: ClipboardStore
	@EnvironmentObject private var bookmarks: BookmarksStore

	@StateObject private var viewModel: FileBrowserViewModel
	@Environment(\.isSearching) private var isSearching
	@State private var searchQuery = ""
	@State private var searchResults: [FileNode] = []
	@State private var isSearchLoading = false
	@State private var searchTask: Task<Void, Never>?
	@State private var isPathInputMode = false
	@State private var pathSuggestions: [String] = []
	@State private var pathSuggestionsTask: Task<Void, Never>?

	@State private var showingImporter = false
	@State private var infoNode: FileNode?
	@State private var openAsTarget: OpenAsTarget?
	@State private var pendingDeleteURLs: [URL] = []
	@State private var showingDeleteConfirmation = false
	@State private var pendingNavigation: PendingNavigation?

	@State private var showingDisks = false
	@State private var showingBookmarks = false
	@State private var showingRecents = false
	@State private var showingSettings = false

	private struct PendingNavigation: Identifiable {
		let url: URL
		let displayName: String?
		/// True for a Bookmarks/Disks jump: the destination's own parent is inserted
		/// onto the stack first (see `BookmarkDestinationRoute`) so backing out of the
		/// destination lands on the folder above it, not back on whatever screen
		/// presented the flyout.
		var insertParent: Bool = false
		var id: URL { url }
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
			if isSearching || isPathInputMode {
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
		.toolbar { toolbarBottom }
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
			NavigationView {
				DisksFlyoutView(onNavigate: { navigate(to: $0, displayName: $1, insertParent: true) })
			}.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingBookmarks) {
			NavigationView {
				BookmarksFlyoutView(currentPath: rootURL.path, onNavigate: { navigate(to: $0, displayName: $1, insertParent: true) })
			}.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingRecents) {
			NavigationView { RecentsFlyoutView() }.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingSettings) {
			SettingsView()
		}
		.onChange(of: searchQuery) { _ in
			if isPathInputMode {
				schedulePathSuggestions()
			} else {
				scheduleSearch()
			}
		}
		.onChange(of: isSearching) { newValue in
			if !newValue { resetPathInputMode() }
		}
		.onSubmit(of: .search) {
			if isPathInputMode { navigate(to: URL(fileURLWithPath: searchQuery), displayName: nil) }
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

	private var isSearchActive: Bool {
		!searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	/// A single hidden `NavigationLink` driving programmatic push — used by the search
	/// bar's path-input mode and by tapping a folder inside the Disks/Bookmarks
	/// flyouts (which dismiss themselves and hand the target back here via
	/// `onNavigate`, so the folder opens in *this* screen's own stack instead of
	/// nesting inside the flyout's).
	private var navigationLinks: some View {
		NavigationLink(
			destination: pendingNavigationDestination,
			isActive: Binding(get: { pendingNavigation != nil }, set: { if !$0 { pendingNavigation = nil } })
		) {
			EmptyView()
		}
	}

	@ViewBuilder
	private var pendingNavigationDestination: some View {
		if let pendingNavigation {
			if pendingNavigation.insertParent {
				BookmarkDestinationRoute(url: pendingNavigation.url, displayName: pendingNavigation.displayName)
			} else {
				FileBrowserView(rootURL: pendingNavigation.url, displayName: pendingNavigation.displayName)
			}
		} else {
			EmptyView()
		}
	}

	private func navigate(to url: URL, displayName: String?, insertParent: Bool = false) {
		isPathInputMode = false
		searchQuery = ""
		pendingNavigation = PendingNavigation(url: url, displayName: displayName, insertParent: insertParent)
	}

	// MARK: - Empty / search states

	@ViewBuilder
	private var emptyStateContent: some View {
		if viewModel.loadErrorMessage != nil {
			EmptyStateView(icon: "lock", title: "No Access")
		} else {
			EmptyStateView(icon: "folder", title: "This Folder Is Empty")
		}
	}

	/// Recursive (subfolders too) or flat (current folder only) per
	/// `settings.recursiveSearch` - see `scheduleSearch`. The persistent path-input
	/// toggle lives in `toolbarBottom`, not here, so it's reachable even before the
	/// user has engaged the native search field at all.
	@ViewBuilder
	private var searchResultsContent: some View {
		if isPathInputMode {
			VStack(spacing: 0) {
				HStack(spacing: 12) {
					Button {
						UIPasteboard.general.string = rootURL.path
					} label: {
						Image(systemName: "doc.on.doc")
					}
					Text(searchQuery.isEmpty ? rootURL.path : searchQuery)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.head)
					Spacer()
				}
				.padding(.horizontal)
				.padding(.vertical, 8)
				pathSuggestionsContent
			}
		} else if isSearchLoading {
			ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if searchResults.isEmpty {
			EmptyStateView(icon: "magnifyingglass", title: "No Results")
		} else {
			List { ForEach(searchResults) { row(for: $0) } }
				.listStyle(.plain)
		}
	}

	@ViewBuilder
	private var pathSuggestionsContent: some View {
		if pathSuggestions.isEmpty {
			EmptyStateView(icon: "folder", title: "No Matching Folders")
		} else {
			List(pathSuggestions, id: \.self) { suggestion in
				Button {
					navigate(to: URL(fileURLWithPath: suggestion), displayName: nil)
				} label: {
					Label(suggestion, systemImage: "folder")
				}
			}
			.listStyle(.plain)
		}
	}

	private func togglePathInputMode() {
		isPathInputMode.toggle()
		if isPathInputMode {
			searchQuery = rootURL.path
			schedulePathSuggestions()
		} else {
			searchQuery = ""
			pathSuggestions = []
		}
	}

	private func resetPathInputMode() {
		isPathInputMode = false
		pathSuggestions = []
	}

	/// Lists the parent of whatever path is currently typed and keeps folders whose
	/// name starts with the partial last segment — an inaccessible parent silently
	/// yields no suggestions rather than surfacing an error popup.
	private func schedulePathSuggestions() {
		pathSuggestionsTask?.cancel()
		let typed = searchQuery
		let includeHidden = settings.showHiddenFiles
		pathSuggestionsTask = Task {
			try? await Task.sleep(nanoseconds: 200_000_000)
			guard !Task.isCancelled else { return }
			let parentPath = (typed as NSString).deletingLastPathComponent
			let partial = (typed as NSString).lastPathComponent
			let parentURL = URL(fileURLWithPath: parentPath.isEmpty ? "/" : parentPath)
			guard let children = try? await FileSystem.current.listDirectory(at: parentURL, includeHidden: includeHidden) else {
				guard !Task.isCancelled else { return }
				pathSuggestions = []
				return
			}
			guard !Task.isCancelled else { return }
			let matches = children
				.filter { $0.isDirectory && (partial.isEmpty || $0.name.lowercased().hasPrefix(partial.lowercased())) }
				.map { parentURL.appendingPathComponent($0.name).path }
				.sorted()
			pathSuggestions = Array(matches.prefix(30))
		}
	}

	/// Recursive (subfolders too) or flat (current folder only) per
	/// `settings.recursiveSearch`, debounced the same as `schedulePathSuggestions`.
	/// Any failure - an inaccessible folder anywhere in a recursive walk, or the
	/// current folder itself going unreadable mid-session - is skipped silently
	/// rather than surfacing an error popup; the user just sees fewer/no results.
	private func scheduleSearch() {
		searchTask?.cancel()
		guard isSearchActive else {
			searchResults = []
			isSearchLoading = false
			return
		}
		let query = searchQuery
		let root = rootURL
		let includeHidden = settings.showHiddenFiles
		let recursive = settings.recursiveSearch
		isSearchLoading = true
		searchTask = Task {
			try? await Task.sleep(nanoseconds: 300_000_000)
			guard !Task.isCancelled else { return }
			let results: [FileNode]
			do {
				if recursive {
					results = try await FileSystem.current.search(root: root, query: query, includeHidden: includeHidden)
				} else {
					let children = try await FileSystem.current.listDirectory(at: root, includeHidden: includeHidden)
					results = children.filter { $0.name.localizedCaseInsensitiveContains(query) }
				}
			} catch {
				results = []
			}
			guard !Task.isCancelled else { return }
			searchResults = results
			isSearchLoading = false
		}
	}

	// MARK: - Content

	@ViewBuilder
	private var content: some View {
		switch settings.viewMode {
		case .list:
			List { ForEach(viewModel.nodes) { row(for: $0) } }
				.listStyle(.plain)
		case .grid:
			ScrollView {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 20) {
					ForEach(viewModel.nodes) { gridCell(for: $0) }
				}
				.padding()
			}
		}
	}

	/// A symlink never lands on Quick Look for itself — `resolvingSymlinksInPath`
	/// follows the *entire* chain (not just one hop, unlike `symbolicLinkDestination`)
	/// so this opens the real browser or viewer for whatever it ultimately points to,
	/// exactly like tapping that target directly would. Fully synchronous: no loading
	/// spinner between tapping a folder-symlink and it pushing.
	@ViewBuilder
	private func destination(for node: FileNode) -> some View {
		if node.isSymbolicLink {
			let resolved = node.url.resolvingSymlinksInPath()
			if node.symbolicLinkTargetIsDirectory {
				FileBrowserView(rootURL: resolved, displayName: node.name)
			} else if let target = try? FileNode.make(at: resolved) {
				FileViewerRoute(node: target)
			} else {
				EmptyStateView(icon: "questionmark.folder", title: "Broken Link")
			}
		} else if node.isDirectory {
			FileBrowserView(rootURL: node.url)
		} else {
			FileViewerRoute(node: node)
		}
	}

	@ViewBuilder
	private func row(for node: FileNode) -> some View {
		Group {
			if viewModel.isSelecting {
				Button {
					viewModel.toggleSelection(of: node)
				} label: {
					FileRow(node: node, selection: viewModel.selection.contains(node.url))
				}
				.buttonStyle(.plain)
			} else {
				NavigationLink(destination: destination(for: node)) {
					FileRow(node: node)
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
			} else {
				NavigationLink(destination: destination(for: node)) {
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
					.opacity(node.isHidden ? 0.65 : 1)
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
				.foregroundStyle(node.isHidden ? Color(.secondaryLabel) : Color(.label))
		}
		.frame(maxWidth: .infinity)
		.opacity(node.isHidden ? 0.92 : 1)
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

	/// A persistent bottom-bar button beside the (top) search field, switching it
	/// between recursive/flat search and a path-input mode with live autosuggest -
	/// reachable whether or not the native search field is currently engaged.
	@ToolbarContentBuilder
	private var toolbarBottom: some ToolbarContent {
		if !viewModel.isSelecting {
			ToolbarItem(placement: .bottomBar) {
				Button {
					togglePathInputMode()
				} label: {
					Image(systemName: isPathInputMode ? "magnifyingglass" : "arrow.triangle.turn.up.right.circle")
				}
			}
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

	/// Root's trailing side has no spare room next to its 4 leading icons, so
	/// Select/Add/Sort collapse into one explicit menu. A pushed subfolder frees the
	/// leading side down to just the back button, so it keeps Select/Add/Sort as
	/// separate items and gains one more menu — for the Disks/Bookmarks/Recents/
	/// Settings flyouts that root's leading icons would otherwise provide.
	@ViewBuilder
	private var trailingToolbarContent: some View {
		if viewModel.isSelecting {
			HStack(spacing: 18) {
				Button(viewModel.selection.count == viewModel.nodes.count ? "Deselect All" : "Select All") {
					if viewModel.selection.count == viewModel.nodes.count {
						viewModel.selection.removeAll()
					} else {
						viewModel.selection = Set(viewModel.nodes.map(\.url))
					}
				}
				batchActionsMenu
			}
		} else if isRoot {
			rootActionsMenu
		} else {
			HStack(spacing: 18) {
				Button("Select") { viewModel.isSelecting = true }
				sortMenu
				addMenu
				locationsMenu
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

	/// Root's single trailing menu: Select is a plain action, Add/Sort are nested
	/// submenus with identical content to the subfolder toolbar's own `addMenu`/
	/// `sortMenu` below.
	private var rootActionsMenu: some View {
		Menu {
			Button {
				viewModel.isSelecting = true
			} label: {
				Label("Select", systemImage: "checkmark.circle")
			}
			Menu {
				addMenuItems
			} label: {
				Label("Add", systemImage: "plus.circle")
			}
			Menu {
				sortMenuItems
			} label: {
				Label("Sort", systemImage: "arrow.up.arrow.down.circle")
			}
		} label: {
			Image(systemName: "ellipsis.circle")
		}
	}

	/// A subfolder's extra trailing menu, standing in for the Disks/Bookmarks/Recents/
	/// Settings icons root shows on its (here unavailable) leading side.
	private var locationsMenu: some View {
		Menu {
			Button { showingDisks = true } label: { Label("Disks", systemImage: "externaldrive") }
			Button { showingBookmarks = true } label: { Label("Bookmarks", systemImage: "bookmark") }
			Button { showingRecents = true } label: { Label("Recents", systemImage: "clock") }
			Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
		} label: {
			Image(systemName: "ellipsis.circle")
		}
	}

	private var sortMenu: some View {
		Menu {
			sortMenuItems
		} label: {
			Image(systemName: "arrow.up.arrow.down.circle")
		}
	}

	/// Sort field + direction only — view mode (list/grid) and hidden-file visibility
	/// are app-wide preferences that live in Settings, not per-folder sort options.
	@ViewBuilder
	private var sortMenuItems: some View {
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
	}

	private var sortFieldBinding: Binding<FileSortField> {
		Binding(
			get: { settings.sortDescriptor.field },
			set: { settings.sortDescriptor.field = $0 }
		)
	}

	private var addMenu: some View {
		Menu {
			addMenuItems
		} label: {
			Image(systemName: "plus.circle")
		}
	}

	@ViewBuilder
	private var addMenuItems: some View {
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

/// Pushed instead of the destination directly for a Bookmarks/Disks jump. Inserts the
/// destination's own parent onto the stack first and auto-pushes the destination on
/// top of it, so backing out of the destination lands on the folder above it in the
/// filesystem - continuing to browse around where the jump landed - rather than back
/// on whatever screen presented the flyout. A destination with no distinct parent
/// (already the volume root) skips the wrapper and pushes straight through.
private struct BookmarkDestinationRoute: View {
	let url: URL
	let displayName: String?

	@State private var isTargetActive = false

	private var parentURL: URL { url.deletingLastPathComponent() }

	var body: some View {
		if parentURL.path == url.path {
			FileBrowserView(rootURL: url, displayName: displayName)
		} else {
			FileBrowserView(rootURL: parentURL)
				.background(
					NavigationLink(
						destination: FileBrowserView(rootURL: url, displayName: displayName),
						isActive: $isTargetActive
					) { EmptyView() }
				)
				.onAppear { isTargetActive = true }
		}
	}
}
