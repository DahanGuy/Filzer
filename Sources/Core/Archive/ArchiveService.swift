import Foundation

/// Everything `SandboxedFileSystemEngine` needs from an archive backend. Kept as a
/// protocol — separate from the concrete `ZIPFoundationArchiveService` — so the engine
/// itself never imports a third-party module; only `ZIPFoundationArchiveService.swift`
/// does.
protocol ArchiveService {
	/// Compresses `urls` (files and/or folders, taken as-is with their own names) into
	/// a new archive at `destination` — whatever format `destination`'s name implies
	/// (see `ArchiveFormat.detect`). `destination` must not already exist.
	func compress(_ urls: [URL], to destination: URL) throws

	/// Extracts every entry of `archive` into `destination`, creating it if needed.
	/// `password` is only meaningful for RAR (the only format Filzer can decrypt);
	/// every other backend ignores it. A missing/wrong password throws
	/// `FileSystemError.archivePasswordRequired`.
	func extract(_ archive: URL, toDirectory destination: URL, password: String?) throws

	/// Lists an archive's contents without extracting anything to disk.
	func listEntries(_ archive: URL, password: String?) throws -> [ArchiveEntry]

	/// Extracts exactly one entry to `destination`, without touching the rest of the archive.
	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL, password: String?) throws
}
