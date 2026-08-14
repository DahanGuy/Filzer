import SwiftUI
import UIKit
import PartyUI

/// Plain-text file editor pushed from `FileViewerRoute`. Wraps `UITextView` directly
/// instead of SwiftUI's `TextEditor` because Find/Next/Prev needs `selectedRange` and
/// `scrollRangeToVisible`, neither of which `TextEditor` exposes at iOS 15.
struct TextEditorView: View {
	let url: URL

	@State private var text = ""
	@State private var isDirty = false
	@State private var isLoading = true
	@State private var loadFailed = false
	@State private var errorMessage: String?

	@State private var isFindBarVisible = false
	@State private var findQuery = ""
	@State private var textView: UITextView?

	var body: some View {
		Group {
			if isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if loadFailed {
				EmptyStateView(icon: "doc.text.magnifyingglass", title: "Can't Display This File", message: "The file couldn't be decoded as text.")
			} else {
				editor
			}
		}
		.navigationTitle(url.lastPathComponent)
		.toolbar { toolbarContent }
		.errorAlert($errorMessage)
		.task { await load() }
	}

	// MARK: - Layout

	private var editor: some View {
		VStack(spacing: 0) {
			if isFindBarVisible {
				findBar
				Divider()
			}
			TextViewRepresentable(text: $text, isDirty: $isDirty, textView: $textView)
		}
	}

	private var findBar: some View {
		HStack(spacing: 12) {
			TextField("Find", text: $findQuery, onCommit: findNext)
				.textFieldStyle(.roundedBorder)
				.autocapitalization(.none)
				.disableAutocorrection(true)
			Text(matchCountLabel)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.frame(minWidth: 40)
			Button(action: findPrevious) {
				Image(systemName: "chevron.up")
			}
			.disabled(findQuery.isEmpty)
			Button(action: findNext) {
				Image(systemName: "chevron.down")
			}
			.disabled(findQuery.isEmpty)
		}
		.padding(8)
	}

	private var matchCountLabel: String {
		guard !findQuery.isEmpty else { return "" }
		let count = Self.countMatches(of: findQuery, in: text)
		return count == 1 ? "1 match" : "\(count) matches"
	}

	@ToolbarContentBuilder
	private var toolbarContent: some ToolbarContent {
		ToolbarItem(placement: .navigationBarTrailing) {
			HStack(spacing: 16) {
				if isDirty {
					InfoBadge(text: "Unsaved Changes", icon: "exclamationmark.circle", color: Color(.systemOrange).opacity(0.2))
				}
				Button("Find") { isFindBarVisible.toggle() }
				Button("Save") { save() }
					.disabled(!isDirty)
			}
		}
	}

	// MARK: - Loading / saving

	private func load() async {
		do {
			let data = try await FileSystem.current.readFile(at: url)
			if let decoded = String(data: data, encoding: .utf8) {
				text = decoded
			} else if let decoded = String(data: data, encoding: .isoLatin1) {
				text = decoded
			} else {
				loadFailed = true
			}
		} catch {
			errorMessage = error.localizedDescription
			loadFailed = true
		}
		isLoading = false
	}

	private func save() {
		guard let data = text.data(using: .utf8) else {
			errorMessage = "Couldn't encode this text as UTF-8."
			return
		}
		Task {
			do {
				try await FileSystem.current.writeFile(at: url, data: data)
				isDirty = false
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}

	// MARK: - Find

	/// Counts case-insensitive, non-overlapping occurrences of `query` in `text` for
	/// the find bar's match-count label.
	private static func countMatches(of query: String, in text: String) -> Int {
		let haystack = text as NSString
		guard haystack.length > 0 else { return 0 }
		var count = 0
		var searchRange = NSRange(location: 0, length: haystack.length)
		while searchRange.length > 0 {
			let found = haystack.range(of: query, options: .caseInsensitive, range: searchRange)
			if found.location == NSNotFound { break }
			count += 1
			let nextLocation = found.location + found.length
			guard nextLocation < haystack.length else { break }
			searchRange = NSRange(location: nextLocation, length: haystack.length - nextLocation)
		}
		return count
	}

	private func findNext() {
		performFind(forward: true)
	}

	private func findPrevious() {
		performFind(forward: false)
	}

	/// Searches from the current selection, wrapping around the ends of the document,
	/// then moves the caret and scrolls the match into view.
	private func performFind(forward: Bool) {
		guard !findQuery.isEmpty, let textView = textView else { return }
		let haystack = text as NSString
		guard haystack.length > 0 else { return }

		let selection = textView.selectedRange
		var found: NSRange

		if forward {
			let start = min(selection.location + selection.length, haystack.length)
			found = haystack.range(of: findQuery, options: .caseInsensitive, range: NSRange(location: start, length: haystack.length - start))
			if found.location == NSNotFound {
				found = haystack.range(of: findQuery, options: .caseInsensitive, range: NSRange(location: 0, length: haystack.length))
			}
		} else {
			let end = min(selection.location, haystack.length)
			found = haystack.range(of: findQuery, options: [.caseInsensitive, .backwards], range: NSRange(location: 0, length: end))
			if found.location == NSNotFound {
				found = haystack.range(of: findQuery, options: [.caseInsensitive, .backwards], range: NSRange(location: 0, length: haystack.length))
			}
		}

		guard found.location != NSNotFound else { return }
		textView.selectedRange = found
		textView.scrollRangeToVisible(found)
	}
}

// MARK: - UITextView bridge

/// Bridges `UITextView` into SwiftUI. A plain SwiftUI `TextEditor` can't drive
/// programmatic selection/scrolling, so Find/Next/Prev call directly into the
/// underlying `UITextView` captured here.
private struct TextViewRepresentable: UIViewRepresentable {
	@Binding var text: String
	@Binding var isDirty: Bool
	@Binding var textView: UITextView?

	func makeUIView(context: Context) -> UITextView {
		let view = UITextView()
		view.font = .preferredFont(forTextStyle: .body)
		view.isEditable = true
		view.autocorrectionType = .no
		view.autocapitalizationType = .none
		view.delegate = context.coordinator
		view.text = text
		DispatchQueue.main.async { textView = view }
		return view
	}

	func updateUIView(_ uiView: UITextView, context: Context) {
		if uiView.text != text {
			uiView.text = text
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	final class Coordinator: NSObject, UITextViewDelegate {
		let parent: TextViewRepresentable

		init(_ parent: TextViewRepresentable) {
			self.parent = parent
		}

		func textViewDidChange(_ textView: UITextView) {
			parent.text = textView.text
			parent.isDirty = true
		}
	}
}
