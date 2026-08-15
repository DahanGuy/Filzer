import Foundation

/// Errors surfaced by `FileSystemEngine` implementations and shown directly in the UI,
/// so every case carries a human-readable description.
enum FileSystemError: LocalizedError {
	case notFound(URL)
	case alreadyExists(URL)
	case accessDenied(URL)
	case invalidName(String)
	case notADirectory(URL)
	case operationFailed(String)
	case cancelled
	case unsupported(String)
	/// Thrown by `ArchiveService.listEntries`/`extract`/`extractEntry` when an archive
	/// needs a password that's missing or wrong - the one `FileSystemError` case the UI
	/// (`ArchiveBrowserView`) specifically catches to prompt for a password and retry,
	/// rather than just surfacing it as a dead-end failure.
	case archivePasswordRequired(URL)
	/// An engine returned a result shape that doesn't match the operation it was asked
	/// to perform — always a bug in that `FileSystemEngine`, never a user-facing failure.
	case unexpectedResult

	var errorDescription: String? {
		switch self {
		case .notFound(let url):
			return "\"\(url.lastPathComponent)\" couldn't be found."
		case .alreadyExists(let url):
			return "\"\(url.lastPathComponent)\" already exists in this location."
		case .accessDenied(let url):
			return "Filzer doesn't have permission to access \"\(url.lastPathComponent)\"."
		case .invalidName(let name):
			return "\"\(name)\" isn't a valid name."
		case .notADirectory(let url):
			return "\"\(url.lastPathComponent)\" isn't a folder."
		case .operationFailed(let message):
			return message
		case .cancelled:
			return "The operation was cancelled."
		case .unsupported(let message):
			return message
		case .archivePasswordRequired(let url):
			return "\"\(url.lastPathComponent)\" is password-protected."
		case .unexpectedResult:
			return "Something went wrong performing that action."
		}
	}
}
