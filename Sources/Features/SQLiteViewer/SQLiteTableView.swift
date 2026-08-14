import SwiftUI

/// Pages through a single table's rows using `SQLiteReader`, loading `pageSize` rows at a
/// time as the user scrolls — fetching every row upfront would be wasteful (and slow) for
/// large tables. Pushed from `SQLiteViewerView` when a table row is tapped.
struct SQLiteTableView: View {
	let url: URL
	let table: String

	private let pageSize = 200

	@State private var columnNames: [String] = []
	@State private var loadedRows: [[String?]] = []
	@State private var totalRowCount = 0
	@State private var isLoadingInitialPage = true
	@State private var isLoadingNextPage = false
	@State private var hasMoreRows = true
	@State private var errorMessage: String?

	var body: some View {
		Group {
			if isLoadingInitialPage {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if columnNames.isEmpty {
				EmptyStateView(icon: "tablecells", title: "No Columns", message: "This table could not be read.")
			} else {
				VStack(spacing: 0) {
					SQLiteResultGrid(columnNames: columnNames, rows: loadedRows, onLastCellAppear: loadNextPageIfNeeded)
					if isLoadingNextPage {
						ProgressView()
							.padding()
					}
				}
			}
		}
		.navigationTitle(table)
		.task {
			await loadInitialPage()
		}
		.errorAlert($errorMessage)
	}

	// MARK: - Paging

	private func loadInitialPage() async {
		let dbURL = url
		let tableName = table
		let limit = pageSize
		let outcome: Result<(Int, SQLiteReader.QueryResult), String> = await Task.detached(priority: .userInitiated) {
			do {
				let reader = try SQLiteReader(url: dbURL)
				let count = try reader.rowCount(table: tableName)
				let page = try reader.rows(table: tableName, offset: 0, limit: limit)
				return .success((count, page))
			} catch {
				return .failure(error.localizedDescription)
			}
		}.value

		isLoadingInitialPage = false
		switch outcome {
		case .success(let (count, page)):
			totalRowCount = count
			columnNames = page.columnNames
			loadedRows = page.rows
			hasMoreRows = loadedRows.count < count
		case .failure(let message):
			errorMessage = message
		}
	}

	/// Fires from the grid's last-cell `.onAppear` — the standard SwiftUI infinite-scroll
	/// trigger. Guarded against overlapping loads and running past the known row count.
	private func loadNextPageIfNeeded() {
		guard !isLoadingNextPage, hasMoreRows, !isLoadingInitialPage else { return }
		isLoadingNextPage = true

		let dbURL = url
		let tableName = table
		let offset = loadedRows.count
		let limit = pageSize

		Task {
			let outcome: Result<SQLiteReader.QueryResult, String> = await Task.detached(priority: .userInitiated) {
				do {
					let reader = try SQLiteReader(url: dbURL)
					return .success(try reader.rows(table: tableName, offset: offset, limit: limit))
				} catch {
					return .failure(error.localizedDescription)
				}
			}.value

			isLoadingNextPage = false
			switch outcome {
			case .success(let page):
				loadedRows.append(contentsOf: page.rows)
				hasMoreRows = !page.rows.isEmpty && loadedRows.count < totalRowCount
			case .failure(let message):
				errorMessage = message
			}
		}
	}
}

/// Shared horizontally- and vertically-scrollable "spreadsheet" rendering for a
/// `SQLiteReader.QueryResult` — used by both this table pager and `SQLiteQueryView`'s
/// free-form query results so cell/column styling stays identical.
struct SQLiteResultGrid: View {
	let columnNames: [String]
	let rows: [[String?]]
	/// Called when the last column of the last row appears on screen — the trigger point
	/// for loading another page. Leave `nil` for one-shot results (a run query).
	var onLastCellAppear: (() -> Void)?

	private static let columnWidth: CGFloat = 140

	private var gridColumns: [GridItem] {
		Array(repeating: GridItem(.fixed(Self.columnWidth), spacing: 1, alignment: .leading), count: max(columnNames.count, 1))
	}

	var body: some View {
		ScrollView([.horizontal, .vertical]) {
			LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 1) {
				ForEach(Array(columnNames.enumerated()), id: \.offset) { _, name in
					cell(isHeader: true) {
						Text(name).bold()
					}
				}
				ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
					ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, value in
						cell(isHeader: false) {
							valueText(value)
						}
						.onAppear {
							if rowIndex == rows.count - 1 && columnIndex == row.count - 1 {
								onLastCellAppear?()
							}
						}
					}
				}
			}
			.padding(.trailing)
		}
	}

	@ViewBuilder
	private func valueText(_ value: String?) -> some View {
		if let value = value {
			Text(value)
		} else {
			Text("NULL")
				.italic()
				.foregroundColor(.secondary)
		}
	}

	private func cell<Content: View>(isHeader: Bool, @ViewBuilder content: () -> Content) -> some View {
		content()
			.font(isHeader ? .subheadline : .body)
			.lineLimit(2)
			.padding(6)
			.frame(width: Self.columnWidth, alignment: .leading)
			.background(isHeader ? Color(.secondarySystemBackground) : Color(.systemBackground))
	}
}
