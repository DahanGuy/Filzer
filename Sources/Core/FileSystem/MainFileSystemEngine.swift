import Foundation

final class MainFileSystemEngine: FileSystemEngine {
	private let archiveService: ArchiveService

	init(archiveService: ArchiveService = CompositeArchiveService()) {
		self.archiveService = archiveService
	}

	func execute(_ operation: FileOperation) async throws -> FileOperationResult {
		switch operation {
		case .listDirectory(let url, let includeHidden):
			if RemoteURL.isRemote(url) {
				return .nodes(try await remoteChildren(of: url, includeHidden: includeHidden))
			}
			return .nodes(try DirectoryLister.children(of: url, includeHidden: includeHidden))

		case .nodeInfo(let url):
			return .node(try await resolveNode(at: url))

		case .createDirectory(let url):
			if RemoteURL.isRemote(url) {
				try await throwIfExistsAsync(url)
				let (provider, path) = try await remoteProvider(for: url)
				try await provider.createDirectory(at: path)
				return .node(try await resolveNode(at: url))
			}
			try throwIfExists(url)
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			return .node(try FileNode.make(at: url))

		case .createFile(let url, let contents):
			if RemoteURL.isRemote(url) {
				try await throwIfExistsAsync(url)
				try await writeBytes(contents, to: url)
				return .node(try await resolveNode(at: url))
			}
			try throwIfExists(url)
			guard FileManager.default.createFile(atPath: url.path, contents: contents) else {
				throw FileSystemError.operationFailed("Couldn't create \"\(url.lastPathComponent)\".")
			}
			return .node(try FileNode.make(at: url))

		case .readFile(let url):
			return .data(try await readBytes(at: url))

		case .writeFile(let url, let data):
			try await writeBytes(data, to: url)
			return .done

		case .delete(let urls):
			for url in urls {
				try await deleteOne(url)
			}
			return .done

		case .renameItem(let url, let newName):
			try validateName(newName)
			let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
			if destination.path == url.path {
				return .node(try await resolveNode(at: url))
			}
			try await moveOne(from: url, to: destination)
			return .node(try await resolveNode(at: destination))

		case .copyItem(let source, let destination):
			try await copyOne(from: source, to: destination)
			return .node(try await resolveNode(at: destination))

		case .moveItem(let source, let destination):
			try await moveOne(from: source, to: destination)
			return .node(try await resolveNode(at: destination))

		case .copyItems(let urls, let directory):
			for url in urls {
				try await copyOne(from: url, to: directory.appendingPathComponent(url.lastPathComponent))
			}
			return .done

		case .moveItems(let urls, let directory):
			for url in urls {
				try await moveOne(from: url, to: directory.appendingPathComponent(url.lastPathComponent))
			}
			return .done

		case .createSymbolicLink(let url, let destination):
			guard !RemoteURL.isRemote(url), !RemoteURL.isRemote(destination) else {
				throw FileSystemError.unsupported("Symbolic links aren't supported on network locations.")
			}
			try throwIfExists(url)
			try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
			return .node(try FileNode.make(at: url))

		case .createHardLink(let url, let destination):
			guard !RemoteURL.isRemote(url), !RemoteURL.isRemote(destination) else {
				throw FileSystemError.unsupported("Hard links aren't supported on network locations.")
			}
			try throwIfExists(url)
			try FileManager.default.linkItem(at: destination, to: url)
			return .node(try FileNode.make(at: url))

		case .setPermissions(let urls, let posixPermissions, let recursive):
			for url in urls {
				guard !RemoteURL.isRemote(url) else {
					throw FileSystemError.unsupported("Permissions can't be changed on network locations.")
				}
				try applyPermissions(posixPermissions, to: url, recursive: recursive)
			}
			return .done

		case .calculateSize(let url):
			return .size(try await calculateSizeRecursively(of: url))

		case .compressItems(let urls, let destination):
			try await compressItems(urls, to: destination)
			return .done

		case .extractArchive(let archive, let destination, let password):
			try await extractArchive(archive, toDirectory: destination, password: password)
			return .done

		case .listArchiveEntries(let archive, let password):
			let (localArchive, isTemporary) = try await materializeLocally(archive)
			defer { if isTemporary { try? FileManager.default.removeItem(at: localArchive) } }
			return .archiveEntries(try archiveService.listEntries(localArchive, password: password))

		case .extractArchiveEntry(let archive, let entryPath, let destination, let password):
			try await extractArchiveEntry(entryPath, from: archive, to: destination, password: password)
			return .done

		case .search(let root, let query, let includeHidden):
			guard !RemoteURL.isRemote(root) else {
				throw FileSystemError.unsupported("Search isn't available for network locations yet.")
			}
			return .nodes(try FileSearchEngine.search(root: root, query: query, includeHidden: includeHidden))

		case .volumeInfo(let url):
			guard !RemoteURL.isRemote(url) else {
				throw FileSystemError.unsupported("Storage info isn't available for network locations.")
			}
			return .volume(try readVolumeInfo(for: url))
		}
	}

	private func readBytes(at url: URL) async throws -> Data {
		guard RemoteURL.isRemote(url) else { return try Data(contentsOf: url) }
		let (provider, path) = try await remoteProvider(for: url)
		return try await provider.readFile(at: path)
	}

	private func writeBytes(_ data: Data, to url: URL) async throws {
		guard RemoteURL.isRemote(url) else {
			try data.write(to: url, options: .atomic)
			return
		}
		let (provider, path) = try await remoteProvider(for: url)
		try await provider.writeFile(at: path, data: data)
	}

	private func deleteOne(_ url: URL) async throws {
		guard RemoteURL.isRemote(url) else {
			try FileManager.default.removeItem(at: url)
			return
		}
		let (provider, path) = try await remoteProvider(for: url)
		try await provider.delete(at: path)
	}

	private func resolveNode(at url: URL) async throws -> FileNode {
		guard RemoteURL.isRemote(url) else { return try FileNode.make(at: url) }
		let (provider, path) = try await remoteProvider(for: url)
		let components = path.split(separator: "/", omittingEmptySubsequences: true)
		guard components.count > 1 else {
			return FileNode.remoteRoot(url: url)
		}
		let parentPath = "/" + components.dropLast().joined(separator: "/")
		let name = String(components[components.count - 1])
		let siblings = try await provider.listDirectory(at: parentPath)
		guard let match = siblings.first(where: { $0.name == name }) else {
			throw FileSystemError.notFound(url)
		}
		return FileNode.remote(url: url, item: match)
	}

	private func childrenOf(_ url: URL) async throws -> [FileNode] {
		if RemoteURL.isRemote(url) {
			return try await remoteChildren(of: url, includeHidden: true)
		}
		return try DirectoryLister.children(of: url, includeHidden: true)
	}

	private func remoteChildren(of url: URL, includeHidden: Bool) async throws -> [FileNode] {
		let (provider, path) = try await remoteProvider(for: url)
		let items = try await provider.listDirectory(at: path)
		return items
			.filter { includeHidden || !$0.name.hasPrefix(".") }
			.map { FileNode.remote(url: url.appendingPathComponent($0.name, isDirectory: $0.isDirectory), item: $0) }
	}

	private func remoteProvider(for url: URL) async throws -> (RemoteFileProvider, String) {
		guard let connectionID = RemoteURL.connectionID(from: url) else {
			throw FileSystemError.notFound(url)
		}
		let provider = try await RemoteProviderRegistry.shared.provider(for: connectionID)
		return (provider, RemoteURL.remotePath(from: url))
	}

	private func throwIfExistsAsync(_ url: URL) async throws {
		guard RemoteURL.isRemote(url) else {
			try throwIfExists(url)
			return
		}
		if (try? await resolveNode(at: url)) != nil {
			throw FileSystemError.alreadyExists(url)
		}
	}

	private func createDirectoryIfNeeded(at url: URL) async throws {
		if (try? await resolveNode(at: url)) != nil { return }
		guard RemoteURL.isRemote(url) else {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			return
		}
		let (provider, path) = try await remoteProvider(for: url)
		try await provider.createDirectory(at: path)
	}

	private func copyOne(from source: URL, to destination: URL) async throws {
		guard RemoteURL.isRemote(source) || RemoteURL.isRemote(destination) else {
			try throwIfExists(destination)
			try FileManager.default.copyItem(at: source, to: destination)
			return
		}
		try await throwIfExistsAsync(destination)
		if try await resolveNode(at: source).isDirectory {
			try await copyDirectoryTree(from: source, to: destination)
		} else {
			try await writeBytes(try await readBytes(at: source), to: destination)
		}
	}

	private func copyDirectoryTree(from source: URL, to destination: URL) async throws {
		try await createDirectoryIfNeeded(at: destination)
		for child in try await childrenOf(source) {
			let childDestination = destination.appendingPathComponent(child.name)
			if child.isDirectory {
				try await copyDirectoryTree(from: child.url, to: childDestination)
			} else {
				try await writeBytes(try await readBytes(at: child.url), to: childDestination)
			}
		}
	}

	private func moveOne(from source: URL, to destination: URL) async throws {
		guard RemoteURL.isRemote(source) || RemoteURL.isRemote(destination) else {
			try throwIfExists(destination)
			try FileManager.default.moveItem(at: source, to: destination)
			return
		}
		if RemoteURL.isRemote(source), RemoteURL.isRemote(destination),
			RemoteURL.connectionID(from: source) == RemoteURL.connectionID(from: destination)
		{
			try await throwIfExistsAsync(destination)
			let (provider, sourcePath) = try await remoteProvider(for: source)
			try await provider.move(from: sourcePath, to: RemoteURL.remotePath(from: destination))
			return
		}
		try await copyOne(from: source, to: destination)
		try await deleteOne(source)
	}

	private func compressItems(_ urls: [URL], to destination: URL) async throws {
		let hasRemoteSource = urls.contains { RemoteURL.isRemote($0) }
		let scratchRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		if hasRemoteSource {
			try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
		}
		defer { if hasRemoteSource { try? FileManager.default.removeItem(at: scratchRoot) } }

		var localSources: [URL] = []
		for url in urls {
			if RemoteURL.isRemote(url) {
				let localCopy = scratchRoot.appendingPathComponent(url.lastPathComponent)
				try await downloadToLocalTree(from: url, into: localCopy)
				localSources.append(localCopy)
			} else {
				localSources.append(url)
			}
		}

		if RemoteURL.isRemote(destination) {
			let tempZip = scratchRoot.appendingPathComponent(UUID().uuidString + ".zip")
			try archiveService.compress(localSources, to: tempZip)
			try await writeBytes(try Data(contentsOf: tempZip), to: destination)
		} else {
			try archiveService.compress(localSources, to: destination)
		}
	}

	private func extractArchive(_ archive: URL, toDirectory destination: URL, password: String?) async throws {
		let (localArchive, isTemporary) = try await materializeLocally(archive)
		defer { if isTemporary { try? FileManager.default.removeItem(at: localArchive) } }

		if RemoteURL.isRemote(destination) {
			let tempOutput = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
			try archiveService.extract(localArchive, toDirectory: tempOutput, password: password)
			defer { try? FileManager.default.removeItem(at: tempOutput) }
			try await uploadLocalTree(from: tempOutput, to: destination)
		} else {
			try archiveService.extract(localArchive, toDirectory: destination, password: password)
		}
	}

	private func extractArchiveEntry(_ entryPath: String, from archive: URL, to destination: URL, password: String?) async throws {
		let (localArchive, isTemporary) = try await materializeLocally(archive)
		defer { if isTemporary { try? FileManager.default.removeItem(at: localArchive) } }

		if RemoteURL.isRemote(destination) {
			let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			try archiveService.extractEntry(entryPath, from: localArchive, to: tempFile, password: password)
			defer { try? FileManager.default.removeItem(at: tempFile) }
			try await writeBytes(try Data(contentsOf: tempFile), to: destination)
		} else {
			try archiveService.extractEntry(entryPath, from: localArchive, to: destination, password: password)
		}
	}

	private func downloadToLocalTree(from url: URL, into localDestination: URL) async throws {
		if try await resolveNode(at: url).isDirectory {
			try FileManager.default.createDirectory(at: localDestination, withIntermediateDirectories: true)
			for child in try await childrenOf(url) {
				try await downloadToLocalTree(from: child.url, into: localDestination.appendingPathComponent(child.name))
			}
		} else {
			try await writeLocalFile(try await readBytes(at: url), to: localDestination)
		}
	}

	private func uploadLocalTree(from localSource: URL, to destination: URL) async throws {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: localSource.path, isDirectory: &isDirectory) else { return }
		if isDirectory.boolValue {
			try await createDirectoryIfNeeded(at: destination)
			for name in try FileManager.default.contentsOfDirectory(atPath: localSource.path) {
				try await uploadLocalTree(from: localSource.appendingPathComponent(name), to: destination.appendingPathComponent(name))
			}
		} else {
			try await writeBytes(try Data(contentsOf: localSource), to: destination)
		}
	}

	private func writeLocalFile(_ data: Data, to url: URL) async throws {
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try data.write(to: url, options: .atomic)
	}

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

	private func calculateSizeRecursively(of url: URL) async throws -> Int64 {
		let node = try await resolveNode(at: url)
		guard node.isDirectory else { return node.size }
		var total: Int64 = 0
		for child in try await childrenOf(url) {
			total += try await calculateSizeRecursively(of: child.url)
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
