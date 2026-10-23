import Foundation

signal(SIGPIPE, SIG_IGN)

func writeAll(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Bool {
	var offset = 0
	while offset < count {
		let written = write(fd, bytes + offset, count - offset)
		if written < 0 {
			if errno == EINTR { continue }
			return false
		}
		offset += written
	}
	return true
}

func emit(_ data: Data) {
	let succeeded = data.withUnsafeBytes { raw -> Bool in
		guard let base = raw.baseAddress else { return true }
		return writeAll(STDOUT_FILENO, base, raw.count)
	}
	if !succeeded { exit(2) }
}

func emitJSON<T: Encodable>(_ value: T) {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	do {
		emit(try encoder.encode(value))
	} catch {
		fail(EIO, "Couldn't encode the result: \(error.localizedDescription)")
	}
}

func fail(_ code: Int32, _ message: String) -> Never {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	if let data = try? encoder.encode(RootErrorRecord(code: code, message: message)) {
		data.withUnsafeBytes { raw in
			if let base = raw.baseAddress { _ = writeAll(STDERR_FILENO, base, raw.count) }
		}
	}
	exit(1)
}

func failErrno(_ context: String? = nil) -> Never {
	let code = errno
	let reason = String(cString: strerror(code))
	fail(code, context.map { "\($0): \(reason)" } ?? reason)
}

func posixCode(of error: Error) -> Int32 {
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

func failWith(_ error: Error) -> Never {
	fail(posixCode(of: error), error.localizedDescription)
}

func lstatInfo(_ path: String) -> stat? {
	var info = stat()
	return lstat(path, &info) == 0 ? info : nil
}

func isDirectoryMode(_ info: stat) -> Bool {
	(info.st_mode & S_IFMT) == S_IFDIR
}

func parentPath(of path: String) -> String {
	let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
	return parent.isEmpty ? "/" : parent
}

func parentOwner(of path: String) -> (uid: uid_t, gid: gid_t)? {
	guard let info = lstatInfo(parentPath(of: path)) else { return nil }
	return (info.st_uid, info.st_gid)
}

func adoptParentOwner(_ path: String) {
	guard let owner = parentOwner(of: path) else { return }
	_ = lchown(path, owner.uid, owner.gid)
}

func chownTree(_ path: String, uid: uid_t, gid: gid_t) {
	_ = lchown(path, uid, gid)
	guard let info = lstatInfo(path), isDirectoryMode(info) else { return }
	guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
	for name in names {
		chownTree(path + "/" + name, uid: uid, gid: gid)
	}
}

func streamStdin(into fd: Int32) -> Int32 {
	let capacity = 1 << 16
	var buffer = [UInt8](repeating: 0, count: capacity)
	while true {
		let count = read(STDIN_FILENO, &buffer, capacity)
		if count < 0 {
			if errno == EINTR { continue }
			return errno
		}
		if count == 0 { return 0 }
		let succeeded = buffer.withUnsafeBytes { writeAll(fd, $0.baseAddress!, count) }
		if !succeeded { return errno }
	}
}

func makeDirectories(_ path: String) {
	var missing: [String] = []
	var current = path
	while current != "/", lstatInfo(current) == nil {
		missing.append(current)
		current = parentPath(of: current)
	}
	for directory in missing.reversed() {
		if mkdir(directory, 0o755) != 0 { failErrno() }
		adoptParentOwner(directory)
	}
}

func totalSize(of path: String) -> Int64 {
	guard let info = lstatInfo(path) else { return 0 }
	guard isDirectoryMode(info) else { return Int64(info.st_size) }
	guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return 0 }
	return names.reduce(Int64(0)) { $0 + totalSize(of: path + "/" + $1) }
}

func applyMode(_ mode: Int16, to path: String, recursive: Bool) throws {
	try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path)
	guard recursive, let info = lstatInfo(path), isDirectoryMode(info) else { return }
	for name in try FileManager.default.contentsOfDirectory(atPath: path) {
		try applyMode(mode, to: path + "/" + name, recursive: true)
	}
}

func requireArguments(_ arguments: [String], _ count: Int, usage: String) {
	if arguments.count < count { fail(EINVAL, "Usage: \(usage)") }
}

func commandList(_ arguments: [String]) {
	requireArguments(arguments, 1, usage: "list <path> [1 to include hidden]")
	let includeHidden = arguments.count > 1 && arguments[1] == "1"
	do {
		let nodes = try DirectoryLister.children(of: URL(fileURLWithPath: arguments[0]), includeHidden: includeHidden)
		emitJSON(nodes.map(RootNodeRecord.init(node:)))
	} catch {
		failWith(error)
	}
}

func commandStat(_ arguments: [String]) {
	requireArguments(arguments, 1, usage: "stat <path>")
	do {
		emitJSON(RootNodeRecord(node: try FileNode.make(at: URL(fileURLWithPath: arguments[0]))))
	} catch {
		failWith(error)
	}
}

func commandRead(_ arguments: [String]) {
	requireArguments(arguments, 1, usage: "read <path>")
	let fd = open(arguments[0], O_RDONLY)
	if fd < 0 { failErrno() }
	let capacity = 1 << 16
	var buffer = [UInt8](repeating: 0, count: capacity)
	while true {
		let count = read(fd, &buffer, capacity)
		if count < 0 {
			if errno == EINTR { continue }
			failErrno("Couldn't read the file")
		}
		if count == 0 { break }
		let succeeded = buffer.withUnsafeBytes { writeAll(STDOUT_FILENO, $0.baseAddress!, count) }
		if !succeeded { exit(2) }
	}
	close(fd)
}

func writeNewFile(_ path: String) {
	let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
	if fd < 0 { failErrno() }
	let streamError = streamStdin(into: fd)
	close(fd)
	if streamError != 0 {
		unlink(path)
		fail(streamError, String(cString: strerror(streamError)))
	}
	adoptParentOwner(path)
}

func replaceFile(_ path: String) {
	var targetPath = path
	if let info = lstatInfo(path), (info.st_mode & S_IFMT) == S_IFLNK {
		targetPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
	}
	let existing = lstatInfo(targetPath)
	let temporaryPath = parentPath(of: targetPath) + "/.filzer-write-" + UUID().uuidString
	let fd = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
	if fd < 0 { failErrno() }
	let streamError = streamStdin(into: fd)
	if streamError != 0 {
		close(fd)
		unlink(temporaryPath)
		fail(streamError, String(cString: strerror(streamError)))
	}
	_ = fchmod(fd, existing.map { $0.st_mode & 0o7777 } ?? 0o644)
	if let existing {
		_ = fchown(fd, existing.st_uid, existing.st_gid)
	} else if let owner = parentOwner(of: targetPath) {
		_ = fchown(fd, owner.uid, owner.gid)
	}
	close(fd)
	if rename(temporaryPath, targetPath) != 0 {
		let code = errno
		unlink(temporaryPath)
		fail(code, String(cString: strerror(code)))
	}
}

func commandWrite(_ arguments: [String]) {
	requireArguments(arguments, 1, usage: "write <path> [new]")
	if arguments.count > 1 && arguments[1] == "new" {
		writeNewFile(arguments[0])
	} else {
		replaceFile(arguments[0])
	}
}

func commandMakeDirectory(_ arguments: [String]) {
	requireArguments(arguments, 1, usage: "mkdir <path>")
	if lstatInfo(arguments[0]) != nil { fail(EEXIST, "\"\(arguments[0])\" already exists.") }
	makeDirectories(arguments[0])
}

func commandRemove(_ arguments: [String]) {
	requireArguments(arguments, 1, usage: "remove <path>")
	do {
		try FileManager.default.removeItem(atPath: arguments[0])
	} catch {
		failWith(error)
	}
}

func commandMove(_ arguments: [String]) {
	requireArguments(arguments, 2, usage: "move <source> <destination>")
	if lstatInfo(arguments[1]) != nil { fail(EEXIST, "\"\(arguments[1])\" already exists.") }
	do {
		try FileManager.default.moveItem(atPath: arguments[0], toPath: arguments[1])
	} catch {
		failWith(error)
	}
}

func commandCopy(_ arguments: [String]) {
	requireArguments(arguments, 2, usage: "copy <source> <destination>")
	if lstatInfo(arguments[1]) != nil { fail(EEXIST, "\"\(arguments[1])\" already exists.") }
	do {
		try FileManager.default.copyItem(atPath: arguments[0], toPath: arguments[1])
	} catch {
		failWith(error)
	}
	if let owner = parentOwner(of: arguments[1]) {
		chownTree(arguments[1], uid: owner.uid, gid: owner.gid)
	}
}

func commandSymbolicLink(_ arguments: [String]) {
	requireArguments(arguments, 2, usage: "symlink <path> <destination>")
	do {
		try FileManager.default.createSymbolicLink(atPath: arguments[0], withDestinationPath: arguments[1])
	} catch {
		failWith(error)
	}
	adoptParentOwner(arguments[0])
}

func commandHardLink(_ arguments: [String]) {
	requireArguments(arguments, 2, usage: "hardlink <path> <existing>")
	do {
		try FileManager.default.linkItem(atPath: arguments[1], toPath: arguments[0])
	} catch {
		failWith(error)
	}
}

func commandChmod(_ arguments: [String]) {
	requireArguments(arguments, 3, usage: "chmod <mode> <path> <1 for recursive>")
	guard let mode = Int16(arguments[0]) else { fail(EINVAL, "\"\(arguments[0])\" isn't a valid mode.") }
	do {
		try applyMode(mode, to: arguments[1], recursive: arguments[2] == "1")
	} catch {
		failWith(error)
	}
}

func commandSize(_ arguments: [String]) {
	requireArguments(arguments, 1, usage: "size <path>")
	if lstatInfo(arguments[0]) == nil { fail(ENOENT, "\"\(arguments[0])\" couldn't be found.") }
	print(totalSize(of: arguments[0]))
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(EINVAL, "No command given.") }
let commandArguments = Array(arguments.dropFirst())

switch command {
case "ping": print("uid=\(getuid())")
case "list": commandList(commandArguments)
case "stat": commandStat(commandArguments)
case "read": commandRead(commandArguments)
case "write": commandWrite(commandArguments)
case "mkdir": commandMakeDirectory(commandArguments)
case "remove": commandRemove(commandArguments)
case "move": commandMove(commandArguments)
case "copy": commandCopy(commandArguments)
case "symlink": commandSymbolicLink(commandArguments)
case "hardlink": commandHardLink(commandArguments)
case "chmod": commandChmod(commandArguments)
case "size": commandSize(commandArguments)
default: fail(EINVAL, "Unknown command \"\(command)\".")
}
