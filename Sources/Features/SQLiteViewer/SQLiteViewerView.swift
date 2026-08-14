import SwiftUI

/// `Result`'s failure case must conform to `Error`; a plain `String` doesn't. This is
/// the minimal wrapper shared by every throwaway-`SQLiteReader` call site in this
/// feature (`SQLiteViewerView`, `SQLiteTableView`, `SQLiteQueryView`).
struct SQLiteTaskError: Error {
	let message: String
}

/// Landing screen for a `.sqlite` file. Lists the database's tables (tap one to page
/// through its rows in `SQLiteTableView`) and exposes a persistent "Run SQL" entry point
/// for free-form queries that aren't tied to any single table.
///
/// Pushed inside an existing `NavigationView` via `FileViewerRoute` — this view does
/// **not** create its own `NavigationView`.
struct SQLiteViewerView: View {
	let url: URL

	@State private var tableNames: [String] = []
	@State private var isLoadingTables = true
	@State private var errorMessage: String?
	@State private var isShowingQuerySheet = false

	var body: some View {
		List {
			Section {
				Button {
					isShowingQuerySheet = true
				} label: {
					Label("Run SQL", systemImage: "terminal")
				}
			}

			Section(header: Text("Tables")) {
				if isLoadingTables {
					HStack {
						Spacer()
						ProgressView()
						Spacer()
					}
				} else if tableNames.isEmpty {
					Text("No tables found")
						.foregroundColor(.secondary)
				} else {
					ForEach(tableNames, id: \.self) { name in
						NavigationLink(destination: SQLiteTableView(url: url, table: name)) {
							Label(name, systemImage: "tablecells")
						}
					}
				}
			}
		}
		.navigationTitle(url.lastPathComponent)
		.task {
			await loadTableNames()
		}
		.sheet(isPresented: $isShowingQuerySheet) {
			SQLiteQueryView(url: url)
		}
		.errorAlert($errorMessage)
	}

	/// Opens a throwaway `SQLiteReader` off the main thread to list tables — the reader's
	/// C-API calls are blocking, so this never happens directly on the view body.
	private func loadTableNames() async {
		let dbURL = url
		let outcome: Result<[String], SQLiteTaskError> = await Task.detached(priority: .userInitiated) {
			do {
				let reader = try SQLiteReader(url: dbURL)
				return .success(try reader.tableNames())
			} catch {
				return .failure(SQLiteTaskError(message: error.localizedDescription))
			}
		}.value

		isLoadingTables = false
		switch outcome {
		case .success(let names):
			tableNames = names
		case .failure(let error):
			errorMessage = error.message
		}
	}
}
