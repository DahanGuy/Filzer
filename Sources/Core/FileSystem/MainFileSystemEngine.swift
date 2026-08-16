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
			do {
				return try await fallback.execute(operation)
			} catch {
				throw primaryError
			}
		}
	}
}
