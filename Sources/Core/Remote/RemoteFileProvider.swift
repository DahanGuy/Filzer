import Foundation

struct RemoteItem {
	let name: String
	let path: String
	let isDirectory: Bool
	let size: Int64
	let modifiedAt: Date?
}

protocol RemoteFileProvider {
	func listDirectory(at path: String) async throws -> [RemoteItem]
	func readFile(at path: String) async throws -> Data
	func writeFile(at path: String, data: Data) async throws
	func createDirectory(at path: String) async throws
	func delete(at path: String) async throws
	func move(from source: String, to destination: String) async throws
	func copy(from source: String, to destination: String) async throws
}

extension RemoteFileProvider {
	func copy(from source: String, to destination: String) async throws {
		try await writeFile(at: destination, data: try await readFile(at: source))
	}

	func move(from source: String, to destination: String) async throws {
		try await copy(from: source, to: destination)
		try await delete(at: source)
	}
}
