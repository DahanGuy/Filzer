import Foundation

struct CompositeArchiveService: ArchiveService {
	private let zip = ZIPFoundationArchiveService()
	private let swCompression = SWCompressionArchiveService()
	private let rar = RarArchiveService()

	func compress(_ urls: [URL], to destination: URL) throws {
		switch ArchiveFormat.detect(from: destination) {
		case .zip:
			try zip.compress(urls, to: destination)
		case .tar, .tarGz, .tarBz2:
			try swCompression.compress(urls, to: destination)
		case .rar, .gzip, .bzip2, .xz, .sevenZip:
			throw FileSystemError.unsupported("Filzer can't create .\(ArchiveFormat.detect(from: destination).fileExtension) archives.")
		}
	}

	func extract(_ archive: URL, toDirectory destination: URL, password: String?) throws {
		try backend(for: archive).extract(archive, toDirectory: destination, password: password)
	}

	func listEntries(_ archive: URL, password: String?) throws -> [ArchiveEntry] {
		try backend(for: archive).listEntries(archive, password: password)
	}

	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL, password: String?) throws {
		try backend(for: archive).extractEntry(entryPath, from: archive, to: destination, password: password)
	}

	private func backend(for archive: URL) -> ArchiveService {
		switch ArchiveFormat.detect(from: archive) {
		case .zip: return zip
		case .rar: return rar
		case .tar, .tarGz, .tarBz2, .gzip, .bzip2, .xz, .sevenZip: return swCompression
		}
	}
}
