import Foundation

/// The fixed, always-available locations inside Filzer's own sandbox container — the
/// realistic sandboxed equivalent of the root paths a jailbroken Filza would browse
/// system-wide. Every other browsable location (Bookmarks' externally-picked folders)
/// comes from `BookmarksStore` instead.
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
