import Foundation

struct POSIXPermissions: Equatable {
	struct Triad: Equatable {
		var read: Bool
		var write: Bool
		var execute: Bool

		fileprivate var bits: Int16 {
			(read ? 0o4 : 0) | (write ? 0o2 : 0) | (execute ? 0o1 : 0)
		}

		fileprivate init(bits: Int16) {
			read = bits & 0o4 != 0
			write = bits & 0o2 != 0
			execute = bits & 0o1 != 0
		}

		init(read: Bool, write: Bool, execute: Bool) {
			self.read = read
			self.write = write
			self.execute = execute
		}
	}

	var owner: Triad
	var group: Triad
	var others: Triad
	var setUID: Bool
	var setGID: Bool
	var sticky: Bool

	init(mode: Int16) {
		owner = Triad(bits: (mode >> 6) & 0o7)
		group = Triad(bits: (mode >> 3) & 0o7)
		others = Triad(bits: mode & 0o7)
		setUID = mode & 0o4000 != 0
		setGID = mode & 0o2000 != 0
		sticky = mode & 0o1000 != 0
	}

	var mode: Int16 {
		var value = (owner.bits << 6) | (group.bits << 3) | others.bits
		if setUID { value |= 0o4000 }
		if setGID { value |= 0o2000 }
		if sticky { value |= 0o1000 }
		return value
	}

	var octalString: String {
		String(format: "%o", mode)
	}

	var symbolicString: String {
		func render(_ triad: Triad, special: (set: Bool, upper: Character, lower: Character)) -> String {
			var result = ""
			result += triad.read ? "r" : "-"
			result += triad.write ? "w" : "-"
			if special.set {
				result += triad.execute ? String(special.lower) : String(special.upper)
			} else {
				result += triad.execute ? "x" : "-"
			}
			return result
		}
		let ownerPart = render(owner, special: (setUID, "S", "s"))
		let groupPart = render(group, special: (setGID, "S", "s"))
		let othersPart = render(others, special: (sticky, "T", "t"))
		return ownerPart + groupPart + othersPart
	}
}
