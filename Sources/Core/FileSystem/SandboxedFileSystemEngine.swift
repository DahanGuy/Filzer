import Foundation

/// The default `FileSystemEngine`: everything routes through `FileManager`, scoped to
/// whatever sandbox/security-scoped access the app currently holds. This is the only
/// type in the app that touches `FileManager` for mutations — see `FileOperation` for
/// why every call funnels through here.
final class SandboxedFileSystemEngine: FileSystemEngine {
	private let archiveService: ArchiveService

	init(archiveService: ArchiveService = ZIPFoundationArchiveService()) {
		self.archiveService = archiveService
	}

	func execute(_ operation: FileOperation) async throws -> FileOperationResult {
		switch operation {
		case .listDirectory(let url, let includeHidden):
			return .nodes(try DirectoryLister.children(of: url, includeHidden: includeHidden))

		case .nodeInfo(let url):
			return .node(try FileNode.make(at: url))

		case .createDirectory(let url):
			try throwIfExists(url)
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			return .node(try FileNode.make(at: url))

		case .createFile(let url, let contents):
			try throwIfExists(url)
			guard FileManager.default.createFile(atPath: url.path, contents: contents) else {
				throw FileSystemError.operationFailed("Couldn't create \"\(url.lastPathComponent)\".")
			}
			return .node(try FileNode.make(at: url))

		case .readFile(let url):
			return .data(try Data(contentsOf: url))

		case .writeFile(let url, let data):
			try data.write(to: url, options: .atomic)
			return .done

		case .delete(let urls):
			for url in urls {
				try FileManager.default.removeItem(at: url)
			}
			return .done

		case .renameItem(let url, let newName):
			try validateName(newName)
			let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
			if destination.path == url.path {
				return .node(try FileNode.make(at: url))
			}
			try throwIfExists(destination)
			try FileManager.default.moveItem(at: url, to: destination)
			return .node(try FileNode.make(at: destination))

		case .copyItem(let source, let destination):
			try throwIfExists(destination)
			try FileManager.default.copyItem(at: source, to: destination)
			return .node(try FileNode.make(at: destination))

		case .moveItem(let source, let destination):
			try throwIfExists(destination)
			try FileManager.default.moveItem(at: source, to: destination)
			return .node(try FileNode.make(at: destination))

		case .copyItems(let urls, let directory):
			for url in urls {
				let destination = directory.appendingPathComponent(url.lastPathComponent)
				try throwIfExists(destination)
				try FileManager.default.copyItem(at: url, to: destination)
			}
			return .done

		case .moveItems(let urls, let directory):
			for url in urls {
				let destination = directory.appendingPathComponent(url.lastPathComponent)
				try throwIfExists(destination)
				try FileManager.default.moveItem(at: url, to: destination)
			}
			return .done

		case .createSymbolicLink(let url, let destination):
			try throwIfExists(url)
			try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
			return .node(try FileNode.make(at: url))

		case .createHardLink(let url, let destination):
			try throwIfExists(url)
			try FileManager.default.linkItem(at: destination, to: url)
			return .node(try FileNode.make(at: url))

		case .setPermissions(let urls, let posixPermissions, let recursive):
			for url in urls {
				try applyPermissions(posixPermissions, to: url, recursive: recursive)
			}
			return .done

		case .calculateSize(let url):
			return .size(try calculateSizeRecursively(of: url))

		case .compressItems(let urls, let destination):
			try archiveService.compress(urls, to: destination)
			return .done

		case .extractArchive(let archive, let destination):
			try archiveService.extract(archive, toDirectory: destination)
			return .done

		case .listArchiveEntries(let archive):
			return .archiveEntries(try archiveService.listEntries(archive))

		case .extractArchiveEntry(let archive, let entryPath, let destination):
			try archiveService.extractEntry(entryPath, from: archive, to: destination)
			return .done

		case .search(let root, let query, let includeHidden):
			return .nodes(try FileSearchEngine.search(root: root, query: query, includeHidden: includeHidden))

		case .volumeInfo(let url):
			return .volume(try readVolumeInfo(for: url))
		}
	}

	// MARK: - Helpers

	private func throwIfExists(_ url: URL) throws {
		if FileManager.default.fileExists(atPath: url.path) {
			throw FileSystemError.alreadyExists(url)
		}
	}

	private func validateName(_ name: String) throws {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
			throw FileSystemError.invalidName(name)
		}
	}

	private func calculateSizeRecursively(of url: URL) throws -> Int64 {
		let node = try FileNode.make(at: url)
		guard node.kind == .directory else { return node.size }
		var total: Int64 = 0
		for child in try DirectoryLister.children(of: url, includeHidden: true) {
			total += try calculateSizeRecursively(of: child.url)
		}
		return total
	}

	private func applyPermissions(_ mode: Int16, to url: URL, recursive: Bool) throws {
		try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
		guard recursive else { return }
		let node = try FileNode.make(at: url)
		guard node.kind == .directory else { return }
		for child in try DirectoryLister.children(of: url, includeHidden: true) {
			try applyPermissions(mode, to: child.url, recursive: true)
		}
	}

	private func readVolumeInfo(for url: URL) throws -> VolumeInfo {
		let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
		let total = Int64(values.volumeTotalCapacity ?? 0)
		let available = values.volumeAvailableCapacityForImportantUsage ?? 0
		return VolumeInfo(totalCapacity: total, availableCapacity: available)
	}
}
