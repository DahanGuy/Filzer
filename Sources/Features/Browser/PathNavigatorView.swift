import PartyUI
import SwiftUI

/// "Go to Folder" — typing/pasting an absolute path directly, with live autosuggest
/// for the folder name currently being typed. A dedicated sheet, deliberately
/// separate from search: the previous design had one field try to be both a search
/// box and a path box via a mode-toggle button, which meant every focus/keyboard/
/// clear-button interaction had to be hand-rolled and re-hand-rolled to work
/// correctly. This has its own small, independent state instead.
struct PathNavigatorView: View {
	let currentPath: String
	let onNavigate: (URL, String?) -> Void

	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var settings: SettingsStore
	@FocusState private var isFocused: Bool
	@State private var path: String
	@State private var suggestions: [String] = []
	@State private var suggestionsTask: Task<Void, Never>?

	init(currentPath: String, onNavigate: @escaping (URL, String?) -> Void) {
		self.currentPath = currentPath
		self.onNavigate = onNavigate
		_path = State(initialValue: currentPath)
	}

	var body: some View {
		List {
			Section(header: HeaderLabel(text: "Location", icon: "folder")) {
				TextField("/path/to/folder", text: $path)
					.focused($isFocused)
					.autocapitalization(.none)
					.disableAutocorrection(true)
					.onSubmit(navigate)
			}

			if !suggestions.isEmpty {
				Section(header: HeaderLabel(text: "Suggestions", icon: "text.magnifyingglass")) {
					ForEach(suggestions, id: \.self) { suggestion in
						Button {
							path = suggestion
							navigate()
						} label: {
							NavigationLabel(
								text: (suggestion as NSString).lastPathComponent,
								icon: "folder.fill",
								footer: suggestion,
								showChevron: false
							)
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
		.navigationTitle("Go to Folder")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) {
				Button("Cancel") { dismiss() }
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				Button("Go", action: navigate)
					.disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
			}
		}
		.onAppear {
			isFocused = true
			scheduleSuggestions()
		}
		.onChange(of: path) { _ in scheduleSuggestions() }
	}

	private func navigate() {
		let trimmed = path.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return }
		onNavigate(URL(fileURLWithPath: trimmed), nil)
		dismiss()
	}

	/// Lists the parent of whatever path is currently typed and keeps folders whose
	/// name starts with the partial last segment — an inaccessible parent silently
	/// yields no suggestions rather than surfacing an error popup.
	private func scheduleSuggestions() {
		suggestionsTask?.cancel()
		let typed = path
		let includeHidden = settings.showHiddenFiles
		suggestionsTask = Task {
			try? await Task.sleep(nanoseconds: 200_000_000)
			guard !Task.isCancelled else { return }
			let parentPath = (typed as NSString).deletingLastPathComponent
			let partial = (typed as NSString).lastPathComponent
			let parentURL = URL(fileURLWithPath: parentPath.isEmpty ? "/" : parentPath)
			guard let children = try? await FileSystem.current.listDirectory(at: parentURL, includeHidden: includeHidden) else {
				guard !Task.isCancelled else { return }
				suggestions = []
				return
			}
			guard !Task.isCancelled else { return }
			let matches = children
				.filter { $0.isDirectory && (partial.isEmpty || $0.name.lowercased().hasPrefix(partial.lowercased())) }
				.map { parentURL.appendingPathComponent($0.name).path }
				.sorted()
			suggestions = Array(matches.prefix(30))
		}
	}
}
