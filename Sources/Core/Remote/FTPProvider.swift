import Foundation
import Network

/// An FTP (and, best-effort, FTPS — see the note in `ensureConnected()`) client built
/// directly on `Network.framework`, with no third-party dependency.
///
/// Shape of the protocol as implemented here: one long-lived *control* connection
/// (opened lazily on first use, reused for the provider's lifetime) carrying
/// line-oriented commands/replies per RFC 959, plus one short-lived *data*
/// connection per transfer or listing, opened against whatever host/port `PASV`
/// hands back. Directory listings prefer `MLSD` (RFC 3659) when the server
/// advertises it via `FEAT`, falling back to parsing `LIST`'s Unix-style output
/// otherwise.
///
/// `actor`-isolated so calls are implicitly queued onto one execution context —
/// but that alone is *not* sufficient for correctness, because actors are
/// reentrant: a method suspended at an `await` lets another call into this same
/// actor start running, which would let two commands interleave on the one control
/// connection. `CommandLock` closes that gap by holding a real FIFO lock across each
/// entire public method's command/reply sequence (including any PASV+transfer pair),
/// not just a single send/receive.
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

	/// One parsed control-connection reply — possibly multi-line (see
	/// `FTPSocket.readReply()`).
	struct FTPReply {
		let code: Int
		let lines: [String]

		/// The reply text with each line's leading `"NNN-"`/`"NNN "` code prefix
		/// stripped, rejoined with spaces — enough detail for an error message.
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
	/// Cached result of `FEAT`, populated on the first `listDirectory` call.
	private var features: Set<String>?
	/// Parses MLSD `modify=` timestamps. `DateFormatter` mutates internal state even
	/// while "just" parsing, so it's unsafe to share across threads — this needs to
	/// be a per-instance (not `static`) property, since two different `FTPProvider`
	/// actors (i.e. two different connections) can genuinely run in parallel on
	/// different threads, whereas everything reachable *within* one instance is
	/// already serialized by `commandLock`.
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

	// MARK: - RemoteFileProvider

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
			// A final-message send triggers Network.framework's half-close, which is
			// how the server learns "this file is complete" — FTP data transfers have
			// no length prefix, EOF is the only framing.
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
			// Servers typically answer a directory with 550 ("not a plain file" / "is
			// a directory") to DELE — retry as RMD rather than pre-flighting with a
			// stat just to learn what we're about to find out anyway.
			try require(try await self.sendCommand(socket, "RMD \(path)"), codes: [250])
		}
	}

	/// Overrides `RemoteFileProvider`'s default read+write+delete `move` with FTP's
	/// native rename verb — a real, atomic, single round-trip rename instead of a
	/// full file copy.
	func move(from source: String, to destination: String) async throws {
		try await perform { socket in
			try require(try await self.sendCommand(socket, "RNFR \(source)"), codes: [350])
			try require(try await self.sendCommand(socket, "RNTO \(destination)"), codes: [250])
		}
	}

	// `copy` is intentionally left on `RemoteFileProvider`'s default (read+write) —
	// FTP has no native server-side copy verb.

	// MARK: - Connection lifecycle

	/// Acquires `commandLock` for the duration of `body`, lazily connects/logs in if
	/// needed, then runs `body` against the live control socket. On any failure that
	/// isn't a plain protocol-level rejection (i.e. anything other than
	/// `FTPError.unexpectedReply`), the cached control socket is dropped so the next
	/// call reconnects from a clean slate instead of replaying commands against a
	/// socket that may be out of sync or already dead.
	private func perform<T>(_ body: (FTPSocket) async throws -> T) async throws -> T {
		await commandLock.acquire()
		do {
			let socket = try await ensureConnected()
			let result = try await body(socket)
			await commandLock.release()
			return result
		} catch {
			if let ftpError = error as? FTPError, case .unexpectedReply = ftpError {
				// The control connection is still in a known-good state — only the
				// requested operation was rejected.
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

		// NOTE ON FTPS: a byte-for-byte correct explicit FTPS (RFC 4217) client would
		// connect in the clear, send "AUTH TLS" here, and upgrade *this same* TCP
		// socket to TLS before USER/PASS. Network.framework doesn't expose a supported
		// way to do that upgrade — `NWParameters`/`NWProtocolTLS` are wired into a
		// connection at construction time, and there's no public API to hand an
		// already-open, already-connected `NWConnection` off to TLS mid-stream.
		// Rather than fake that handshake, `FTPSocket.init` below applies TLS
		// parameters from the very first byte whenever `useSecureConnection` is set,
		// for both this control connection and every per-transfer data connection.
		// In effect FTPS is treated as "implicit enough": the whole session runs over
		// TLS, just without the plaintext AUTH-TLS command/reply pair a strict RFC
		// 4217 trace would show. Servers that require that exact plaintext handshake
		// on port 21 will reject this; the far more common case of a server willing to
		// negotiate TLS immediately on connect will work fine.

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

	/// Sends one command line and returns its (possibly multi-line) reply. Only
	/// safe to call while `commandLock` is held — i.e. from inside `perform(_:)`.
	private func sendCommand(_ socket: FTPSocket, _ line: String) async throws -> FTPReply {
		try await socket.sendLine(line)
		return try await socket.readReply()
	}

	// MARK: - FEAT / MLSD / LIST

	private func featureSet(_ socket: FTPSocket) async throws -> Set<String> {
		if let features { return features }
		let reply = try await sendCommand(socket, "FEAT")
		var parsed: Set<String> = []
		if reply.code == 211 {
			// RFC 2389: first/last lines are the "211-Features:"/"211 End" framing;
			// everything between is one feature per line, conventionally indented
			// with a single leading space (e.g. " MLSD", " MLST type*;size*;").
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

	/// Parses `"227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)."` (RFC 959 §4.1.2) into
	/// a connectable host/port. Only the parenthesized numbers are used, so trailing
	/// server-specific commentary around them doesn't matter.
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
		// Order matters: PASV must be answered (so we know where to connect the data
		// socket) *before* the transfer command is sent, and the transfer command's
		// own reply must not be read until the data connection has been fully drained
		// — the server won't send its final 226 until it's done writing the listing.
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

	/// Parses one RFC 3659 MLSD line: semicolon-separated `fact=value` pairs, then a
	/// single space, then the filename verbatim to end of line (so a filename may
	/// itself contain spaces or semicolons without ambiguity).
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
		// "cdir"/"pdir" are the listing's self-referential entries for "this
		// directory"/"parent directory" — never real children, so skip them.
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

	/// Best-effort parse of one `ls -l`-style `LIST` line: `permissions links owner
	/// group size month day year-or-time name`. This is a convention, not a spec, so
	/// parsing is deliberately forgiving — a line that doesn't fit the common shape
	/// is skipped (`nil`) rather than guessed at. `modifiedAt` is always left `nil`:
	/// telling a year from an `HH:mm` in the eighth field depends on knowing the
	/// server's current date, which we don't, so any parse would just be a guess.
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

		// A symlink is listed as "linkname -> target"; keep just the link's own name.
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

/// Throws `FTPProvider.FTPError.unexpectedReply` unless `reply.code` is one of
/// `codes`. A free function (rather than a method) since it needs no actor state —
/// keeping it outside `FTPProvider` avoids every call site having to hop back onto
/// the actor just to check a status code.
@discardableResult
private func require(_ reply: FTPProvider.FTPReply, codes: Set<Int>) throws -> FTPProvider.FTPReply {
	guard codes.contains(reply.code) else {
		throw FTPProvider.FTPError.unexpectedReply(code: reply.code, message: reply.message)
	}
	return reply
}

/// A single TCP (optionally TLS-wrapped) connection to the FTP server, built on
/// `Network.framework`. Used for both `FTPProvider`'s long-lived control connection
/// and each short-lived, per-transfer data connection — the two uses differ only in
/// which methods callers drive it with: `readLine()`/`readReply()` for the
/// line-oriented control channel, `readAll()`/`sendFinal(_:)` for a data channel.
private final class FTPSocket {
	private let connection: NWConnection
	private let queue = DispatchQueue(label: "com.filzer.ftpsocket")
	/// Bytes received but not yet consumed by `readLine()` — a data-connection socket
	/// never calls `readLine()`, so this only ever holds control-channel overreads.
	private var buffer = Data()

	init(host: String, port: Int, useTLS: Bool) throws {
		guard port > 0, port <= 65535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
			throw FTPProvider.FTPError.invalidHost(host, port)
		}
		// See the FTPS note in `FTPProvider.ensureConnected()` — TLS, when requested,
		// is applied here at construction time rather than upgraded mid-stream.
		let parameters: NWParameters = useTLS ? .tls : .tcp
		connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
	}

	/// Starts the connection and suspends until it reaches `.ready`, or throws if it
	/// fails or is cancelled first.
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
					// .setup / .preparing / .waiting — not yet a terminal state.
					break
				}
			}
			connection.start(queue: queue)
		}
	}

	func close() {
		connection.cancel()
	}

	/// Sends one line, appending the `\r\n` terminator the control protocol requires.
	func sendLine(_ line: String) async throws {
		try await send(Data((line + "\r\n").utf8))
	}

	/// Sends `data` as a normal (non-final) message — used for control commands.
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

	/// Sends `data` marked as the connection's final message, which drives
	/// `Network.framework` to half-close the write side once it's flushed — this is
	/// how `STOR` signals end-of-file to the server, since FTP data transfers carry
	/// no length prefix and rely entirely on the connection closing to mark EOF.
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

	/// Reads one `\n`-terminated line off the connection (stripping a trailing `\r`),
	/// buffering any bytes read past the line ending for the next call.
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

	/// Reads one full FTP reply, correctly handling multi-line replies per RFC 959
	/// §4.2: a multi-line reply's first line is `"NNN-"` + text, and it doesn't end
	/// until a later line starts with the same code followed by a space (`"NNN "`) —
	/// every line in between is free-form server text, not necessarily itself
	/// prefixed with a reply code, so it must never be mistaken for the terminator.
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

	/// Reads off the connection until the server closes it (EOF), returning
	/// everything received. Used for `RETR`/`MLSD`/`LIST` data connections — none of
	/// these respond with a length prefix, so EOF is the only end-of-data signal.
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

	/// `NWConnection.receive` can, in principle, call back with no data, no
	/// completion, and no error (e.g. an intermediate zero-length delivery) — re-issue
	/// the receive in that case instead of guessing at EOF. Recursing here (rather
	/// than looping inside the completion handler itself) keeps each
	/// `CheckedContinuation` resumed exactly once, as required.
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

/// A FIFO async mutex serializing FTP control-connection exchanges end-to-end.
/// Plain actor isolation is not enough on its own: actors are reentrant, so
/// `FTPProvider`'s methods can still interleave with each other at `await` points,
/// and FTP's control channel is a strictly synchronous request/reply protocol that
/// cannot tolerate two exchanges (or someone else's PASV+transfer sequence) in
/// flight at once. Callers hold this lock for an entire public method's worth of
/// commands, not just one send/receive pair — see `FTPProvider.perform(_:)`.
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
