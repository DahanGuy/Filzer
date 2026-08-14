import Foundation

/// One entry in a remote directory listing.
struct RemoteItem {
	let name: String
	/// The full remote path (not including the connection — that's implicit in which
	/// `RemoteFileProvider` you're talking to).
	let path: String
	let isDirectory: Bool
	let size: Int64
	let modifiedAt: Date?
}

/// What every remote backend (WebDAV, FTP, SMB) implements. Paths are plain strings in
/// whatever form that protocol natively uses — `SandboxedFileSystemEngine` is
/// responsible for translating `filzer-remote://` URLs to/from these paths; providers
/// never see a `URL`.
protocol RemoteFileProvider {
	func listDirectory(at path: String) async throws -> [RemoteItem]
	func readFile(at path: String) async throws -> Data
	func writeFile(at path: String, data: Data) async throws
	func createDirectory(at path: String) async throws
	func delete(at path: String) async throws
	func move(from source: String, to destination: String) async throws
	func copy(from source: String, to destination: String) async throws
}

/// Default implementations for providers whose protocol has no native rename/copy verb
/// (or where implementing one isn't worth the complexity yet) — falls back to
/// read+write / read+write+delete, which works for files on every provider.
extension RemoteFileProvider {
	func copy(from source: String, to destination: String) async throws {
		try await writeFile(at: destination, data: try await readFile(at: source))
	}

	func move(from source: String, to destination: String) async throws {
		try await copy(from: source, to: destination)
		try await delete(at: source)
	}
}
