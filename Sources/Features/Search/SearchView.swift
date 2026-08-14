import SwiftUI

/// A scoped search — pick 'Filzer' (Documents), 'Library', or one of the user's
/// bookmarks, then search that subtree by name. Debounced so fast typing doesn't spawn
/// a search per keystroke.
struct SearchView: View {
	@EnvironmentObject private var bookmarks: BookmarksStore
	@EnvironmentObject private var settings: SettingsStore

	@State private var query = ""
	@State private var selectedScopeID = SearchScope.documentsID
	@State private var results: [FileNode] = []
	@State private var isSearching = false
	@State private var hasSearched = false
	@State private var searchTask: Task<Void, Never>?
	@State private var errorMessage: String?

	var body: some View {
		NavigationView {
			VStack(spacing: 0) {
				Picker("Scope", selection: $selectedScopeID) {
					ForEach(scopes) { scope in
						Text(scope.title).tag(scope.id)
					}
				}
				.pickerStyle(.segmented)
				.padding(.horizontal)
				.padding(.top, 8)

				resultsContent
			}
			.navigationTitle("Search")
			.searchable(text: $query, prompt: "Search files and folders")
			.onChange(of: query) { _ in scheduleSearch() }
			.onChange(of: selectedScopeID) { _ in scheduleSearch() }
			.errorAlert($errorMessage)
		}
		.navigationViewStyle(.stack)
	}

	@ViewBuilder
	private var resultsContent: some View {
		if query.isEmpty {
			EmptyStateView(
				icon: "magnifyingglass",
				title: "Search",
				message: "Enter a name to search within the selected scope."
			)
		} else if isSearching && !hasSearched {
			ProgressView()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if hasSearched && results.isEmpty {
			EmptyStateView(
				icon: "magnifyingglass",
				title: "No Results",
				message: "No files or folders match \u{201C}\(query)\u{201D}."
			)
		} else {
			List(results) { node in
				NavigationLink(destination: destination(for: node)) {
					FileRow(node: node)
				}
			}
			.listStyle(.plain)
		}
	}

	/// Every searchable location: the two fixed sandbox roots, then one entry per
	/// bookmark (which may itself be in-sandbox or an externally-scoped folder).
	private var scopes: [SearchScope] {
		var result = [
			SearchScope(id: SearchScope.documentsID, title: "Filzer", url: SandboxRoots.documents, isSecurityScoped: false),
			SearchScope(id: SearchScope.libraryID, title: "Library", url: SandboxRoots.library, isSecurityScoped: false),
		]
		result.append(contentsOf: bookmarks.entries.map { entry in
			SearchScope(
				id: entry.id.uuidString,
				title: entry.displayName,
				url: bookmarks.resolvedURL(for: entry),
				isSecurityScoped: entry.securityScopedBookmarkData != nil
			)
		})
		return result
	}

	private var currentScope: SearchScope? {
		scopes.first { $0.id == selectedScopeID }
	}

	@ViewBuilder
	private func destination(for node: FileNode) -> some View {
		if node.isDirectory {
			FileBrowserView(rootURL: node.url)
		} else {
			FileViewerRoute(node: node)
		}
	}

	private func scheduleSearch() {
		searchTask?.cancel()

		guard !query.isEmpty, let scope = currentScope else {
			results = []
			hasSearched = false
			isSearching = false
			return
		}

		let pendingQuery = query
		isSearching = true
		hasSearched = false
		searchTask = Task {
			try? await Task.sleep(nanoseconds: 300_000_000)
			guard !Task.isCancelled else { return }
			await performSearch(for: pendingQuery, in: scope)
		}
	}

	/// Runs the actual search, starting security-scoped access around it only when the
	/// scope needs it. `withSecurityScopedAccess` is synchronous, so the start/stop
	/// calls are made directly here rather than through that helper.
	private func performSearch(for searchQuery: String, in scope: SearchScope) async {
		let didStartAccessing = scope.isSecurityScoped ? scope.url.startAccessingSecurityScopedResource() : false
		defer {
			if didStartAccessing { scope.url.stopAccessingSecurityScopedResource() }
		}

		do {
			let found = try await FileSystem.current.search(root: scope.url, query: searchQuery, includeHidden: settings.showHiddenFiles)
			guard !Task.isCancelled else { return }
			results = found
			isSearching = false
			hasSearched = true
		} catch {
			guard !Task.isCancelled else { return }
			results = []
			isSearching = false
			hasSearched = true
			errorMessage = error.localizedDescription
		}
	}
}

/// One selectable search root: a fixed sandbox location or a resolved bookmark.
private struct SearchScope: Identifiable, Hashable {
	static let documentsID = "documents"
	static let libraryID = "library"

	let id: String
	let title: String
	let url: URL
	let isSecurityScoped: Bool
}
