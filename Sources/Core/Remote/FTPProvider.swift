import Foundation
import Network

actor FTPProvider: RemoteFileProvider {
	enum FTPError: LocalizedError {
		case connectionClosed
		case malformedReply(String)
		case unexpectedReply(code: Int, message: String)
		case invalidPassiveModeReply(String)
		case invalidHost(String, Int)

		var errorDescription: String? {
			switch self {
			case .connectionClosed:
				return "The FTP server closed the connection unexpectedly."
			case .malformedReply(let line):
				return "The FTP server sent a reply Filzer couldn't parse: \"\(line)\"."
			case .unexpectedReply(let code, let message):
				return "FTP server error \(code): \(message)"
			case .invalidPassiveModeReply(let text):
				return "Couldn't parse the FTP server's passive-mode reply: \"\(text)\"."
			case .invalidHost(let host, let port):
				return "\"\(host):\(port)\" isn't a valid FTP server address."
			}
		}
	}

	struct FTPReply {
		let code: Int
		let lines: [String]

		var message: String {
			lines.map { line in
				guard line.count > 4 else { return line }
				return String(line[line.index(line.startIndex, offsetBy: 4)...])
			}.joined(separator: " ")
		}
	}

	private let connection: RemoteConnection
	private let password: String
	private let commandLock = CommandLock()
	private var controlSocket: FTPSocket?
	private var features: Set<String>?
	private let mlsdDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyyMMddHHmmss"
		formatter.timeZone = TimeZone(identifier: "UTC")
		return formatter
	}()

	init(connection: RemoteConnection, password: String) {
		self.connection = connection
		self.password = password
	}

	deinit {
		controlSocket?.close()
	}

	func listDirectory(at path: String) async throws -> [RemoteItem] {
		try await perform { socket in
			let supportsMLSD = try await self.featureSet(socket).contains("MLSD")
			return supportsMLSD
				? try await self.listDirectoryMLSD(socket, path: path)
				: try await self.listDirectoryLIST(socket, path: path)
		}
	}

	func readFile(at path: String) async throws -> Data {
		try await perform { socket in
			let (host, port) = try await self.enterPassiveMode(socket)
			let dataSocket = try FTPSocket(host: host, port: port, useTLS: self.connection.useSecureConnection)
			try await dataSocket.open()
			try require(try await self.sendCommand(socket, "RETR \(path)"), codes: [125, 150])
			let data = try await dataSocket.readAll()
			dataSocket.close()
			try require(try await socket.readReply(), codes: [226, 250])
			return data
		}
	}

	func writeFile(at path: String, data: Data) async throws {
		try await perform { socket in
			let (host, port) = try await self.enterPassiveMode(socket)
			let dataSocket = try FTPSocket(host: host, port: port, useTLS: self.connection.useSecureConnection)
			try await dataSocket.open()
			try require(try await self.sendCommand(socket, "STOR \(path)"), codes: [125, 150])
			try await dataSocket.sendFinal(data)
			dataSocket.close()
			try require(try await socket.readReply(), codes: [226, 250])
		}
	}

	func createDirectory(at path: String) async throws {
		try await perform { socket in
			try require(try await self.sendCommand(socket, "MKD \(path)"), codes: [257])
		}
	}

	func delete(at path: String) async throws {
		try await perform { socket in
			let reply = try await self.sendCommand(socket, "DELE \(path)")
			guard reply.code != 250 else { return }
			try require(try await self.sendCommand(socket, "RMD \(path)"), codes: [250])
		}
	}

	func move(from source: String, to destination: String) async throws {
		try await perform { socket in
			try require(try await self.sendCommand(socket, "RNFR \(source)"), codes: [350])
			try require(try await self.sendCommand(socket, "RNTO \(destination)"), codes: [250])
		}
	}

	private func perform<T>(_ body: (FTPSocket) async throws -> T) async throws -> T {
		await commandLock.acquire()
		do {
			let socket = try await ensureConnected()
			let result = try await body(socket)
			await commandLock.release()
			return result
		} catch {
			if let ftpError = error as? FTPError, case .unexpectedReply = ftpError {
			} else {
				controlSocket?.close()
				controlSocket = nil
			}
			await commandLock.release()
			throw error
		}
	}

	private func ensureConnected() async throws -> FTPSocket {
		if let controlSocket { return controlSocket }

		let socket = try FTPSocket(host: connection.host, port: connection.port, useTLS: connection.useSecureConnection)
		try await socket.open()
		try require(try await socket.readReply(), codes: [220])

		let userReply = try await sendCommand(socket, "USER \(connection.username)")
		if userReply.code == 331 {
			try require(try await sendCommand(socket, "PASS \(password)"), codes: [230])
		} else {
			try require(userReply, codes: [230])
		}
		try require(try await sendCommand(socket, "TYPE I"), codes: [200])

		controlSocket = socket
		return socket
	}

	private func sendCommand(_ socket: FTPSocket, _ line: String) async throws -> FTPReply {
		try await socket.sendLine(line)
		return try await socket.readReply()
	}

	private func featureSet(_ socket: FTPSocket) async throws -> Set<String> {
		if let features { return features }
		let reply = try await sendCommand(socket, "FEAT")
		var parsed: Set<String> = []
		if reply.code == 211 {
			for line in reply.lines.dropFirst().dropLast() {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				let name = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
				parsed.insert(name.uppercased())
			}
		}
		features = parsed
		return parsed
	}

	private func enterPassiveMode(_ socket: FTPSocket) async throws -> (host: String, port: Int) {
		let reply = try await sendCommand(socket, "PASV")
		try require(reply, codes: [227])
		return try parsePassiveReply(reply.message)
	}

	private func parsePassiveReply(_ text: String) throws -> (host: String, port: Int) {
		guard
			let open = text.firstIndex(of: "("),
			let close = text.firstIndex(of: ")"),
			open < close
		else {
			throw FTPError.invalidPassiveModeReply(text)
		}
		let numbers = text[text.index(after: open)..<close]
			.split(separator: ",")
			.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
		guard numbers.count == 6 else {
			throw FTPError.invalidPassiveModeReply(text)
		}
		let host = "\(numbers[0]).\(numbers[1]).\(numbers[2]).\(numbers[3])"
		let port = numbers[4] * 256 + numbers[5]
		return (host, port)
	}

	private func listDirectoryMLSD(_ socket: FTPSocket, path: String) async throws -> [RemoteItem] {
		let (host, port) = try await enterPassiveMode(socket)
		let dataSocket = try FTPSocket(host: host, port: port, useTLS: connection.useSecureConnection)
		try await dataSocket.open()
		try require(try await sendCommand(socket, "MLSD \(path)"), codes: [125, 150])
		let data = try await dataSocket.readAll()
		dataSocket.close()
		try require(try await socket.readReply(), codes: [226, 250])

		let text = String(decoding: data, as: UTF8.self)
		return text.split(separator: "\n").compactMap { parseMLSDLine(String($0), directory: path) }
	}

	private func parseMLSDLine(_ rawLine: String, directory: String) -> RemoteItem? {
		var line = rawLine
		if line.hasSuffix("\r") { line.removeLast() }
		guard let spaceIndex = line.firstIndex(of: " ") else { return nil }

		let factsText = line[line.startIndex..<spaceIndex]
		let filename = String(line[line.index(after: spaceIndex)...])
		guard !filename.isEmpty else { return nil }

		var facts: [String: String] = [:]
		for fact in factsText.split(separator: ";") {
			guard let equals = fact.firstIndex(of: "=") else { continue }
			facts[fact[fact.startIndex..<equals].lowercased()] = String(fact[fact.index(after: equals)...])
		}

		let type = (facts["type"] ?? "file").lowercased()
		guard type != "cdir", type != "pdir" else { return nil }

		let size = facts["size"].flatMap(Int64.init) ?? 0
		let modifiedAt = facts["modify"]
			.flatMap { $0.split(separator: ".").first.map(String.init) }
			.flatMap { mlsdDateFormatter.date(from: $0) }

		return RemoteItem(
			name: filename,
			path: remotePath(directory, appending: filename),
			isDirectory: type == "dir",
			size: size,
			modifiedAt: modifiedAt
		)
	}

	private func listDirectoryLIST(_ socket: FTPSocket, path: String) async throws -> [RemoteItem] {
		let (host, port) = try await enterPassiveMode(socket)
		let dataSocket = try FTPSocket(host: host, port: port, useTLS: connection.useSecureConnection)
		try await dataSocket.open()
		try require(try await sendCommand(socket, "LIST \(path)"), codes: [125, 150])
		let data = try await dataSocket.readAll()
		dataSocket.close()
		try require(try await socket.readReply(), codes: [226, 250])

		let text = String(decoding: data, as: UTF8.self)
		return text.split(separator: "\n").compactMap { parseUnixListLine(String($0), directory: path) }
	}

	private func parseUnixListLine(_ rawLine: String, directory: String) -> RemoteItem? {
		var line = rawLine
		if line.hasSuffix("\r") { line.removeLast() }
		guard let kind = line.first, kind == "d" || kind == "-" || kind == "l" else { return nil }

		var remaining = Substring(line)
		var fields: [Substring] = []
		for _ in 0..<8 {
			remaining = remaining.drop { $0 == " " || $0 == "\t" }
			guard let separator = remaining.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
			fields.append(remaining[remaining.startIndex..<separator])
			remaining = remaining[separator...]
		}
		let name = String(remaining.drop { $0 == " " || $0 == "\t" })
		guard !name.isEmpty, name != ".", name != ".." else { return nil }

		var displayName = name
		if kind == "l", let arrowRange = name.range(of: " -> ") {
			displayName = String(name[name.startIndex..<arrowRange.lowerBound])
		}
		let size = Int64(fields[4]) ?? 0

		return RemoteItem(
			name: displayName,
			path: remotePath(directory, appending: displayName),
			isDirectory: kind == "d",
			size: size,
			modifiedAt: nil
		)
	}

	private func remotePath(_ directory: String, appending name: String) -> String {
		directory.hasSuffix("/") ? directory + name : directory + "/" + name
	}
}

@discardableResult
private func require(_ reply: FTPProvider.FTPReply, codes: Set<Int>) throws -> FTPProvider.FTPReply {
	guard codes.contains(reply.code) else {
		throw FTPProvider.FTPError.unexpectedReply(code: reply.code, message: reply.message)
	}
	return reply
}

private final class FTPSocket {
	private let connection: NWConnection
	private let queue = DispatchQueue(label: "com.filzer.ftpsocket")
	private var buffer = Data()

	init(host: String, port: Int, useTLS: Bool) throws {
		guard port > 0, port <= 65535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
			throw FTPProvider.FTPError.invalidHost(host, port)
		}
		let parameters: NWParameters = useTLS ? .tls : .tcp
		connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
	}

	func open() async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			var resumed = false
			connection.stateUpdateHandler = { state in
				guard !resumed else { return }
				switch state {
				case .ready:
					resumed = true
					continuation.resume()
				case .failed(let error):
					resumed = true
					continuation.resume(throwing: error)
				case .cancelled:
					resumed = true
					continuation.resume(throwing: FTPProvider.FTPError.connectionClosed)
				default:
					break
				}
			}
			connection.start(queue: queue)
		}
	}

	func close() {
		connection.cancel()
	}

	func sendLine(_ line: String) async throws {
		try await send(Data((line + "\r\n").utf8))
	}

	func send(_ data: Data) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			connection.send(content: data, completion: .contentProcessed { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			})
		}
	}

	func sendFinal(_ data: Data) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			})
		}
	}

	func readLine() async throws -> String {
		while true {
			if let newlineIndex = buffer.firstIndex(of: 0x0A) {
				let lineData = buffer[buffer.startIndex..<newlineIndex]
				var line = String(decoding: lineData, as: UTF8.self)
				if line.hasSuffix("\r") { line.removeLast() }
				buffer = Data(buffer[buffer.index(after: newlineIndex)...])
				return line
			}
			let chunk = try await receiveChunk()
			if chunk.isEmpty {
				throw FTPProvider.FTPError.connectionClosed
			}
			buffer.append(chunk)
		}
	}

	func readReply() async throws -> FTPProvider.FTPReply {
		let firstLine = try await readLine()
		guard firstLine.count >= 3, let code = Int(firstLine.prefix(3)) else {
			throw FTPProvider.FTPError.malformedReply(firstLine)
		}
		var lines = [firstLine]
		let fourthCharIndex = firstLine.index(firstLine.startIndex, offsetBy: 3)
		let isMultiline = firstLine.count > 3 && firstLine[fourthCharIndex] == "-"
		if isMultiline {
			let terminator = "\(code) "
			while true {
				let line = try await readLine()
				lines.append(line)
				if line.hasPrefix(terminator) {
					break
				}
			}
		}
		return FTPProvider.FTPReply(code: code, lines: lines)
	}

	func readAll() async throws -> Data {
		var result = buffer
		buffer = Data()
		while true {
			let chunk = try await receiveChunk()
			if chunk.isEmpty { break }
			result.append(chunk)
		}
		return result
	}

	private func receiveChunk(maxLength: Int = 65536) async throws -> Data {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
			receiveLoop(maxLength: maxLength, continuation: continuation)
		}
	}

	private func receiveLoop(maxLength: Int, continuation: CheckedContinuation<Data, Error>) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { [weak self] data, _, isComplete, error in
			if let error {
				continuation.resume(throwing: error)
			} else if let data, !data.isEmpty {
				continuation.resume(returning: data)
			} else if isComplete {
				continuation.resume(returning: Data())
			} else {
				self?.receiveLoop(maxLength: maxLength, continuation: continuation)
			}
		}
	}
}

private actor CommandLock {
	private var isLocked = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func acquire() async {
		if !isLocked {
			isLocked = true
			return
		}
		await withCheckedContinuation { waiters.append($0) }
	}

	func release() {
		if waiters.isEmpty {
			isLocked = false
		} else {
			waiters.removeFirst().resume()
		}
	}
}
