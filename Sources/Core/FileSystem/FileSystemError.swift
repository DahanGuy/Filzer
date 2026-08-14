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
		case .unexpectedResult:
			return "Something went wrong performing that action."
		}
	}
}
