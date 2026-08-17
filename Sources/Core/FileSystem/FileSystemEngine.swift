import Foundation

protocol FileSystemEngine {
	func execute(_ operation: FileOperation) async throws -> FileOperationResult
}

enum FileSystem {
	static var current: FileSystemEngine = SandboxedFileSystemEngine()
}
