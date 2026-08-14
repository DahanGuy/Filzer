import Foundation

/// Wraps the security-scoped bookmark dance needed to keep read/write access to a
/// folder or file the user picked once via `UIDocumentPickerViewController` (e.g. "Add
/// Location" in Home, or a Bookmark pointing outside Filzer's own container) across app
/// launches.
enum SecurityScopedBookmark {
	/// Creates bookmark data for a URL the app currently has access to (typically right
	/// after a document picker returns it). Store the result in `BookmarksStore`.
	static func makeBookmark(for url: URL) throws -> Data {
		try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
	}

	/// Resolves previously-stored bookmark data back into a URL. The caller is
	/// responsible for calling `resolvedURL.startAccessingSecurityScopedResource()`
	/// before use and `stopAccessingSecurityScopedResource()` when done — see
	/// `withSecurityScopedAccess(to:_:)` below for the common case.
	static func resolve(_ bookmarkData: Data) throws -> (url: URL, isStale: Bool) {
		var isStale = false
		let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
		return (url, isStale)
	}

	/// Runs `body` with security-scoped access to `url` started, guaranteeing it's
	/// stopped afterward even if `body` throws.
	static func withSecurityScopedAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
		let didStartAccessing = url.startAccessingSecurityScopedResource()
		defer {
			if didStartAccessing { url.stopAccessingSecurityScopedResource() }
		}
		return try body()
	}

	/// Async variant for wrapping an `async throws` body (e.g. an engine call) instead
	/// of a synchronous one.
	static func withSecurityScopedAccess<T>(to url: URL, _ body: () async throws -> T) async rethrows -> T {
		let didStartAccessing = url.startAccessingSecurityScopedResource()
		defer {
			if didStartAccessing { url.stopAccessingSecurityScopedResource() }
		}
		return try await body()
	}
}
