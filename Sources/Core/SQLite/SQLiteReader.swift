import Foundation
import SQLite3

/// A minimal, read-oriented wrapper around the system `libsqlite3` C API — just enough
/// to power Filzer's SQLite viewer (list tables, page through rows, run a free-form
/// query). Always opens with `SQLITE_OPEN_READONLY`: this viewer never mutates a
/// database.
final class SQLiteReader {
	enum ReaderError: LocalizedError {
		case cannotOpen(String)
		case queryFailed(String)

		var errorDescription: String? {
			switch self {
			case .cannotOpen(let message): return "Couldn't open database: \(message)"
			case .queryFailed(let message): return "Query failed: \(message)"
			}
		}
	}

	struct QueryResult {
		let columnNames: [String]
		let rows: [[String?]]
	}

	private var handle: OpaquePointer?

	init(url: URL) throws {
		var db: OpaquePointer?
		let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
		guard status == SQLITE_OK, let db else {
			let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
			if let db { sqlite3_close(db) }
			throw ReaderError.cannotOpen(message)
		}
		handle = db
	}

	deinit {
		if let handle { sqlite3_close(handle) }
	}

	func tableNames() throws -> [String] {
		let result = try run("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;")
		return result.rows.compactMap { $0.first ?? nil }
	}

	func rows(table: String, offset: Int, limit: Int) throws -> QueryResult {
		try run("SELECT * FROM \"\(table.replacingOccurrences(of: "\"", with: "\"\""))\" LIMIT \(limit) OFFSET \(offset);")
	}

	func rowCount(table: String) throws -> Int {
		let result = try run("SELECT COUNT(*) FROM \"\(table.replacingOccurrences(of: "\"", with: "\"\""))\";")
		guard let firstRow = result.rows.first, let cell = firstRow.first, let text = cell, let value = Int(text) else { return 0 }
		return value
	}

	/// Runs arbitrary caller-supplied SQL, for the viewer's free-form query field.
	func run(_ sql: String) throws -> QueryResult {
		guard let handle else { throw ReaderError.cannotOpen("Database is closed.") }
		var statement: OpaquePointer?
		guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
			throw ReaderError.queryFailed(String(cString: sqlite3_errmsg(handle)))
		}
		defer { sqlite3_finalize(statement) }

		let columnCount = sqlite3_column_count(statement)
		var columnNames: [String] = []
		columnNames.reserveCapacity(Int(columnCount))
		for index in 0..<columnCount {
			columnNames.append(String(cString: sqlite3_column_name(statement, index)))
		}

		var rows: [[String?]] = []
		while true {
			let step = sqlite3_step(statement)
			if step == SQLITE_DONE { break }
			guard step == SQLITE_ROW else {
				throw ReaderError.queryFailed(String(cString: sqlite3_errmsg(handle)))
			}
			var row: [String?] = []
			row.reserveCapacity(Int(columnCount))
			for index in 0..<columnCount {
				row.append(SQLiteReader.stringValue(statement: statement, column: index))
			}
			rows.append(row)
		}
		return QueryResult(columnNames: columnNames, rows: rows)
	}

	private static func stringValue(statement: OpaquePointer, column: Int32) -> String? {
		switch sqlite3_column_type(statement, column) {
		case SQLITE_NULL:
			return nil
		case SQLITE_INTEGER:
			return String(sqlite3_column_int64(statement, column))
		case SQLITE_FLOAT:
			return String(sqlite3_column_double(statement, column))
		case SQLITE_TEXT:
			return String(cString: sqlite3_column_text(statement, column))
		case SQLITE_BLOB:
			let byteCount = sqlite3_column_bytes(statement, column)
			return "<\(byteCount) byte BLOB>"
		default:
			return nil
		}
	}
}
