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
		} catch let primaryError {
			if case FileSystemError.archivePasswordRequired = primaryError {
				throw primaryError
			}
			do {
				return try await fallback.execute(operation)
			} catch let fallbackError {
				if case FileSystemError.archivePasswordRequired = fallbackError {
					throw fallbackError
				}
				throw EngineError(
					primaryEngine: String(describing: type(of: primary)),
					primaryError: primaryError,
					fallbackEngine: String(describing: type(of: fallback)),
					fallbackError: fallbackError
				)
			}
		}
	}
}

struct EngineError: LocalizedError {
	let primaryEngine: String
	let primaryError: Error
	let fallbackEngine: String
	let fallbackError: Error

	var errorDescription: String? {
		let primaryDesc = (primaryError as? LocalizedError)?.errorDescription ?? primaryError.localizedDescription
		let fallbackDesc = (fallbackError as? LocalizedError)?.errorDescription ?? fallbackError.localizedDescription
		return "[\(primaryEngine)] \(primaryDesc)\n[\(fallbackEngine)] \(fallbackDesc)"
	}
}
