import Foundation

/// Tries `primary` first; if it throws a permission error, retries the same
/// operation through `fallback`. Any non-permission error from `primary`
/// propagates normally — the fallback only fires for sandbox access denial,
/// not for "file not found", "already exists", or other legitimate failures.
///
/// This is the glue between `SandboxedFileSystemEngine` (which works inside
/// the sandbox but fails outside it) and `ExploitFileSystemEngine` (which
/// acquires sandbox extensions via `bad_query` before each call). The app
/// tries the fast, no-exploit path first and only reaches for the exploit
/// when actually blocked.
final class FallbackFileSystemEngine: FileSystemEngine {
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

	/// Checks whether an error is a permission/access denial that the exploit
	/// engine might be able to overcome, versus a legitimate failure (file not
	/// found, already exists, invalid name, etc.) that retrying won't fix.
	private static func isPermissionError(_ error: Error) -> Bool {
		// Our own explicit access-denied case
		if case FileSystemError.accessDenied = error { return true }

		// FileManager throws CocoaErrors for permission failures
		let nsError = error as NSError
		if nsError.domain == NSCocoaErrorDomain {
			switch nsError.code {
			case CocoaError.fileReadNoPermission.rawValue,
				 CocoaError.fileWriteNoPermission.rawValue,
				 CocoaError.fileReadNoSuchFile.rawValue:
				// fileReadNoSuchFile is included because the sandbox sometimes
				// reports "no such file" for paths it's actually blocking access
				// to — the file exists, but the sandbox makes it invisible.
				return true
			default:
				return false
			}
		}

		// Low-level POSIX errors from direct syscalls
		if nsError.domain == NSPOSIXErrorDomain {
			return nsError.code == 1 /* EPERM */ || nsError.code == 13 /* EACCES */
		}

		return false
	}
}
