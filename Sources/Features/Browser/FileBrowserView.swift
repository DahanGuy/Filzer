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
	@EnvironmentObject private var remoteConnections: RemoteConnectionsStore

	@StateObject private var viewModel: FileBrowserViewModel
	@FocusState private var isSearchFieldFocused: Bool
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
	@State private var hostNavigationController: UINavigationController?
	@State private var archivePasswordPromptURL: URL?
	@State private var archivePasswordInput = ""
	@State private var pendingArchivePasswordRetry: (() -> Void)?

	@State private var showingDisks = false
	@State private var showingBookmarks = false
	@State private var showingRecents = false
	@State private var showingSettings = false

	private struct PendingNavigation: Identifiable {
		let url: URL
		let displayName: String?
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
			if isSearchFieldFocused || isSearchActive || isPathInputMode {
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
		.toolbar { toolbarLeading }
		.toolbar { toolbarTrailing }
		.safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBar }
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
		.alert(
			"Password Required",
			isPresented: Binding(get: { archivePasswordPromptURL != nil }, set: { if !$0 { archivePasswordPromptURL = nil } })
		) {
			SecureField("Password", text: $archivePasswordInput)
			Button("Cancel", role: .cancel) { pendingArchivePasswordRetry = nil }
			Button("Unlock") {
				let retry = pendingArchivePasswordRetry
				pendingArchivePasswordRetry = nil
				retry?()
			}
		} message: {
			Text("\"\(archivePasswordPromptURL?.lastPathComponent ?? "")\" is password-protected.")
		}
		.popover(isPresented: $showingDisks) {
			NavigationView {
				DisksFlyoutView(onNavigate: { navigate(to: $0, displayName: $1) })
			}.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingBookmarks) {
			NavigationView {
				BookmarksFlyoutView(currentPath: rootURL.path, onNavigate: { navigate(to: $0, displayName: $1, chainFromRoot: true) })
			}.navigationViewStyle(.stack)
		}
		.popover(isPresented: $showingRecents) {
			NavigationView {
				RecentsFlyoutView(onNavigate: { navigate(to: $0, displayName: $1, chainFromRoot: true) })
			}.navigationViewStyle(.stack)
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

	/// A single hidden `NavigationLink` driving programmatic push, plus a captured
	/// reference to this screen's own `UINavigationController` (see
	/// `NavigationControllerAccessor`) — used by the search bar's path-input mode and
	/// by tapping a folder inside the Disks/Bookmarks/Recents flyouts (which dismiss
	/// themselves and hand the target back here via `onNavigate`, so the folder opens
	/// in *this* screen's own stack instead of nesting inside the flyout's).
	private var navigationLinks: some View {
		Group {
			NavigationLink(
				destination: pendingNavigationDestination,
				isActive: Binding(get: { pendingNavigation != nil }, set: { if !$0 { pendingNavigation = nil } })
			) {
				EmptyView()
			}
			NavigationControllerAccessor { hostNavigationController = $0 }
		}
	}

	@ViewBuilder
	private var pendingNavigationDestination: some View {
		if let pendingNavigation {
			FileBrowserView(rootURL: pendingNavigation.url, displayName: pendingNavigation.displayName)
		} else {
			EmptyView()
		}
	}

	/// `chainFromRoot: true` (Bookmarks/Recents jumps) walks up from the nearest
	/// reachable root and pushes every folder from there down to `url`, exactly as if
	/// the user had tapped through each one by hand, so backing out retraces the same
	/// folders one level at a time - but only when that root is the volume root or the
	/// sandbox container. An Added Folder or remote connection's own root never
	/// chains, matching Disks' own jumps: there's nothing reachable above it to walk
	/// through, so a chain rooted there would just be a same-length detour, not a
	/// meaningful "way you got there". Path-input jumps push `url` directly too - a
	/// typed path isn't "the way you got there" the way a bookmark is.
	///
	/// A chain of more than one folder is pushed by reaching straight into this
	/// screen's own `UINavigationController` (`pushChain`), never through a SwiftUI
	/// `NavigationLink`. Driving a multi-level push reactively through `pendingNavigation`
	/// - even bridged through a `UIViewControllerRepresentable` that later replaced
	/// itself - still leaves that stack slot under a live `NavigationLink(isActive:)`
	/// binding; SwiftUI "reconciles" its own tracked destination against whatever's
	/// actually there and reverts the manual change, which is exactly what showed up as
	/// the target flashing on screen and then reverting to an earlier level. A single
	/// level has nothing to reconcile against and keeps using the plain, working
	/// `pendingNavigation` path.
	private func navigate(to url: URL, displayName: String?, chainFromRoot: Bool = false) {
		isPathInputMode = false
		isSearchFieldFocused = false
		searchQuery = ""
		var chain: [URL]
		if chainFromRoot, let root = reachableRoot(containing: url), !isAddedFolderOrRemoteRoot(root) {
			chain = pathChain(from: root, to: url)
		} else {
			chain = [url]
		}
		// The chain's own first level can be exactly the folder already on screen -
		// e.g. jumping to a bookmark from the root screen ("/") itself chains from "/"
		// too, which would otherwise re-push a second, redundant "/" ahead of the one
		// already at the bottom of the stack. Drop it; everything after it is still a
		// real step down from what's currently showing.
		if chain.count > 1, chain[0].path == rootURL.path {
			chain.removeFirst()
		}
		if chain.count > 1, let hostNavigationController {
			pushChain(chain, displayName: displayName, on: hostNavigationController)
		} else {
			pendingNavigation = PendingNavigation(url: url, displayName: displayName)
		}
	}

	/// Appends every intermediate folder to the stack in one non-animated
	/// `setViewControllers` call, then pushes the final (target) folder with the usual
	/// animated transition - one clean push the user actually sees, no per-level
	/// animation cost, and (critically) no SwiftUI `NavigationLink` involved anywhere
	/// in the process to fight with the manual stack mutation.
	private func pushChain(_ chain: [URL], displayName: String?, on navigationController: UINavigationController) {
		let hostingControllers: [UIViewController] = chain.enumerated().map { index, url in
			let view = FileBrowserView(rootURL: url, displayName: index == chain.count - 1 ? displayName : nil)
				.environmentObject(settings)
				.environmentObject(clipboard)
				.environmentObject(bookmarks)
				.environmentObject(remoteConnections)
			return UIHostingController(rootView: view)
		}
		guard let last = hostingControllers.last else { return }
		navigationController.setViewControllers(navigationController.viewControllers + hostingControllers.dropLast(), animated: false)
		navigationController.pushViewController(last, animated: true)
	}

	private func isAddedFolderOrRemoteRoot(_ root: URL) -> Bool {
		let addedFolderRoots = bookmarks.entries
			.filter { $0.securityScopedBookmarkData != nil }
			.map { bookmarks.resolvedURL(for: $0).absoluteString }
		let remoteRoots = remoteConnections.connections.map { $0.rootURL.absoluteString }
		return (addedFolderRoots + remoteRoots).contains(root.absoluteString)
	}

	/// The nearest known reachable root at or above `url`, most-specific first: an
	/// Added Folder or remote connection's own root, the sandbox container, or - for
	/// any plain local path none of those cover, e.g. a bookmark somewhere like
	/// `/private/var/mobile` that sits *above* the sandbox container - the volume root
	/// itself, so the chain always has somewhere to start from and never falls back to
	/// a bare single-level push.
	private func reachableRoot(containing url: URL) -> URL? {
		var candidates = [URL(fileURLWithPath: "/"), URL(fileURLWithPath: NSHomeDirectory())]
		candidates += bookmarks.entries
			.filter { $0.securityScopedBookmarkData != nil }
			.map { bookmarks.resolvedURL(for: $0) }
		candidates += remoteConnections.connections.map(\.rootURL)
		return candidates
			.filter { isAncestor($0, of: url) }
			.max { $0.pathComponents.count < $1.pathComponents.count }
	}

	private func isAncestor(_ root: URL, of url: URL) -> Bool {
		guard root.scheme == url.scheme, root.host == url.host else { return false }
		let rootComponents = root.pathComponents
		let urlComponents = url.pathComponents
		guard urlComponents.count >= rootComponents.count else { return false }
		return Array(urlComponents.prefix(rootComponents.count)) == rootComponents
	}

	/// Every folder from `root` (first) down to (and including) `target` (last), one
	/// path component at a time.
	private func pathChain(from root: URL, to target: URL) -> [URL] {
		let remainder = target.pathComponents.dropFirst(root.pathComponents.count)
		var chain = [root]
		var current = root
		for component in remainder {
			current = current.appendingPathComponent(component)
			chain.append(current)
		}
		return chain
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
	/// `settings.recursiveSearch` - see `scheduleSearch`. Path-input mode shows live
	/// autosuggest instead - the search field itself doubles as the path field, typed
	/// or pasted directly, no separate readout needed.
	@ViewBuilder
	private var searchResultsContent: some View {
		if isPathInputMode {
			pathSuggestionsContent
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
			isSearchFieldFocused = true
			schedulePathSuggestions()
		} else {
			searchQuery = ""
			pathSuggestions = []
			isSearchFieldFocused = false
		}
	}

	/// Clears the field and fully exits search/path-input mode - the bottom bar's own
	/// "x" button, standing in for the Cancel a native `.searchable` field would give.
	private func clearSearch() {
		searchQuery = ""
		isSearchFieldFocused = false
		if isPathInputMode {
			isPathInputMode = false
			pathSuggestions = []
		}
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
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 104))], spacing: 14) {
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
		let isSelected = viewModel.selection.contains(node.url)
		return VStack(spacing: 8) {
			ZStack(alignment: .topTrailing) {
				FileIconView(node: node, size: 52)
					.opacity(node.isHidden ? 0.65 : 1)
					.frame(width: 64, height: 64)
				if viewModel.isSelecting {
					Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
						.symbolRenderingMode(.palette)
						.foregroundStyle(.white, isSelected ? Color.accentColor : Color(.systemGray3))
						.font(.system(size: 20))
						.background(Circle().fill(Color(.systemBackground)).padding(2))
						.offset(x: 6, y: -6)
				}
			}
			.frame(height: 64)

			Text(node.name)
				.font(.caption)
				.lineLimit(2)
				.multilineTextAlignment(.center)
				.foregroundStyle(node.isHidden ? Color(.secondaryLabel) : Color(.label))
				.frame(height: 30, alignment: .top)
		}
		.padding(10)
		.frame(maxWidth: .infinity)
		.background(
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
		)
		.opacity(node.isHidden ? 0.85 : 1)
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
			onCompress: { format in Task { await viewModel.compress([node.url], format: format) } },
			onExtractHere: { extractArchiveHere(node) },
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

	/// The search bar itself, at the bottom - not `.searchable`'s default top
	/// placement - a capsule field with a separate, standalone circular button beside
	/// it (same layout Contacts' own bottom search bar uses for its "+", just with a
	/// path-mode icon instead). Deliberately a `.safeAreaInset`, not a
	/// `ToolbarItem(placement: .bottomBar)`: the toolbar version was prone to
	/// rendering a stray, blank button-shaped artifact at the bottom under some
	/// content-change sequences - a known category of `ToolbarItem`/`.bottomBar`
	/// flakiness when its content changes shape dynamically. A safe-area inset is a
	/// plain view modifier on the main content, entirely outside the toolbar layout
	/// system, so there's nothing left for it to misrender.
	@ViewBuilder
	private var bottomSearchBar: some View {
		if !viewModel.isSelecting {
			HStack(spacing: 10) {
				searchOrPathField
				modeToggleButton
			}
			.padding(.horizontal)
			.padding(.vertical, 8)
			.background(.bar)
		}
	}

	private var searchOrPathField: some View {
		HStack(spacing: 8) {
			Image(systemName: isPathInputMode ? "arrow.forward.to.line" : "magnifyingglass")
				.foregroundStyle(.secondary)
			TextField(isPathInputMode ? "Path" : "Search", text: $searchQuery)
				.focused($isSearchFieldFocused)
				.autocapitalization(.none)
				.disableAutocorrection(true)
				.onSubmit {
					if isPathInputMode { navigate(to: URL(fileURLWithPath: searchQuery), displayName: nil) }
				}
			if !searchQuery.isEmpty {
				Button {
					clearSearch()
				} label: {
					Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 14)
		.frame(height: 44)
		.background(Color(.secondarySystemBackground), in: Capsule())
	}

	private var modeToggleButton: some View {
		Button {
			togglePathInputMode()
		} label: {
			Image(systemName: isPathInputMode ? "magnifyingglass" : "arrow.triangle.turn.up.right")
				.font(.system(size: 17, weight: .semibold))
				.foregroundStyle(Color(.label))
				.frame(width: 44, height: 44)
				.background(Color(.secondarySystemBackground), in: Circle())
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
				Label("Cut", systemImage: "scissors")
			}
			Menu {
				ForEach(ArchiveFormat.creatable, id: \.fileExtension) { format in
					Button(format.title) {
						let urls = Array(viewModel.selection)
						Task {
							await viewModel.compress(urls, format: format)
							viewModel.endSelecting()
						}
					}
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

	/// "Extract Here" from the context menu - unlike the interactive `ArchiveBrowserView`
	/// (which has its own password prompt), this is a one-tap action, so a
	/// password-protected archive needs its own retry loop right here.
	private func extractArchiveHere(_ node: FileNode, password: String? = nil) {
		Task {
			do {
				try await viewModel.extractHere(node, password: password)
			} catch FileSystemError.archivePasswordRequired {
				archivePasswordInput = password ?? ""
				archivePasswordPromptURL = node.url
				pendingArchivePasswordRetry = { extractArchiveHere(node, password: archivePasswordInput) }
			} catch {
				viewModel.errorMessage = error.localizedDescription
			}
		}
	}
}

/// Captures the real `UINavigationController` hosting this specific `FileBrowserView`
/// screen, once, and hands it back via `onResolve` - used only so a multi-level
/// Bookmarks/Recents chain jump (`pushChain`) can push straight onto it later,
/// entirely outside SwiftUI's own `NavigationLink`/`isActive` machinery. Driving that
/// same push *through* a live `NavigationLink` (even indirectly, via a
/// `UIViewControllerRepresentable` that swaps itself out after appearing) still left
/// SwiftUI convinced it owned that stack slot; it "reconciled" its own tracked
/// destination against the manually-pushed one and reverted the change - the target
/// flashing on screen and then reverting to an earlier level. A stack mutation that no
/// `NavigationLink` ever claimed ownership of has nothing for SwiftUI to revert.
private struct NavigationControllerAccessor: UIViewControllerRepresentable {
	let onResolve: (UINavigationController) -> Void

	func makeUIViewController(context: Context) -> ResolverViewController {
		let controller = ResolverViewController()
		controller.onResolve = onResolve
		return controller
	}

	func updateUIViewController(_ uiViewController: ResolverViewController, context: Context) {
		uiViewController.onResolve = onResolve
	}
}

private final class ResolverViewController: UIViewController {
	var onResolve: ((UINavigationController) -> Void)?

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if let navigationController {
			onResolve?(navigationController)
		}
	}
}
