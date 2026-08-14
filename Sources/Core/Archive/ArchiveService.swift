import Foundation

/// Everything `SandboxedFileSystemEngine` needs from an archive backend. Kept as a
/// protocol — separate from the concrete `ZIPFoundationArchiveService` — so the engine
/// itself never imports a third-party module; only `ZIPFoundationArchiveService.swift`
/// does.
protocol ArchiveService {
	/// Zips `urls` (files and/or folders, taken as-is with their own names) into a new
	/// archive at `destination`. `destination` must not already exist.
	func compress(_ urls: [URL], to destination: URL) throws

	/// Extracts every entry of `archive` into `destination`, creating it if needed.
	func extract(_ archive: URL, toDirectory destination: URL) throws

	/// Lists an archive's contents without extracting anything to disk.
	func listEntries(_ archive: URL) throws -> [ArchiveEntry]

	/// Extracts exactly one entry to `destination`, without touching the rest of the archive.
	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL) throws
}
