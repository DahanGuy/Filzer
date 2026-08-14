import Foundation

/// A backend capable of performing file operations. `execute(_:)` is the single
/// chokepoint the whole app funnels through — see `FileOperation` for why that matters.
protocol FileSystemEngine {
	func execute(_ operation: FileOperation) async throws -> FileOperationResult
}

/// The app-wide entry point to the filesystem.
///
/// Every screen in Filzer talks to `FileSystem.current`, never to `FileManager`
/// directly. To point the whole app at a different backend — a jailbreak-level root
/// helper, an MDM-provided container, a mock for previews — assign a new
/// `FileSystemEngine` here once; no other file needs to change.
enum FileSystem {
	static var current: FileSystemEngine = SandboxedFileSystemEngine()
}
