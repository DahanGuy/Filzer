import Foundation

final class MainFileSystemEngine: FileSystemEngine {
	private let primary: FileSystemEngine
	private let fallback: FileSystemEngine

	init(primary: FileSystemEngine, fallback: FileSystemEngine) {
		self.primary = primary
		self.fallback = fallback
	}

	func execute(_ operation: FileOperation) async throws -> FileOperationResult {
		if shouldSkipPrimary(for: operation) {
			return try await fallback.execute(operation)
		}
		do {
			return try await primary.execute(operation)
		} catch let error where Self.isPermissionError(error) {
			return try await fallback.execute(operation)
		}
	}

	private func shouldSkipPrimary(for operation: FileOperation) -> Bool {
		guard let url = Self.primaryLocalURL(for: operation) else { return false }
		let fm = FileManager.default
		if fm.isReadableFile(atPath: url.path) { return false }
		if fm.isReadableFile(atPath: url.deletingLastPathComponent().path) { return false }
		return true
	}

	private static func primaryLocalURL(for operation: FileOperation) -> URL? {
		let url: URL
		switch operation {
		case .listDirectory(let u, _), .nodeInfo(let u), .createDirectory(let u),
			 .createFile(let u, _), .readFile(let u), .writeFile(let u, _),
			 .calculateSize(let u), .volumeInfo(let u), .search(let u, _, _),
			 .createSymbolicLink(let u, _), .createHardLink(let u, _),
			 .renameItem(let u, _):
			url = u
		case .copyItem(let src, _), .moveItem(let src, _):
			url = src
		case .delete(let urls), .copyItems(let urls, _), .moveItems(let urls, _),
			 .compressItems(let urls, _), .setPermissions(let urls, _, _):
			guard let first = urls.first else { return nil }
			url = first
		case .extractArchive(let archive, _, _), .listArchiveEntries(let archive, _),
			 .extractArchiveEntry(let archive, _, _, _):
			url = archive
		}
		return RemoteURL.isRemote(url) ? nil : url
	}

	private static func isPermissionError(_ error: Error) -> Bool {
		if case FileSystemError.accessDenied = error { return true }
		let nsError = error as NSError
		if nsError.domain == NSCocoaErrorDomain {
			switch nsError.code {
			case CocoaError.fileReadNoPermission.rawValue,
				 CocoaError.fileWriteNoPermission.rawValue,
				 CocoaError.fileReadNoSuchFile.rawValue:
				return true
			default:
				return false
			}
		}
		if nsError.domain == NSPOSIXErrorDomain {
			return nsError.code == 1 || nsError.code == 13
		}
		return false
	}
}
