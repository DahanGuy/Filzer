import Foundation
import Unrar

struct RarArchiveService: ArchiveService {
	func compress(_ urls: [URL], to destination: URL) throws {
		throw FileSystemError.unsupported("Filzer can only create .zip, .tar, .tar.gz, and .tar.bz2 archives.")
	}

	func extract(_ archive: URL, toDirectory destination: URL, password: String?) throws {
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		let unrarArchive = try Archive(fileURL: archive, password: password)
		for entry in try entries(of: unrarArchive, url: archive) {
			let entryURL = destination.appendingPathComponent(entry.fileName)
			if entry.directory {
				try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: true)
			} else {
				try FileManager.default.createDirectory(at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
				try extractedData(of: entry, from: unrarArchive, url: archive).write(to: entryURL)
			}
		}
	}

	func listEntries(_ archive: URL, password: String?) throws -> [ArchiveEntry] {
		let unrarArchive = try Archive(fileURL: archive, password: password)
		return try entries(of: unrarArchive, url: archive).map { entry in
			ArchiveEntry(
				path: entry.fileName,
				isDirectory: entry.directory,
				uncompressedSize: Int64(entry.uncompressedSize),
				compressedSize: Int64(entry.compressedSize)
			)
		}
	}

	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL, password: String?) throws {
		let unrarArchive = try Archive(fileURL: archive, password: password)
		guard let entry = try entries(of: unrarArchive, url: archive).first(where: { $0.fileName == entryPath }) else {
			throw FileSystemError.notFound(archive.appendingPathComponent(entryPath))
		}
		try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
		try extractedData(of: entry, from: unrarArchive, url: archive).write(to: destination)
	}

	private func entries(of archive: Archive, url: URL) throws -> [Entry] {
		do {
			return try archive.entries()
		} catch UnrarError.missingPassword, UnrarError.badData {
			throw FileSystemError.archivePasswordRequired(url)
		}
	}

	private func extractedData(of entry: Entry, from archive: Archive, url: URL) throws -> Data {
		do {
			return try archive.extract(entry)
		} catch UnrarError.missingPassword, UnrarError.badData {
			throw FileSystemError.archivePasswordRequired(url)
		}
	}
}
