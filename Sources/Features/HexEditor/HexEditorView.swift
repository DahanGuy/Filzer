import SwiftUI
import PartyUI

/// Raw byte-level file viewer/editor pushed from `FileViewerRoute`. Renders
/// `HexFormatting.rows(for:)` in a `List` with per-byte tap targets for single-byte
/// overwrites, plus Go To / Find toolbar actions.
///
/// Note: SwiftUI's `.alert(isPresented:actions:)` silently drops `TextField`s from its
/// `actions` closure at iOS 15 (that only works from iOS 16 onward), so offset/byte
/// prompts use PartyUI's `Alertinator.shared.prompt`, which is backed by
/// `UIAlertController` and works correctly at iOS 15.
struct HexEditorView: View {
	let url: URL

	/// Above this size, editing is disabled but the file is still rendered read-only.
	private static let largeFileThreshold = 32_000_000

	@State private var editableData = Data()
	@State private var rows: [HexFormatting.Row] = []
	@State private var isLoading = true
	@State private var isReadOnly = false
	@State private var isDirty = false
	@State private var errorMessage: String?
	@State private var scrollProxy: ScrollViewProxy?

	@State private var isFindBarVisible = false
	@State private var findQuery = ""
	@State private var lastSearchedQuery = ""
	@State private var searchMatches: [Int] = []
	@State private var searchPatternLength = 0
	@State private var currentMatchIndex = -1

	var body: some View {
		Group {
			if isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if rows.isEmpty {
				EmptyStateView(icon: "doc", title: "Empty File", message: "This file has no bytes to display.")
			} else {
				content
			}
		}
		.navigationTitle(url.lastPathComponent)
		.toolbar { toolbarContent }
		.errorAlert($errorMessage)
		.task { await load() }
	}

	// MARK: - Layout

	private var content: some View {
		VStack(spacing: 0) {
			if isReadOnly {
				CompactAlert(title: "Read-Only", icon: "lock.fill", text: "This file is over 32 MB, so byte editing is disabled to keep the app responsive. You can still browse its contents.", color: .orange)
					.padding(8)
			}
			if isFindBarVisible {
				findBar
				Divider()
			}
			ScrollViewReader { proxy in
				List(rows) { row in
					HexRowView(row: row, isReadOnly: isReadOnly, highlightRange: currentHighlightRange, onTapByte: beginByteEdit)
						.listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
				}
				.listStyle(.plain)
				.onAppear { scrollProxy = proxy }
			}
		}
	}

	private var findBar: some View {
		HStack(spacing: 12) {
			TextField("Find ASCII text or hex bytes", text: $findQuery, onCommit: search)
				.textFieldStyle(.roundedBorder)
				.autocapitalization(.none)
				.disableAutocorrection(true)
			Text(matchCountLabel)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.frame(minWidth: 56)
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
		guard !findQuery.isEmpty, findQuery == lastSearchedQuery else { return "" }
		guard !searchMatches.isEmpty else { return "No matches" }
		return "\(currentMatchIndex + 1)/\(searchMatches.count)"
	}

	@ToolbarContentBuilder
	private var toolbarContent: some ToolbarContent {
		ToolbarItem(placement: .navigationBarTrailing) {
			HStack(spacing: 16) {
				Button("Go To") { presentGoTo() }
				Button("Find") { isFindBarVisible.toggle() }
				if !isReadOnly {
					Button("Save") { save() }
						.disabled(!isDirty)
				}
			}
		}
	}

	private var currentHighlightRange: Range<Int>? {
		guard currentMatchIndex >= 0, currentMatchIndex < searchMatches.count else { return nil }
		let start = searchMatches[currentMatchIndex]
		return start..<(start + max(searchPatternLength, 1))
	}

	// MARK: - Loading / saving

	private func load() async {
		do {
			let data = try await FileSystem.current.readFile(at: url)
			// Row construction is O(fileSize) and can involve millions of rows for
			// large files — compute it off the main actor so the load doesn't hitch.
			let computedRows = await Task.detached(priority: .userInitiated) {
				HexFormatting.rows(for: data)
			}.value
			editableData = data
			isReadOnly = data.count > Self.largeFileThreshold
			rows = computedRows
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}

	private func save() {
		Task {
			do {
				try await FileSystem.current.writeFile(at: url, data: editableData)
				isDirty = false
			} catch {
				errorMessage = error.localizedDescription
			}
		}
	}

	// MARK: - Go To

	private func presentGoTo() {
		Alertinator.shared.prompt(title: "Go To Offset", placeholder: "0x1A2B or decimal") { text in
			guard let text = text, let offset = Self.parseOffset(text) else { return }
			scrollToRow(containing: offset)
		}
	}

	private static func parseOffset(_ text: String) -> Int? {
		let trimmed = text.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return nil }
		if trimmed.lowercased().hasPrefix("0x") {
			return Int(trimmed.dropFirst(2), radix: 16)
		}
		if let decimal = Int(trimmed) {
			return decimal
		}
		return Int(trimmed, radix: 16)
	}

	private func scrollToRow(containing offset: Int) {
		guard !rows.isEmpty, !editableData.isEmpty else { return }
		let clamped = max(0, min(offset, editableData.count - 1))
		let rowOffset = (clamped / HexFormatting.bytesPerRow) * HexFormatting.bytesPerRow
		withAnimation {
			scrollProxy?.scrollTo(rowOffset, anchor: .center)
		}
	}

	// MARK: - Find

	/// Runs (or re-runs) the byte search for the current query and jumps to the first
	/// match. Next/Prev reuse the cached result instead of re-searching every tap.
	private func search() {
		guard !findQuery.isEmpty else {
			searchMatches = []
			searchPatternLength = 0
			currentMatchIndex = -1
			lastSearchedQuery = ""
			return
		}
		let pattern = Self.searchPattern(for: findQuery)
		searchPatternLength = pattern.count
		searchMatches = Self.findOccurrences(of: pattern, in: editableData)
		currentMatchIndex = searchMatches.isEmpty ? -1 : 0
		lastSearchedQuery = findQuery
		if let first = searchMatches.first {
			scrollToRow(containing: first)
		}
	}

	/// Interprets the find query as space-separated hex bytes first (e.g. "DE AD BE
	/// EF"); falls back to raw ASCII/UTF-8 bytes so plain-text searches also work.
	private static func searchPattern(for query: String) -> [UInt8] {
		if let hexBytes = HexFormatting.bytes(fromHexString: query), !hexBytes.isEmpty {
			return hexBytes
		}
		return Array(query.utf8)
	}

	private static func findOccurrences(of pattern: [UInt8], in data: Data) -> [Int] {
		guard !pattern.isEmpty, pattern.count <= data.count else { return [] }
		let bytes = [UInt8](data)
		var matches: [Int] = []
		let lastStart = bytes.count - pattern.count
		var index = 0
		while index <= lastStart {
			if Array(bytes[index..<(index + pattern.count)]) == pattern {
				matches.append(index)
			}
			index += 1
		}
		return matches
	}

	private func findNext() {
		guard findQuery == lastSearchedQuery else { search(); return }
		guard !searchMatches.isEmpty else { return }
		currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
		scrollToRow(containing: searchMatches[currentMatchIndex])
	}

	private func findPrevious() {
		guard findQuery == lastSearchedQuery else { search(); return }
		guard !searchMatches.isEmpty else { return }
		currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
		scrollToRow(containing: searchMatches[currentMatchIndex])
	}

	// MARK: - Byte editing

	private func beginByteEdit(offset: Int, byte: UInt8) {
		guard !isReadOnly else { return }
		let title = String(format: "Edit Byte at 0x%08X", offset)
		Alertinator.shared.prompt(title: title, placeholder: "00-FF", text: String(format: "%02X", byte)) { text in
			guard let text = text else { return }
			commitByteEdit(offset: offset, hexText: text)
		}
	}

	private func commitByteEdit(offset: Int, hexText: String) {
		let hex = hexText.trimmingCharacters(in: .whitespaces)
		guard hex.count <= 2, let value = UInt8(hex, radix: 16) else {
			errorMessage = "\"\(hexText)\" isn't a valid hex byte (00-FF)."
			return
		}
		let index = editableData.startIndex + offset
		guard index >= editableData.startIndex, index < editableData.endIndex else { return }
		editableData[index] = value
		replaceRow(containing: offset)
		isDirty = true
	}

	/// Rebuilds only the single affected row (rather than the whole `rows` array,
	/// which can hold millions of entries for large files) after a byte edit.
	private func replaceRow(containing offset: Int) {
		let rowOffset = (offset / HexFormatting.bytesPerRow) * HexFormatting.bytesPerRow
		guard let rowIndex = rows.firstIndex(where: { $0.offset == rowOffset }) else { return }
		let start = editableData.startIndex + rowOffset
		let end = min(start + HexFormatting.bytesPerRow, editableData.endIndex)
		rows[rowIndex] = HexFormatting.Row(offset: rowOffset, bytes: Array(editableData[start..<end]))
	}
}

// MARK: - Row rendering

/// One offset/hex/ASCII row. Hex bytes render as individually tappable cells (instead
/// of `row.hexString`'s single concatenated string) so a tap can target one byte for
/// the single-byte-overwrite edit flow.
private struct HexRowView: View {
	let row: HexFormatting.Row
	let isReadOnly: Bool
	let highlightRange: Range<Int>?
	let onTapByte: (Int, UInt8) -> Void

	private static let cellWidth: CGFloat = 20

	var body: some View {
		HStack(spacing: 0) {
			Text(row.offsetString)
				.font(.system(.footnote, design: .monospaced))
				.foregroundStyle(.secondary)
				.frame(width: 74, alignment: .leading)
			HStack(spacing: 2) {
				ForEach(Array(row.bytes.enumerated()), id: \.offset) { index, byte in
					byteCell(index: index, byte: byte)
				}
				ForEach(row.bytes.count..<HexFormatting.bytesPerRow, id: \.self) { _ in
					Text("")
						.frame(width: Self.cellWidth)
				}
			}
			Text(row.asciiString)
				.font(.system(.footnote, design: .monospaced))
				.foregroundStyle(.secondary)
				.padding(.leading, 8)
		}
	}

	@ViewBuilder
	private func byteCell(index: Int, byte: UInt8) -> some View {
		let absoluteOffset = row.offset + index
		let isHighlighted = highlightRange?.contains(absoluteOffset) ?? false
		let label = Text(String(format: "%02X", byte))
			.font(.system(.footnote, design: .monospaced))
			.frame(width: Self.cellWidth)
			.background(isHighlighted ? Color.yellow.opacity(0.6) : Color.clear)

		if isReadOnly {
			label
		} else {
			Button(action: { onTapByte(absoluteOffset, byte) }) {
				label
			}
			.buttonStyle(.plain)
		}
	}
}
