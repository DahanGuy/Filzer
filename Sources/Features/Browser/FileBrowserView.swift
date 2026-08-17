import PartyUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
	@State private var showingPathNavigator = false

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
			if isSearchFieldFocused || isSearchActive {
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
		.safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
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
		.sheet(isPresented: $showingDisks) {
			NavigationView {
				DisksFlyoutView(onNavigate: { navigate(to: $0, displayName: $1) })
			}.navigationViewStyle(.stack)
		}
		.sheet(isPresented: $showingBookmarks) {
			NavigationView {
				BookmarksFlyoutView(currentPath: rootURL.path, onNavigate: { navigate(to: $0, displayName: $1, chainFromRoot: true) })
			}.navigationViewStyle(.stack)
		}
		.sheet(isPresented: $showingRecents) {
			NavigationView {
				RecentsFlyoutView(onNavigate: { navigate(to: $0, displayName: $1, chainFromRoot: true) })
			}.navigationViewStyle(.stack)
		}
		.sheet(isPresented: $showingSettings) {
			NavigationView {
				SettingsView()
			}.navigationViewStyle(.stack)
		}
		.sheet(isPresented: $showingPathNavigator) {
			NavigationView {
				PathNavigatorView(currentPath: rootURL.path, onNavigate: { navigate(to: $0, displayName: $1) })
			}.navigationViewStyle(.stack)
		}
		.onChange(of: searchQuery) { _ in
			scheduleSearch()
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

	private func navigate(to url: URL, displayName: String?, chainFromRoot: Bool = false) {
		isSearchFieldFocused = false
		searchQuery = ""
		var chain: [URL]
		if chainFromRoot, let root = reachableRoot(containing: url), !isAddedFolderOrRemoteRoot(root) {
			chain = pathChain(from: root, to: url)
		} else {
			chain = [url]
		}
		if chain.count > 1, chain[0].path == rootURL.path {
			chain.removeFirst()
		}
		if chain.count > 1, let hostNavigationController {
			pushChain(chain, displayName: displayName, on: hostNavigationController)
		} else {
			pendingNavigation = PendingNavigation(url: url, displayName: displayName)
		}
	}

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

	@ViewBuilder
	private var emptyStateContent: some View {
		if viewModel.loadErrorMessage != nil {
			EmptyStateView(icon: "lock", title: "No Access")
		} else {
			EmptyStateView(icon: "folder", title: "This Folder Is Empty")
		}
	}

	@ViewBuilder
	private var searchResultsContent: some View {
		if isSearchLoading {
			ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if searchResults.isEmpty {
			EmptyStateView(icon: "magnifyingglass", title: "No Results")
		} else {
			List { ForEach(searchResults) { row(for: $0) } }
				.listStyle(.plain)
		}
	}

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
			RoundedRectangle(cornerRadius: cornerRad.component, style: .continuous)
				.fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
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
	private var bottomBar: some View {
		if viewModel.isSelecting {
			selectionActionBar
		}
	}

	private var searchBar: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)
			TextField("Search", text: $searchQuery)
				.focused($isSearchFieldFocused)
				.autocapitalization(.none)
				.disableAutocorrection(true)
			if isSearchFieldFocused && !searchQuery.isEmpty {
				Button {
					clearSearch()
				} label: {
					Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
		}
		.modifier(TextFieldBackground(shape: Capsule()))
		.contentShape(Capsule())
		.onTapGesture { isSearchFieldFocused = true }
		.modifier(OverlayBackground())
	}

	private func clearSearch() {
		searchQuery = ""
		isSearchFieldFocused = false
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
			Button(viewModel.selection.count == viewModel.nodes.count ? "Deselect All" : "Select All") {
				if viewModel.selection.count == viewModel.nodes.count {
					viewModel.selection.removeAll()
				} else {
					viewModel.selection = Set(viewModel.nodes.map(\.url))
				}
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

	private var selectionActionBar: some View {
		HStack {
			Spacer()
			selectionButton(icon: "doc.on.doc", label: "Copy") {
				clipboard.set(Array(viewModel.selection), operation: .copy)
				viewModel.endSelecting()
			}
			Spacer()
			selectionButton(icon: "scissors", label: "Cut") {
				clipboard.set(Array(viewModel.selection), operation: .move)
				viewModel.endSelecting()
			}
			Spacer()
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
				Image(systemName: "doc.zipper")
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(Color.accentColor)
					.padding()
					.background(Color.accentColor.opacity(0.2), in: Circle())
			}
			.accessibilityLabel("Compress")
			Spacer()
			selectionButton(icon: "square.and.arrow.up", label: "Share") {
				presentMultiShareSheet(for: Array(viewModel.selection))
			}
			Spacer()
			selectionButton(icon: "trash", label: "Delete", color: .red) {
				pendingDeleteURLs = Array(viewModel.selection)
				showingDeleteConfirmation = true
			}
			Spacer()
		}
		.disabled(viewModel.selection.isEmpty)
		.modifier(OverlayBackground())
	}

	private func selectionButton(icon: String, label: String, color: Color = .accentColor, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: icon)
				.font(.system(size: 18, weight: .semibold))
		}
		.buttonStyle(TranslucentButtonStyle(color: color, shape: Circle(), useFullWidth: false))
		.accessibilityLabel(label)
	}

	private var rootActionsMenu: some View {
		Menu {
			Button {
				viewModel.isSelecting = true
			} label: {
				Label("Select", systemImage: "checkmark.circle")
			}
			Button {
				showingPathNavigator = true
			} label: {
				Label("Go to Folder", systemImage: "arrow.forward.to.line")
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

	private var locationsMenu: some View {
		Menu {
			Button { showingDisks = true } label: { Label("Disks", systemImage: "externaldrive") }
			Button { showingBookmarks = true } label: { Label("Bookmarks", systemImage: "bookmark") }
			Button { showingRecents = true } label: { Label("Recents", systemImage: "clock") }
			Button { showingPathNavigator = true } label: { Label("Go to Folder", systemImage: "arrow.forward.to.line") }
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
