import Foundation

/// A backend capable of performing file operations. `execute(_:)` is the single
/// chokepoint the whole app funnels through — see `FileOperation` for why that matters.
protocol FileSystemEngine {
	func execute(_ operation: FileOperation) async throws -> FileOperationResult
}

/// The app-wide entry point to the filesystem.
///
/// Every screen in Filzer talks to `FileSystem.current`, never to `FileManager`
/// directly. The default wiring tries the normal sandboxed engine first; if a
/// permission error is thrown (the sandbox blocking access), it automatically
/// retries through `ExploitFileSystemEngine`, which acquires a sandbox extension
/// via `bad_query` before each call. To swap out the entire stack — for a mock,
/// a different exploit backend, or a root helper — assign a new engine here once;
/// no other file needs to change.
enum FileSystem {
	static var current: FileSystemEngine = MainFileSystemEngine(
		primary: SandboxedFileSystemEngine(),
		fallback: ExploitFileSystemEngine()
	)
}
