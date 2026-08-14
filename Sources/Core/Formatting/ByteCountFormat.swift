import Foundation

/// Shared byte-count formatting so every screen (rows, Info panel, storage usage)
/// renders sizes identically.
enum ByteCountFormat {
	private static let formatter: ByteCountFormatter = {
		let formatter = ByteCountFormatter()
		formatter.countStyle = .file
		return formatter
	}()

	static func string(for bytes: Int64) -> String {
		formatter.string(fromByteCount: max(0, bytes))
	}
}
