import Foundation

protocol ArchiveService {
	func compress(_ urls: [URL], to destination: URL) throws

	func extract(_ archive: URL, toDirectory destination: URL, password: String?) throws

	func listEntries(_ archive: URL, password: String?) throws -> [ArchiveEntry]

	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL, password: String?) throws
}
