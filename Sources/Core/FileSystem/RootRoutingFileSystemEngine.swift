import Foundation

final class RootRoutingFileSystemEngine: FileSystemEngine {
	private let base: FileSystemEngine
	private let access: RootAccess

	init(base: FileSystemEngine, access: RootAccess = .shared) {
		self.base = base
		self.access = access
	}

	func execute(_ operation: FileOperation) async throws -> FileOperationResult {
		guard Self.isRoutable(operation), let client = await access.activeClient() else {
			return try await base.execute(operation)
		}
		do {
			return try await perform(operation, using: client)
		} catch RootHelperError.launchFailed(let reason) {
			access.markUnavailable(reason)
			return try await base.execute(operation)
		}
	}

	private static func isRoutable(_ operation: FileOperation) -> Bool {
		let urls: [URL]
		switch operation {
		case .listDirectory(let url, _), .nodeInfo(let url), .createDirectory(let url),
			.createFile(let url, _), .readFile(let url), .writeFile(let url, _),
			.renameItem(let url, _), .calculateSize(let url):
			urls = [url]
		case .delete(let deleted):
			urls = deleted
		case .copyItem(let source, let destination), .moveItem(let source, let destination):
			urls = [source, destination]
		case .copyItems(let sources, let directory), .moveItems(let sources, let directory):
			urls = sources + [directory]
		case .createSymbolicLink(let url, let destination), .createHardLink(let url, let destination):
			urls = [url, destination]
		case .setPermissions(let sources, _, _):
			urls = sources
		case .compressItems, .extractArchive, .listArchiveEntries, .extractArchiveEntry, .search, .volumeInfo:
			return false
		}
		return urls.allSatisfy { !RemoteURL.isRemote($0) }
	}

	private func perform(_ operation: FileOperation, using client: RootHelperClient) async throws -> FileOperationResult {
		switch operation {
		case .listDirectory(let url, let includeHidden):
			return .nodes(try await client.list(url, includeHidden: includeHidden))

		case .nodeInfo(let url):
			return .node(try await client.stat(url))

		case .createDirectory(let url):
			try await client.makeDirectory(url)
			return .node(try await client.stat(url))

		case .createFile(let url, let contents):
			try await client.write(contents, to: url, createNew: true)
			return .node(try await client.stat(url))

		case .readFile(let url):
			return .data(try await client.read(url))

		case .writeFile(let url, let data):
			try await client.write(data, to: url, createNew: false)
			return .done

		case .delete(let urls):
			for url in urls {
				try await client.remove(url)
			}
			return .done

		case .renameItem(let url, let newName):
			let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
				throw FileSystemError.invalidName(newName)
			}
			let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
			if destination.path == url.path {
				return .node(try await client.stat(url))
			}
			try await client.move(from: url, to: destination)
			return .node(try await client.stat(destination))

		case .copyItem(let source, let destination):
			try await client.copy(from: source, to: destination)
			return .node(try await client.stat(destination))

		case .moveItem(let source, let destination):
			try await client.move(from: source, to: destination)
			return .node(try await client.stat(destination))

		case .copyItems(let sources, let directory):
			for source in sources {
				try await client.copy(from: source, to: directory.appendingPathComponent(source.lastPathComponent))
			}
			return .done

		case .moveItems(let sources, let directory):
			for source in sources {
				try await client.move(from: source, to: directory.appendingPathComponent(source.lastPathComponent))
			}
			return .done

		case .createSymbolicLink(let url, let destination):
			try await client.makeSymbolicLink(at: url, destination: destination)
			return .node(try await client.stat(url))

		case .createHardLink(let url, let destination):
			try await client.makeHardLink(at: url, destination: destination)
			return .node(try await client.stat(url))

		case .setPermissions(let urls, let posixPermissions, let recursive):
			for url in urls {
				try await client.setPermissions(posixPermissions, at: url, recursive: recursive)
			}
			return .done

		case .calculateSize(let url):
			return .size(try await client.size(of: url))

		case .compressItems, .extractArchive, .listArchiveEntries, .extractArchiveEntry, .search, .volumeInfo:
			return try await base.execute(operation)
		}
	}
}
