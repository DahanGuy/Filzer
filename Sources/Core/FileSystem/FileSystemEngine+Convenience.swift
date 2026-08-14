import Foundation

/// Ergonomic, typed wrappers around `execute(_:)`. Every method here does nothing but
/// build a `FileOperation`, await `execute(_:)`, and unwrap the expected
/// `FileOperationResult` case — the single chokepoint stays `execute(_:)` itself.
/// UI code should only ever call the methods below, never `execute(_:)` directly.
extension FileSystemEngine {
	func listDirectory(at url: URL, includeHidden: Bool = false) async throws -> [FileNode] {
		try await expectNodes(.listDirectory(url, includeHidden: includeHidden))
	}

	func nodeInfo(at url: URL) async throws -> FileNode {
		try await expectNode(.nodeInfo(url))
	}

	@discardableResult
	func createDirectory(at url: URL) async throws -> FileNode {
		try await expectNode(.createDirectory(url))
	}

	@discardableResult
	func createFile(at url: URL, contents: Data = Data()) async throws -> FileNode {
		try await expectNode(.createFile(url, contents: contents))
	}

	func readFile(at url: URL) async throws -> Data {
		try await expectData(.readFile(url))
	}

	func writeFile(at url: URL, data: Data) async throws {
		try await expectDone(.writeFile(url, data: data))
	}

	func delete(_ urls: [URL]) async throws {
		try await expectDone(.delete(urls))
	}

	@discardableResult
	func rename(_ url: URL, to newName: String) async throws -> FileNode {
		try await expectNode(.renameItem(url, newName: newName))
	}

	@discardableResult
	func copyItem(from source: URL, to destination: URL) async throws -> FileNode {
		try await expectNode(.copyItem(from: source, to: destination))
	}

	@discardableResult
	func moveItem(from source: URL, to destination: URL) async throws -> FileNode {
		try await expectNode(.moveItem(from: source, to: destination))
	}

	func copyItems(_ urls: [URL], toDirectory destination: URL) async throws {
		try await expectDone(.copyItems(urls, toDirectory: destination))
	}

	func moveItems(_ urls: [URL], toDirectory destination: URL) async throws {
		try await expectDone(.moveItems(urls, toDirectory: destination))
	}

	@discardableResult
	func createSymbolicLink(at url: URL, destination: URL) async throws -> FileNode {
		try await expectNode(.createSymbolicLink(at: url, destination: destination))
	}

	@discardableResult
	func createHardLink(at url: URL, destination: URL) async throws -> FileNode {
		try await expectNode(.createHardLink(at: url, destination: destination))
	}

	func setPermissions(_ urls: [URL], posixPermissions: Int16, recursive: Bool = false) async throws {
		try await expectDone(.setPermissions(urls, posixPermissions: posixPermissions, recursive: recursive))
	}

	func calculateSize(of url: URL) async throws -> Int64 {
		try await expectSize(.calculateSize(url))
	}

	/// Zips `urls` (files and/or folders) into a new archive at `destination`.
	func compressItems(_ urls: [URL], to destination: URL) async throws {
		try await expectDone(.compressItems(urls, to: destination))
	}

	func extractArchive(_ archive: URL, toDirectory destination: URL) async throws {
		try await expectDone(.extractArchive(archive, toDirectory: destination))
	}

	/// Lists an archive's contents without extracting it to disk.
	func listArchiveEntries(_ archive: URL) async throws -> [ArchiveEntry] {
		try await expectArchiveEntries(.listArchiveEntries(archive))
	}

	func extractArchiveEntry(_ entryPath: String, from archive: URL, to destination: URL) async throws {
		try await expectDone(.extractArchiveEntry(archive: archive, entryPath: entryPath, to: destination))
	}

	func search(root: URL, query: String, includeHidden: Bool = false) async throws -> [FileNode] {
		try await expectNodes(.search(root: root, query: query, includeHidden: includeHidden))
	}

	func volumeInfo(for url: URL) async throws -> VolumeInfo {
		try await expectVolume(.volumeInfo(url))
	}

	// MARK: - Result unwrapping

	private func expectNodes(_ op: FileOperation) async throws -> [FileNode] {
		guard case .nodes(let nodes) = try await execute(op) else { throw FileSystemError.unexpectedResult }
		return nodes
	}

	private func expectNode(_ op: FileOperation) async throws -> FileNode {
		guard case .node(let node) = try await execute(op) else { throw FileSystemError.unexpectedResult }
		return node
	}

	private func expectData(_ op: FileOperation) async throws -> Data {
		guard case .data(let data) = try await execute(op) else { throw FileSystemError.unexpectedResult }
		return data
	}

	private func expectSize(_ op: FileOperation) async throws -> Int64 {
		guard case .size(let size) = try await execute(op) else { throw FileSystemError.unexpectedResult }
		return size
	}

	private func expectArchiveEntries(_ op: FileOperation) async throws -> [ArchiveEntry] {
		guard case .archiveEntries(let entries) = try await execute(op) else { throw FileSystemError.unexpectedResult }
		return entries
	}

	private func expectVolume(_ op: FileOperation) async throws -> VolumeInfo {
		guard case .volume(let info) = try await execute(op) else { throw FileSystemError.unexpectedResult }
		return info
	}

	@discardableResult
	private func expectDone(_ op: FileOperation) async throws -> Void {
		guard case .done = try await execute(op) else { throw FileSystemError.unexpectedResult }
	}
}
