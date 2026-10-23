import Foundation

struct RootHelperClient {
	let executablePath: String

	func ping() async throws -> Bool {
		let output = try await run(["ping"], context: URL(fileURLWithPath: "/"))
		return String(decoding: output, as: UTF8.self).contains("uid=0")
	}

	func list(_ url: URL, includeHidden: Bool) async throws -> [FileNode] {
		let output = try await run(["list", url.path, includeHidden ? "1" : "0"], context: url)
		let records = try decode([RootNodeRecord].self, from: output)
		return records.map { record in
			record.node(at: url.appendingPathComponent(record.name, isDirectory: record.kind == "directory"))
		}
	}

	func stat(_ url: URL) async throws -> FileNode {
		let output = try await run(["stat", url.path], context: url)
		return try decode(RootNodeRecord.self, from: output).node(at: url)
	}

	func read(_ url: URL) async throws -> Data {
		try await run(["read", url.path], context: url)
	}

	func write(_ data: Data, to url: URL, createNew: Bool) async throws {
		_ = try await run(["write", url.path] + (createNew ? ["new"] : []), input: data, context: url)
	}

	func makeDirectory(_ url: URL) async throws {
		_ = try await run(["mkdir", url.path], context: url)
	}

	func remove(_ url: URL) async throws {
		_ = try await run(["remove", url.path], context: url)
	}

	func move(from source: URL, to destination: URL) async throws {
		_ = try await run(["move", source.path, destination.path], context: destination)
	}

	func copy(from source: URL, to destination: URL) async throws {
		_ = try await run(["copy", source.path, destination.path], context: destination)
	}

	func makeSymbolicLink(at url: URL, destination: URL) async throws {
		_ = try await run(["symlink", url.path, destination.path], context: url)
	}

	func makeHardLink(at url: URL, destination: URL) async throws {
		_ = try await run(["hardlink", url.path, destination.path], context: url)
	}

	func setPermissions(_ mode: Int16, at url: URL, recursive: Bool) async throws {
		_ = try await run(["chmod", String(mode), url.path, recursive ? "1" : "0"], context: url)
	}

	func size(of url: URL) async throws -> Int64 {
		let output = try await run(["size", url.path], context: url)
		guard let size = Int64(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
			throw FileSystemError.unexpectedResult
		}
		return size
	}

	private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
		do {
			return try JSONDecoder().decode(type, from: data)
		} catch {
			throw RootHelperError.launchFailed("The root helper returned an unreadable response.")
		}
	}

	private func run(_ arguments: [String], input: Data? = nil, context: URL) async throws -> Data {
		let path = executablePath
		let result: RootHelperProcess.Result = try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				do {
					continuation.resume(returning: try RootHelperProcess.spawnAsRoot(path, arguments: arguments, input: input))
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
		switch result.exit {
		case .exited(0):
			return result.output
		case .exited(1):
			guard let record = try? JSONDecoder().decode(RootErrorRecord.self, from: result.errorOutput) else {
				throw RootHelperError.launchFailed("The root helper failed without a readable error.")
			}
			throw Self.fileSystemError(code: record.code, message: record.message, url: context)
		case .exited(let status):
			throw RootHelperError.launchFailed("The root helper exited with status \(status).")
		case .signaled(let signalNumber):
			throw RootHelperError.launchFailed("The root helper was stopped by signal \(signalNumber).")
		}
	}

	private static func fileSystemError(code: Int32, message: String, url: URL) -> FileSystemError {
		switch code {
		case ENOENT: return .notFound(url)
		case EEXIST: return .alreadyExists(url)
		case EACCES, EPERM: return .accessDenied(url)
		case ENOTDIR: return .notADirectory(url)
		default: return .operationFailed(message)
		}
	}
}
