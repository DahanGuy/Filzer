import Foundation

enum FileOperation {
	case listDirectory(URL, includeHidden: Bool)
	case nodeInfo(URL)
	case createDirectory(URL)
	case createFile(URL, contents: Data)
	case readFile(URL)
	case writeFile(URL, data: Data)
	case delete([URL])
	case renameItem(URL, newName: String)
	case copyItem(from: URL, to: URL)
	case moveItem(from: URL, to: URL)
	case copyItems([URL], toDirectory: URL)
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

enum FileOperationResult {
	case nodes([FileNode])
	case node(FileNode)
	case data(Data)
	case size(Int64)
	case archiveEntries([ArchiveEntry])
	case volume(VolumeInfo)
	case done
}
