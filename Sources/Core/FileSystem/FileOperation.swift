import Foundation

/// Every mutation or read Filzer can perform on a filesystem, expressed as data.
///
/// This enum — together with `FileOperationResult` and `FileSystemEngine.execute(_:)`
/// — is the single chokepoint every file action in the app funnels through. UI code
/// never touches `FileManager` directly; it calls the typed convenience methods in
/// `FileSystemEngine+Convenience.swift`, which all bottom out in one `execute(_:)` call.
/// Swap `FileSystem.current` for a different `FileSystemEngine` and every call site —
/// browsing, editing, archiving, everything — is redirected without a single UI change.
enum FileOperation {
	case listDirectory(URL, includeHidden: Bool)
	case nodeInfo(URL)
	case createDirectory(URL)
	case createFile(URL, contents: Data)
	case readFile(URL)
	case writeFile(URL, data: Data)
	case delete([URL])
	case renameItem(URL, newName: String)
	/// Copies exactly one item to an exact destination path (used by Duplicate).
	case copyItem(from: URL, to: URL)
	/// Moves exactly one item to an exact destination path (used by Rename-via-move, restore-from-Trash).
	case moveItem(from: URL, to: URL)
	/// Copies one or more items into a destination directory, keeping their names.
	case copyItems([URL], toDirectory: URL)
	/// Moves one or more items into a destination directory, keeping their names.
	case moveItems([URL], toDirectory: URL)
	case createSymbolicLink(at: URL, destination: URL)
	case createHardLink(at: URL, destination: URL)
	case setPermissions([URL], posixPermissions: Int16, recursive: Bool)
	case calculateSize(URL)
	case compressItems([URL], to: URL)
	case extractArchive(URL, toDirectory: URL, password: String?)
	case listArchiveEntries(URL, password: String?)
	case extractArchiveEntry(archive: URL, entryPath: String, to: URL, password: String?)
	case search(root: URL, query: String, includeHidden: Bool)
	case volumeInfo(URL)
}

/// The typed payload returned by `FileSystemEngine.execute(_:)`. Each `FileOperation`
/// case has exactly one matching result shape; mismatches are treated as engine bugs
/// (see `FileSystemError.unexpectedResult`), not user-facing errors.
enum FileOperationResult {
	case nodes([FileNode])
	case node(FileNode)
	case data(Data)
	case size(Int64)
	case archiveEntries([ArchiveEntry])
	case volume(VolumeInfo)
	case done
}
