import Foundation

enum SecurityScopedBookmark {
	static func makeBookmark(for url: URL) throws -> Data {
		try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
	}

	static func resolve(_ bookmarkData: Data) throws -> (url: URL, isStale: Bool) {
		var isStale = false
		let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
		return (url, isStale)
	}

	static func withSecurityScopedAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
		let didStartAccessing = url.startAccessingSecurityScopedResource()
		defer {
			if didStartAccessing { url.stopAccessingSecurityScopedResource() }
		}
		return try body()
	}

	static func withSecurityScopedAccess<T>(to url: URL, _ body: () async throws -> T) async rethrows -> T {
		let didStartAccessing = url.startAccessingSecurityScopedResource()
		defer {
			if didStartAccessing { url.stopAccessingSecurityScopedResource() }
		}
		return try await body()
	}
}
