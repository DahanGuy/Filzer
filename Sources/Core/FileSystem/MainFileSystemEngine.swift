import Foundation

final class MainFileSystemEngine: FileSystemEngine {
	private let primary: FileSystemEngine
	private let fallback: FileSystemEngine

	init(primary: FileSystemEngine, fallback: FileSystemEngine) {
		self.primary = primary
		self.fallback = fallback
	}

	func execute(_ operation: FileOperation) async throws -> FileOperationResult {
		do {
			return try await primary.execute(operation)
		} catch let error where Self.isPermissionError(error) {
			return try await fallback.execute(operation)
		}
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
