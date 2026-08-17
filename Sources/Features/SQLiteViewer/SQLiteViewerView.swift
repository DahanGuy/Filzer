import PartyUI
import SwiftUI

struct SQLiteTaskError: Error {
	let message: String
}

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
					ButtonLabel(text: "Run SQL", icon: "terminal")
				}
				.buttonStyle(TranslucentButtonStyle())
			}

			Section(header: HeaderLabel(text: "Tables", icon: "tablecells")) {
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
							NavigationLabel(text: name, icon: "tablecells")
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
