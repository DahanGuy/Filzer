import Foundation

enum RootHelperError: Error {
	case launchFailed(String)
}

enum RootHelperProcess {
	enum Exit {
		case exited(Int32)
		case signaled(Int32)
	}

	struct Result {
		let exit: Exit
		let output: Data
		let errorOutput: Data
	}

	private typealias SetPersona = @convention(c) (UnsafeRawPointer, uid_t, UInt32) -> Int32
	private typealias SetPersonaID = @convention(c) (UnsafeRawPointer, uid_t) -> Int32

	private static let rootPersonaID: uid_t = 99
	private static let personaOverrideFlag: UInt32 = 1

	private final class DataBox: @unchecked Sendable {
		var data = Data()
	}

	static func spawnAsRoot(_ path: String, arguments: [String], input: Data?) throws -> Result {
		guard
			let handle = dlopen(nil, RTLD_NOW),
			let setPersonaSymbol = dlsym(handle, "posix_spawnattr_set_persona_np"),
			let setUIDSymbol = dlsym(handle, "posix_spawnattr_set_persona_uid_np"),
			let setGIDSymbol = dlsym(handle, "posix_spawnattr_set_persona_gid_np")
		else {
			throw RootHelperError.launchFailed("Spawning processes as root isn't supported on this system.")
		}
		let setPersona = unsafeBitCast(setPersonaSymbol, to: SetPersona.self)
		let setPersonaUID = unsafeBitCast(setUIDSymbol, to: SetPersonaID.self)
		let setPersonaGID = unsafeBitCast(setGIDSymbol, to: SetPersonaID.self)

		var attributes: posix_spawnattr_t? = nil
		guard posix_spawnattr_init(&attributes) == 0 else {
			throw RootHelperError.launchFailed("Couldn't prepare the root helper launch.")
		}
		defer { posix_spawnattr_destroy(&attributes) }

		var personaStatus: Int32 = 0
		withUnsafePointer(to: &attributes) { pointer in
			let raw = UnsafeRawPointer(pointer)
			personaStatus = setPersona(raw, rootPersonaID, personaOverrideFlag)
			if personaStatus == 0 { personaStatus = setPersonaUID(raw, 0) }
			if personaStatus == 0 { personaStatus = setPersonaGID(raw, 0) }
		}
		guard personaStatus == 0 else {
			throw RootHelperError.launchFailed("Couldn't request root privileges (error \(personaStatus)).")
		}

		let standardInput = try makePipe()
		let standardOutput = try makePipe()
		let standardError = try makePipe()

		var fileActions: posix_spawn_file_actions_t? = nil
		posix_spawn_file_actions_init(&fileActions)
		defer { posix_spawn_file_actions_destroy(&fileActions) }
		posix_spawn_file_actions_adddup2(&fileActions, standardInput.read, STDIN_FILENO)
		posix_spawn_file_actions_adddup2(&fileActions, standardOutput.write, STDOUT_FILENO)
		posix_spawn_file_actions_adddup2(&fileActions, standardError.write, STDERR_FILENO)

		let argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
		let environment: [UnsafeMutablePointer<CChar>?] = [strdup("PATH=/usr/bin:/bin:/usr/sbin:/sbin"), nil]
		defer {
			argv.forEach { free($0) }
			environment.forEach { free($0) }
		}

		var processID: pid_t = 0
		let spawnStatus = posix_spawn(&processID, path, &fileActions, &attributes, argv, environment)

		close(standardInput.read)
		close(standardOutput.write)
		close(standardError.write)

		guard spawnStatus == 0 else {
			close(standardInput.write)
			close(standardOutput.read)
			close(standardError.read)
			throw RootHelperError.launchFailed("Couldn't launch the root helper: \(String(cString: strerror(spawnStatus))).")
		}

		let output = DataBox()
		let errorOutput = DataBox()
		let group = DispatchGroup()
		let queue = DispatchQueue.global(qos: .userInitiated)
		queue.async(group: group) { output.data = readAll(from: standardOutput.read) }
		queue.async(group: group) { errorOutput.data = readAll(from: standardError.read) }
		queue.async(group: group) {
			if let input { writeAll(input, to: standardInput.write) }
			close(standardInput.write)
		}
		group.wait()
		close(standardOutput.read)
		close(standardError.read)

		var waitStatus: Int32 = 0
		while waitpid(processID, &waitStatus, 0) == -1 {
			if errno != EINTR {
				throw RootHelperError.launchFailed("Lost track of the root helper process.")
			}
		}
		let signalNumber = waitStatus & 0x7f
		let exit: Exit = signalNumber == 0 ? .exited((waitStatus >> 8) & 0xff) : .signaled(signalNumber)
		return Result(exit: exit, output: output.data, errorOutput: errorOutput.data)
	}

	private static func makePipe() throws -> (read: Int32, write: Int32) {
		var descriptors: [Int32] = [-1, -1]
		guard pipe(&descriptors) == 0 else {
			throw RootHelperError.launchFailed("Couldn't open a pipe to the root helper.")
		}
		for descriptor in descriptors {
			_ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
		}
		_ = fcntl(descriptors[1], F_SETNOSIGPIPE, 1)
		return (descriptors[0], descriptors[1])
	}

	private static func readAll(from descriptor: Int32) -> Data {
		var result = Data()
		let capacity = 1 << 16
		var buffer = [UInt8](repeating: 0, count: capacity)
		while true {
			let count = read(descriptor, &buffer, capacity)
			if count < 0 {
				if errno == EINTR { continue }
				break
			}
			if count == 0 { break }
			result.append(contentsOf: buffer[0..<count])
		}
		return result
	}

	private static func writeAll(_ data: Data, to descriptor: Int32) {
		data.withUnsafeBytes { raw in
			guard let base = raw.baseAddress else { return }
			var offset = 0
			while offset < raw.count {
				let written = write(descriptor, base + offset, raw.count - offset)
				if written < 0 {
					if errno == EINTR { continue }
					return
				}
				offset += written
			}
		}
	}
}
