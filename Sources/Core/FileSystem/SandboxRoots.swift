import Foundation

enum SandboxRoots {
	static var documents: URL {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
	}

	static var library: URL {
		FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
	}

	static var temporary: URL {
		FileManager.default.temporaryDirectory
	}
}
