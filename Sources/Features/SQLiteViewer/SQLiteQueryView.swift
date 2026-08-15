import PartyUI
import SwiftUI

/// Sheet content behind `SQLiteViewerView`'s "Run SQL" button — a free-form query editor
/// whose results render through the same `SQLiteResultGrid` used by `SQLiteTableView`.
///
/// Presented modally via `.sheet`, so — unlike the pushed viewers in this feature — it
/// owns its own `NavigationView` to get a title bar and a "Done" button.
struct SQLiteQueryView: View {
	let url: URL

	@Environment(\.presentationMode) private var presentationMode

	@State private var sqlText: String = ""
	@State private var columnNames: [String] = []
	@State private var rows: [[String?]] = []
	@State private var isRunning = false
	@State private var errorMessage: String?

	private var canRun: Bool {
		!sqlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
	}

	var body: some View {
		NavigationView {
			VStack(spacing: 0) {
				TextEditor(text: $sqlText)
					.font(.system(.body, design: .monospaced))
					.frame(height: 140)
					.padding(4)
					.overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator)))
					.padding()

				Button(action: runQuery) {
					ButtonLabel(text: "Run", icon: isRunning ? "showMeProgressPlease" : "play.fill")
				}
				.buttonStyle(FancyButtonStyle())
				.disabled(!canRun)
				.padding(.horizontal)
				.padding(.bottom)

				Divider()

				if columnNames.isEmpty {
					EmptyStateView(icon: "terminal", title: "No Results", message: "Run a query to see its results here.")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else {
					SQLiteResultGrid(columnNames: columnNames, rows: rows)
				}
			}
			.navigationTitle("Run SQL")
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button("Done") {
						presentationMode.wrappedValue.dismiss()
					}
				}
			}
			.errorAlert($errorMessage)
		}
		.navigationViewStyle(.stack)
	}

	/// Opens a throwaway `SQLiteReader` off the main thread to run the query — its
	/// C-API calls are blocking, so this never happens directly on the view body.
	private func runQuery() {
		let dbURL = url
		let sql = sqlText
		isRunning = true

		Task {
			let outcome: Result<SQLiteReader.QueryResult, SQLiteTaskError> = await Task.detached(priority: .userInitiated) {
				do {
					let reader = try SQLiteReader(url: dbURL)
					return .success(try reader.run(sql))
				} catch {
					return .failure(SQLiteTaskError(message: error.localizedDescription))
				}
			}.value

			isRunning = false
			switch outcome {
			case .success(let result):
				columnNames = result.columnNames
				rows = result.rows
			case .failure(let error):
				errorMessage = error.message
			}
		}
	}
}
