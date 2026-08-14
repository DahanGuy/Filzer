import Foundation
import SWCompression

/// Extraction-only backend for TAR, TAR.GZ, GZip, BZip2, XZ, and 7-Zip via
/// SWCompression. Everything here is Data-in/Data-out (SWCompression has no streaming
/// API besides plain TAR, and combined formats like tar.gz still fully materialize both
/// the compressed and decompressed bytes) — fine for the file sizes a mobile file
/// manager typically opens, not suited to multi-gigabyte archives.
struct SWCompressionArchiveService: ArchiveService {
	private struct RawEntry {
		let name: String
		let isDirectory: Bool
		let size: Int
		let data: Data?
	}

	func compress(_ urls: [URL], to destination: URL) throws {
		throw FileSystemError.unsupported("Filzer can only create .zip archives.")
	}

	func extract(_ archive: URL, toDirectory destination: URL) throws {
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		for entry in try rawEntries(of: archive) {
			let entryURL = destination.appendingPathComponent(entry.name)
			if entry.isDirectory {
				try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: true)
			} else {
				try FileManager.default.createDirectory(at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
				try (entry.data ?? Data()).write(to: entryURL)
			}
		}
	}

	func listEntries(_ archive: URL) throws -> [ArchiveEntry] {
		try rawEntries(of: archive).map { entry in
			ArchiveEntry(path: entry.name, isDirectory: entry.isDirectory, uncompressedSize: Int64(entry.size), compressedSize: Int64(entry.size))
		}
	}

	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL) throws {
		guard let entry = try rawEntries(of: archive).first(where: { $0.name == entryPath }) else {
			throw FileSystemError.notFound(archive.appendingPathComponent(entryPath))
		}
		try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
		try (entry.data ?? Data()).write(to: destination)
	}

	/// Loads every entry (with data) for `archive`, decoding by format.
	private func rawEntries(of archive: URL) throws -> [RawEntry] {
		let raw = try Data(contentsOf: archive)
		switch ArchiveFormat.detect(from: archive) {
		case .tar:
			return try TarContainer.open(container: raw).map {
				RawEntry(name: $0.info.name, isDirectory: $0.info.type == .directory, size: Int($0.info.size ?? 0), data: $0.data)
			}
		case .tarGz:
			let tarData = try GzipArchive.unarchive(archive: raw)
			return try TarContainer.open(container: tarData).map {
				RawEntry(name: $0.info.name, isDirectory: $0.info.type == .directory, size: Int($0.info.size ?? 0), data: $0.data)
			}
		case .gzip:
			let decoded = try GzipArchive.unarchive(archive: raw)
			return [RawEntry(name: archive.deletingPathExtension().lastPathComponent, isDirectory: false, size: decoded.count, data: decoded)]
		case .bzip2:
			let decoded = try BZip2.decompress(data: raw)
			return [RawEntry(name: archive.deletingPathExtension().lastPathComponent, isDirectory: false, size: decoded.count, data: decoded)]
		case .xz:
			let decoded = try XZArchive.unarchive(archive: raw)
			return [RawEntry(name: archive.deletingPathExtension().lastPathComponent, isDirectory: false, size: decoded.count, data: decoded)]
		case .sevenZip:
			return try SevenZipContainer.open(container: raw).map {
				RawEntry(name: $0.info.name, isDirectory: $0.info.type == .directory, size: Int($0.info.size ?? 0), data: $0.data)
			}
		case .zip, .rar:
			throw FileSystemError.unsupported("This archive format isn't handled by SWCompressionArchiveService.")
		}
	}
}
