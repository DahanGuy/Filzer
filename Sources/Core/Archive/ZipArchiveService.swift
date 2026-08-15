import Foundation
import ZIPFoundation

/// The only file in Filzer that imports ZIPFoundation. `SandboxedFileSystemEngine`
/// only ever sees the `ArchiveService` protocol.
struct ZIPFoundationArchiveService: ArchiveService {
	func compress(_ urls: [URL], to destination: URL) throws {
		guard !urls.isEmpty else {
			throw FileSystemError.operationFailed("Nothing selected to compress.")
		}
		if urls.count == 1 {
			try FileManager.default.zipItem(at: urls[0], to: destination, shouldKeepParent: true, compressionMethod: .deflate)
			return
		}
		let archive = try Archive(url: destination, accessMode: .create)
		for url in urls {
			try addEntryRecursively(at: url, path: url.lastPathComponent, to: archive)
		}
	}

	func extract(_ archive: URL, toDirectory destination: URL, password: String?) throws {
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		try FileManager.default.unzipItem(at: archive, to: destination)
	}

	func listEntries(_ archiveURL: URL, password: String?) throws -> [ArchiveEntry] {
		let archive = try Archive(url: archiveURL, accessMode: .read)
		return archive.map { entry in
			ArchiveEntry(
				path: entry.path,
				isDirectory: entry.type == .directory,
				uncompressedSize: Int64(entry.uncompressedSize),
				compressedSize: Int64(entry.compressedSize)
			)
		}
	}

	func extractEntry(_ entryPath: String, from archiveURL: URL, to destination: URL, password: String?) throws {
		let archive = try Archive(url: archiveURL, accessMode: .read)
		guard let entry = archive[entryPath] else {
			throw FileSystemError.notFound(archiveURL.appendingPathComponent(entryPath))
		}
		try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
		_ = try archive.extract(entry, to: destination)
	}

	/// Adds `url` (file, directory, or symlink) under `path`, recursing into directories
	/// one level of `addEntry` at a time — `Archive` has no built-in recursive add.
	private func addEntryRecursively(at url: URL, path: String, to archive: Archive) throws {
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
			throw FileSystemError.notFound(url)
		}
		let entryPath = isDirectory.boolValue ? path + "/" : path
		try archive.addEntry(with: entryPath, fileURL: url, compressionMethod: .deflate)
		guard isDirectory.boolValue else { return }

		for subpath in try fileManager.subpathsOfDirectory(atPath: url.path).sorted() {
			let childURL = url.appendingPathComponent(subpath)
			var childIsDirectory: ObjCBool = false
			fileManager.fileExists(atPath: childURL.path, isDirectory: &childIsDirectory)
			let childEntryPath = path + "/" + subpath + (childIsDirectory.boolValue ? "/" : "")
			try archive.addEntry(with: childEntryPath, fileURL: childURL, compressionMethod: .deflate)
		}
	}
}
