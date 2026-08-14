import Foundation

/// Dispatches to the right backend by archive format. Creation always goes to ZIP
/// (Filzer only ever creates `.zip`, matching Filza); extraction/listing routes to
/// whichever library actually understands that format.
struct CompositeArchiveService: ArchiveService {
	private let zip = ZIPFoundationArchiveService()
	private let swCompression = SWCompressionArchiveService()
	private let rar = RarArchiveService()

	func compress(_ urls: [URL], to destination: URL) throws {
		try zip.compress(urls, to: destination)
	}

	func extract(_ archive: URL, toDirectory destination: URL) throws {
		try backend(for: archive).extract(archive, toDirectory: destination)
	}

	func listEntries(_ archive: URL) throws -> [ArchiveEntry] {
		try backend(for: archive).listEntries(archive)
	}

	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL) throws {
		try backend(for: archive).extractEntry(entryPath, from: archive, to: destination)
	}

	private func backend(for archive: URL) -> ArchiveService {
		switch ArchiveFormat.detect(from: archive) {
		case .zip: return zip
		case .rar: return rar
		case .tar, .tarGz, .gzip, .bzip2, .xz, .sevenZip: return swCompression
		}
	}
}
