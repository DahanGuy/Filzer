import Foundation
import SWCompression

struct SWCompressionArchiveService: ArchiveService {
	private struct RawEntry {
		let name: String
		let isDirectory: Bool
		let size: Int
		let data: Data?
	}

	func compress(_ urls: [URL], to destination: URL) throws {
		guard !urls.isEmpty else {
			throw FileSystemError.operationFailed("Nothing selected to compress.")
		}
		var entries: [TarEntry] = []
		for url in urls {
			entries += try tarEntries(at: url, name: url.lastPathComponent)
		}
		let tarData = TarContainer.create(from: entries)
		switch ArchiveFormat.detect(from: destination) {
		case .tar:
			try tarData.write(to: destination)
		case .tarGz:
			try GzipArchive.archive(data: tarData, fileName: destination.deletingPathExtension().lastPathComponent).write(to: destination)
		case .tarBz2:
			try BZip2.compress(data: tarData).write(to: destination)
		case .zip, .rar, .gzip, .bzip2, .xz, .sevenZip:
			throw FileSystemError.unsupported("Filzer can't create this archive format.")
		}
	}

	private func tarEntries(at url: URL, name: String) throws -> [TarEntry] {
		let fm = FileManager.default
		var isDirectory: ObjCBool = false
		guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
			throw FileSystemError.notFound(url)
		}
		let modificationTime = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
		if isDirectory.boolValue {
			var info = TarEntryInfo(name: name + "/", type: .directory)
			info.modificationTime = modificationTime
			var entries = [TarEntry(info: info, data: nil)]
			for childName in try fm.contentsOfDirectory(atPath: url.path).sorted() {
				entries += try tarEntries(at: url.appendingPathComponent(childName), name: name + "/" + childName)
			}
			return entries
		}
		var info = TarEntryInfo(name: name, type: .regular)
		info.modificationTime = modificationTime
		return [TarEntry(info: info, data: try Data(contentsOf: url))]
	}

	func extract(_ archive: URL, toDirectory destination: URL, password: String?) throws {
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

	func listEntries(_ archive: URL, password: String?) throws -> [ArchiveEntry] {
		try rawEntries(of: archive).map { entry in
			ArchiveEntry(path: entry.name, isDirectory: entry.isDirectory, uncompressedSize: Int64(entry.size), compressedSize: Int64(entry.size))
		}
	}

	func extractEntry(_ entryPath: String, from archive: URL, to destination: URL, password: String?) throws {
		guard let entry = try rawEntries(of: archive).first(where: { $0.name == entryPath }) else {
			throw FileSystemError.notFound(archive.appendingPathComponent(entryPath))
		}
		try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
		try (entry.data ?? Data()).write(to: destination)
	}

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
		case .tarBz2:
			let tarData = try BZip2.decompress(data: raw)
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
