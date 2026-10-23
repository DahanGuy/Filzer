import Foundation

struct RootNodeRecord: Codable {
	var name: String
	var kind: String
	var size: Int64
	var createdAt: Double?
	var modifiedAt: Double?
	var posixPermissions: Int16
	var ownerAccountName: String?
	var groupOwnerAccountName: String?
	var symbolicLinkDestination: String?
	var symbolicLinkTargetIsDirectory: Bool
	var isHidden: Bool
}

struct RootErrorRecord: Codable {
	var code: Int32
	var message: String
}

extension RootNodeRecord {
	init(node: FileNode) {
		name = node.name
		switch node.kind {
		case .file: kind = "file"
		case .directory: kind = "directory"
		case .symbolicLink: kind = "symlink"
		}
		size = node.size
		createdAt = node.createdAt?.timeIntervalSince1970
		modifiedAt = node.modifiedAt?.timeIntervalSince1970
		posixPermissions = node.posixPermissions
		ownerAccountName = node.ownerAccountName
		groupOwnerAccountName = node.groupOwnerAccountName
		symbolicLinkDestination = node.symbolicLinkDestination?.path
		symbolicLinkTargetIsDirectory = node.symbolicLinkTargetIsDirectory
		isHidden = node.isHidden
	}

	func node(at url: URL) -> FileNode {
		let nodeKind: FileNode.Kind
		switch kind {
		case "directory": nodeKind = .directory
		case "symlink": nodeKind = .symbolicLink
		default: nodeKind = .file
		}
		return FileNode(
			url: url, name: name, kind: nodeKind,
			size: size,
			createdAt: createdAt.map(Date.init(timeIntervalSince1970:)),
			modifiedAt: modifiedAt.map(Date.init(timeIntervalSince1970:)),
			posixPermissions: posixPermissions,
			ownerAccountName: ownerAccountName,
			groupOwnerAccountName: groupOwnerAccountName,
			symbolicLinkDestination: symbolicLinkDestination.map { URL(fileURLWithPath: $0) },
			symbolicLinkTargetIsDirectory: symbolicLinkTargetIsDirectory,
			isHidden: isHidden
		)
	}
}

enum RootHelperTool {
	static let launchArgument = "--filzer-root-helper"

	static func run(_ arguments: [String]) -> Never {
		signal(SIGPIPE, SIG_IGN)
		guard let command = arguments.first else { fail(EINVAL, "No command given.") }
		let rest = Array(arguments.dropFirst())
		switch command {
		case "ping": print("uid=\(getuid())")
		case "list": list(rest)
		case "stat": stat(rest)
		case "read": read(rest)
		case "write": write(rest)
		case "mkdir": makeDirectory(rest)
		case "remove": remove(rest)
		case "move": move(rest)
		case "copy": copy(rest)
		case "symlink": makeSymbolicLink(rest)
		case "hardlink": makeHardLink(rest)
		case "chmod": changeMode(rest)
		case "size": size(rest)
		default: fail(EINVAL, "Unknown command \"\(command)\".")
		}
		exit(0)
	}

	private static func list(_ arguments: [String]) {
		require(arguments, 1, usage: "list <path> [1 to include hidden]")
		let includeHidden = arguments.count > 1 && arguments[1] == "1"
		do {
			let nodes = try DirectoryLister.children(of: URL(fileURLWithPath: arguments[0]), includeHidden: includeHidden)
			emitJSON(nodes.map(RootNodeRecord.init(node:)))
		} catch {
			failWith(error)
		}
	}

	private static func stat(_ arguments: [String]) {
		require(arguments, 1, usage: "stat <path>")
		emitNode(at: arguments[0])
	}

	private static func read(_ arguments: [String]) {
		require(arguments, 1, usage: "read <path>")
		let descriptor = open(arguments[0], O_RDONLY)
		if descriptor < 0 { failErrno() }
		let capacity = 1 << 16
		var buffer = [UInt8](repeating: 0, count: capacity)
		while true {
			let count = Darwin.read(descriptor, &buffer, capacity)
			if count < 0 {
				if errno == EINTR { continue }
				failErrno("Couldn't read the file")
			}
			if count == 0 { break }
			let succeeded = buffer.withUnsafeBytes { writeAll(STDOUT_FILENO, $0.baseAddress!, count) }
			if !succeeded { exit(2) }
		}
		close(descriptor)
	}

	private static func write(_ arguments: [String]) {
		require(arguments, 1, usage: "write <path> [new]")
		if arguments.count > 1 && arguments[1] == "new" {
			writeNewFile(arguments[0])
			emitNode(at: arguments[0])
		} else {
			replaceFile(arguments[0])
		}
	}

	private static func makeDirectory(_ arguments: [String]) {
		require(arguments, 1, usage: "mkdir <path>")
		if lstatInfo(arguments[0]) != nil { fail(EEXIST, "\"\(arguments[0])\" already exists.") }
		var missing: [String] = []
		var current = arguments[0]
		while current != "/", lstatInfo(current) == nil {
			missing.append(current)
			current = parentPath(of: current)
		}
		for directory in missing.reversed() {
			if mkdir(directory, 0o755) != 0 { failErrno() }
			adoptParentOwner(directory)
		}
		emitNode(at: arguments[0])
	}

	private static func remove(_ arguments: [String]) {
		require(arguments, 1, usage: "remove <path>")
		do {
			try FileManager.default.removeItem(atPath: arguments[0])
		} catch {
			failWith(error)
		}
	}

	private static func move(_ arguments: [String]) {
		require(arguments, 2, usage: "move <source> <destination>")
		if lstatInfo(arguments[1]) != nil { fail(EEXIST, "\"\(arguments[1])\" already exists.") }
		do {
			try FileManager.default.moveItem(atPath: arguments[0], toPath: arguments[1])
		} catch {
			failWith(error)
		}
		emitNode(at: arguments[1])
	}

	private static func copy(_ arguments: [String]) {
		require(arguments, 2, usage: "copy <source> <destination>")
		if lstatInfo(arguments[1]) != nil { fail(EEXIST, "\"\(arguments[1])\" already exists.") }
		do {
			try FileManager.default.copyItem(atPath: arguments[0], toPath: arguments[1])
		} catch {
			failWith(error)
		}
		if let owner = parentOwner(of: arguments[1]) {
			chownTree(arguments[1], uid: owner.uid, gid: owner.gid)
		}
		emitNode(at: arguments[1])
	}

	private static func makeSymbolicLink(_ arguments: [String]) {
		require(arguments, 2, usage: "symlink <path> <destination>")
		do {
			try FileManager.default.createSymbolicLink(atPath: arguments[0], withDestinationPath: arguments[1])
		} catch {
			failWith(error)
		}
		adoptParentOwner(arguments[0])
		emitNode(at: arguments[0])
	}

	private static func makeHardLink(_ arguments: [String]) {
		require(arguments, 2, usage: "hardlink <path> <existing>")
		do {
			try FileManager.default.linkItem(atPath: arguments[1], toPath: arguments[0])
		} catch {
			failWith(error)
		}
		emitNode(at: arguments[0])
	}

	private static func changeMode(_ arguments: [String]) {
		require(arguments, 3, usage: "chmod <mode> <path> <1 for recursive>")
		guard let mode = Int16(arguments[0]) else { fail(EINVAL, "\"\(arguments[0])\" isn't a valid mode.") }
		do {
			try applyMode(mode, to: arguments[1], recursive: arguments[2] == "1")
		} catch {
			failWith(error)
		}
	}

	private static func size(_ arguments: [String]) {
		require(arguments, 1, usage: "size <path>")
		if lstatInfo(arguments[0]) == nil { fail(ENOENT, "\"\(arguments[0])\" couldn't be found.") }
		print(totalSize(of: arguments[0]))
	}

	private static func writeNewFile(_ path: String) {
		let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
		if descriptor < 0 { failErrno() }
		let streamError = streamStdin(into: descriptor)
		close(descriptor)
		if streamError != 0 {
			unlink(path)
			fail(streamError, String(cString: strerror(streamError)))
		}
		adoptParentOwner(path)
	}

	private static func replaceFile(_ path: String) {
		var targetPath = path
		if let info = lstatInfo(path), (info.st_mode & S_IFMT) == S_IFLNK {
			targetPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
		}
		let existing = lstatInfo(targetPath)
		let temporaryPath = parentPath(of: targetPath) + "/.filzer-write-" + UUID().uuidString
		let descriptor = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		if descriptor < 0 { failErrno() }
		let streamError = streamStdin(into: descriptor)
		if streamError != 0 {
			close(descriptor)
			unlink(temporaryPath)
			fail(streamError, String(cString: strerror(streamError)))
		}
		_ = fchmod(descriptor, existing.map { $0.st_mode & 0o7777 } ?? 0o644)
		if let existing {
			_ = fchown(descriptor, existing.st_uid, existing.st_gid)
		} else if let owner = parentOwner(of: targetPath) {
			_ = fchown(descriptor, owner.uid, owner.gid)
		}
		close(descriptor)
		if rename(temporaryPath, targetPath) != 0 {
			let code = errno
			unlink(temporaryPath)
			fail(code, String(cString: strerror(code)))
		}
	}

	private static func streamStdin(into descriptor: Int32) -> Int32 {
		let capacity = 1 << 16
		var buffer = [UInt8](repeating: 0, count: capacity)
		while true {
			let count = Darwin.read(STDIN_FILENO, &buffer, capacity)
			if count < 0 {
				if errno == EINTR { continue }
				return errno
			}
			if count == 0 { return 0 }
			let succeeded = buffer.withUnsafeBytes { writeAll(descriptor, $0.baseAddress!, count) }
			if !succeeded { return errno }
		}
	}

	private static func totalSize(of path: String) -> Int64 {
		guard let info = lstatInfo(path) else { return 0 }
		guard isDirectoryMode(info) else { return Int64(info.st_size) }
		guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return 0 }
		return names.reduce(Int64(0)) { $0 + totalSize(of: path + "/" + $1) }
	}

	private static func applyMode(_ mode: Int16, to path: String, recursive: Bool) throws {
		try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path)
		guard recursive, let info = lstatInfo(path), isDirectoryMode(info) else { return }
		for name in try FileManager.default.contentsOfDirectory(atPath: path) {
			try applyMode(mode, to: path + "/" + name, recursive: true)
		}
	}

	private static func chownTree(_ path: String, uid: uid_t, gid: gid_t) {
		_ = lchown(path, uid, gid)
		guard let info = lstatInfo(path), isDirectoryMode(info) else { return }
		guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
		for name in names {
			chownTree(path + "/" + name, uid: uid, gid: gid)
		}
	}

	private static func adoptParentOwner(_ path: String) {
		guard let owner = parentOwner(of: path) else { return }
		_ = lchown(path, owner.uid, owner.gid)
	}

	private static func parentOwner(of path: String) -> (uid: uid_t, gid: gid_t)? {
		guard let info = lstatInfo(parentPath(of: path)) else { return nil }
		return (info.st_uid, info.st_gid)
	}

	private static func parentPath(of path: String) -> String {
		let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
		return parent.isEmpty ? "/" : parent
	}

	private static func lstatInfo(_ path: String) -> Darwin.stat? {
		var info = Darwin.stat()
		return lstat(path, &info) == 0 ? info : nil
	}

	private static func isDirectoryMode(_ info: Darwin.stat) -> Bool {
		(info.st_mode & S_IFMT) == S_IFDIR
	}

	private static func require(_ arguments: [String], _ count: Int, usage: String) {
		if arguments.count < count { fail(EINVAL, "Usage: \(usage)") }
	}

	private static func emitNode(at path: String) {
		do {
			emitJSON(RootNodeRecord(node: try FileNode.make(at: URL(fileURLWithPath: path))))
		} catch {
			failWith(error)
		}
	}

	private static func emitJSON<T: Encodable>(_ value: T) {
		do {
			emit(try encoder.encode(value))
		} catch {
			fail(EIO, "Couldn't encode the result: \(error.localizedDescription)")
		}
	}

	private static func emit(_ data: Data) {
		let succeeded = data.withUnsafeBytes { raw -> Bool in
			guard let base = raw.baseAddress else { return true }
			return writeAll(STDOUT_FILENO, base, raw.count)
		}
		if !succeeded { exit(2) }
	}

	private static func writeAll(_ descriptor: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Bool {
		var offset = 0
		while offset < count {
			let written = Darwin.write(descriptor, bytes + offset, count - offset)
			if written < 0 {
				if errno == EINTR { continue }
				return false
			}
			offset += written
		}
		return true
	}

	private static func fail(_ code: Int32, _ message: String) -> Never {
		if var data = try? encoder.encode(RootErrorRecord(code: code, message: message)) {
			data.append(0x0A)
			data.withUnsafeBytes { raw in
				if let base = raw.baseAddress { _ = writeAll(STDERR_FILENO, base, raw.count) }
			}
		}
		exit(1)
	}

	private static func failErrno(_ context: String? = nil) -> Never {
		let code = errno
		let reason = String(cString: strerror(code))
		fail(code, context.map { "\($0): \(reason)" } ?? reason)
	}

	private static func failWith(_ error: Error) -> Never {
		fail(posixCode(of: error), error.localizedDescription)
	}

	private static func posixCode(of error: Error) -> Int32 {
		let nsError = error as NSError
		if nsError.domain == NSPOSIXErrorDomain { return Int32(nsError.code) }
		if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
			return Int32(underlying.code)
		}
		switch nsError.code {
		case CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue: return ENOENT
		case CocoaError.fileWriteFileExists.rawValue: return EEXIST
		case CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue: return EACCES
		default: return 0
		}
	}

	private static let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return encoder
	}()
}
