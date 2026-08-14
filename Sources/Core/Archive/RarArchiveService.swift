import Foundation
import Unrar

/// RAR extraction via `mtgto/Unrar.swift`, a Swift wrapper over RarLab's own official
/// UnRAR decompression source. Extraction only: the UnRAR License explicitly forbids
/// using this source to build a RAR-*compatible archiver* or to re-create RAR's
/// proprietary compression algorithm, so Filzer never creates `.rar` files — only
/// `.zip` creation is supported anywhere in the app.
///
/// The UnRAR License requires its text (reproduced in `AboutView`'s licenses section)
/// to accompany any software that redistributes this source.
struct RarArchiveService: ArchiveService {
	func compress(_ urls: [URL], to destination: URL) throws {
		throw FileSystemError.unsupported("Filzer can only create .zip archives.")
	}

	func extract(_ archive: URL, toDirectory destination: URL) throws {
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		let unrarArchive = try Archive(fileURL: archive)
		for entry in try unrarArchive.entries() {
			let entryURL = destination.appendingPathComponent(entry.fileName)
			if entry.directory {
				try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: true)
			} else {
				try FileManager.default.createDirectory(at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
				try unrarArchive.extract(entry).write(to: entryURL)
			}
		}
	}

	func listEntries(_ archive: URL) throws -> [ArchiveEntry] {
		let unrarArchive = try Archive(fileURL: archive)
		return try unrarArchive.entries().map { entry in
			ArchiveEntry(
				path: entry.fileName,
				isDirectory: entry.directory,
				uncompressedSize: Int64(entry.uncompressedSize),
				compressedSize: Int64(entry.compressedSize)
			)
		}
	}

	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL) throws {
		let unrarArchive = try Archive(fileURL: archive)
		guard let entry = try unrarArchive.entries().first(where: { $0.fileName == entryPath }) else {
			throw FileSystemError.notFound(archive.appendingPathComponent(entryPath))
		}
		try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
		try unrarArchive.extract(entry).write(to: destination)
	}
}
