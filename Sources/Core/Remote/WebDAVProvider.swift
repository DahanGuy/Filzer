import Foundation

/// A WebDAV (RFC 4918, obsoletes RFC 2518) client built directly on
/// `URLSession`/`URLRequest` — no third-party dependency. Every method issues one
/// WebDAV HTTP request (PROPFIND/GET/PUT/MKCOL/DELETE/MOVE/COPY) and maps the response
/// to `RemoteFileProvider`'s vocabulary. Stateless per request (HTTP Basic auth is sent
/// on every call), so unlike a stateful protocol this needs no internal serialization.
struct WebDAVProvider: RemoteFileProvider {
	enum WebDAVError: LocalizedError {
		case invalidURL(String)
		case httpStatus(Int, String)
		case malformedResponse(String)

		var errorDescription: String? {
			switch self {
			case .invalidURL(let path):
				return "Couldn't build a WebDAV URL for \"\(path)\"."
			case .httpStatus(let code, let context):
				return "Server returned HTTP \(code) while \(context)."
			case .malformedResponse(let message):
				return "Unexpected WebDAV response: \(message)."
			}
		}
	}

	/// The literal PROPFIND request body — asks for exactly the props `listDirectory`
	/// needs, nothing more.
	private static let propfindBody = Data("""
	<?xml version="1.0" encoding="utf-8"?>
	<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:getcontentlength/><D:getlastmodified/></D:prop></D:propfind>
	""".utf8)

	private let connection: RemoteConnection
	private let password: String
	private let session: URLSession

	init(connection: RemoteConnection, password: String) {
		self.connection = connection
		self.password = password
		let configuration = URLSessionConfiguration.default
		configuration.timeoutIntervalForRequest = 30
		self.session = URLSession(configuration: configuration)
	}

	// MARK: - RemoteFileProvider

	func listDirectory(at path: String) async throws -> [RemoteItem] {
		var request = try makeRequest(method: "PROPFIND", path: path)
		request.setValue("1", forHTTPHeaderField: "Depth")
		request.setValue("application/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
		request.httpBody = Self.propfindBody

		let (data, _) = try await perform(request, successStatuses: [207], context: "listing \"\(path)\"")

		let parser = PropfindResponseParser()
		guard parser.parse(data) else {
			throw WebDAVError.malformedResponse("couldn't parse the PROPFIND multi-status body for \"\(path)\"")
		}

		let requestedPath = Self.normalizedPath(path)
		return parser.entries.compactMap { entry in
			let entryPath = Self.normalizedPath(entry.href)
			guard !entryPath.isEmpty, entryPath != requestedPath else { return nil }
			return RemoteItem(
				name: (entryPath as NSString).lastPathComponent,
				path: entryPath,
				isDirectory: entry.isCollection,
				size: entry.isCollection ? 0 : entry.contentLength,
				modifiedAt: entry.lastModified
			)
		}
	}

	func readFile(at path: String) async throws -> Data {
		let request = try makeRequest(method: "GET", path: path)
		let (data, _) = try await perform(request, successStatuses: Self.anySuccess, context: "reading \"\(path)\"")
		return data
	}

	func writeFile(at path: String, data: Data) async throws {
		var request = try makeRequest(method: "PUT", path: path)
		request.httpBody = data
		_ = try await perform(request, successStatuses: Self.anySuccess, context: "writing \"\(path)\"")
	}

	func createDirectory(at path: String) async throws {
		let request = try makeRequest(method: "MKCOL", path: path)
		// RFC 4918 §9.3.1: MKCOL succeeds with 201 Created only. A 405 (Method Not
		// Allowed) most commonly means the collection already exists — a genuine
		// conflict the caller should see, not something to swallow here.
		_ = try await perform(request, successStatuses: [201], context: "creating directory \"\(path)\"")
	}

	func delete(at path: String) async throws {
		let request = try makeRequest(method: "DELETE", path: path)
		// 207 Multi-Status can occur for a collection delete with partial per-item
		// failures; treated as success here rather than inspecting the multi-status
		// body for individual failures.
		_ = try await perform(request, successStatuses: Self.anySuccess.union([207]), context: "deleting \"\(path)\"")
	}

	func move(from source: String, to destination: String) async throws {
		try await copyOrMove(method: "MOVE", from: source, to: destination)
	}

	func copy(from source: String, to destination: String) async throws {
		try await copyOrMove(method: "COPY", from: source, to: destination)
	}

	// MARK: - Request building

	private static let anySuccess: Set<Int> = Set(200...299)

	private func url(for path: String) throws -> URL {
		var components = URLComponents()
		components.scheme = connection.useSecureConnection ? "https" : "http"
		components.host = connection.host
		components.port = connection.port
		components.path = path
		guard let url = components.url else {
			throw WebDAVError.invalidURL(path)
		}
		return url
	}

	private var authorizationHeaderValue: String {
		let credentials = "\(connection.username):\(password)"
		let encoded = Data(credentials.utf8).base64EncodedString()
		return "Basic \(encoded)"
	}

	private func makeRequest(method: String, path: String) throws -> URLRequest {
		var request = URLRequest(url: try url(for: path))
		request.httpMethod = method
		request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
		return request
	}

	/// WebDAV COPY/MOVE share everything but the HTTP method: a `Destination` header
	/// carrying the *full* destination URL (RFC 4918 §9.9.3/§9.8.3 require an absolute
	/// URI, not just a path) plus `Overwrite: T`. 201 (created) and 204 (overwrote an
	/// existing resource) both count as success.
	private func copyOrMove(method: String, from source: String, to destination: String) async throws {
		var request = try makeRequest(method: method, path: source)
		request.setValue(try url(for: destination).absoluteString, forHTTPHeaderField: "Destination")
		request.setValue("T", forHTTPHeaderField: "Overwrite")
		let verb = method == "MOVE" ? "moving" : "copying"
		_ = try await perform(request, successStatuses: [201, 204], context: "\(verb) \"\(source)\" to \"\(destination)\"")
	}

	private func perform(
		_ request: URLRequest,
		successStatuses: Set<Int>,
		context: String
	) async throws -> (Data, HTTPURLResponse) {
		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw WebDAVError.malformedResponse("no HTTP response while \(context)")
		}
		guard successStatuses.contains(httpResponse.statusCode) else {
			throw WebDAVError.httpStatus(httpResponse.statusCode, context)
		}
		return (data, httpResponse)
	}

	/// Normalizes an href/path for comparison and display: strips scheme+host if the
	/// server returned an absolute URL instead of a path-only href, URL-decodes it, and
	/// drops a trailing slash (WebDAV collections are conventionally returned with one).
	private static func normalizedPath(_ raw: String) -> String {
		var rawPath = raw
		if let schemeRange = raw.range(of: "://"), let hostEnd = raw[schemeRange.upperBound...].firstIndex(of: "/") {
			rawPath = String(raw[hostEnd...])
		}
		var decoded = rawPath.removingPercentEncoding ?? rawPath
		if decoded.count > 1 && decoded.hasSuffix("/") {
			decoded.removeLast()
		}
		return decoded
	}

	// MARK: - PROPFIND response parsing

	/// Parses a PROPFIND multi-status XML body into one entry per `<D:response>`.
	/// Matches elements by local name only (stripping any namespace prefix) since
	/// real-world servers vary between `D:`, `d:`, and no prefix at all.
	private final class PropfindResponseParser: NSObject, XMLParserDelegate {
		struct Entry {
			var href = ""
			var isCollection = false
			var contentLength: Int64 = 0
			var lastModified: Date?
		}

		private(set) var entries: [Entry] = []

		private var currentEntry: Entry?
		private var textBuffer = ""

		private static let dateFormatter: DateFormatter = {
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.timeZone = TimeZone(identifier: "UTC")
			formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
			return formatter
		}()

		func parse(_ data: Data) -> Bool {
			let parser = XMLParser(data: data)
			parser.delegate = self
			return parser.parse()
		}

		private static func localName(_ qualifiedName: String) -> String {
			guard let colonIndex = qualifiedName.lastIndex(of: ":") else { return qualifiedName }
			return String(qualifiedName[qualifiedName.index(after: colonIndex)...])
		}

		func parser(
			_ parser: XMLParser,
			didStartElement elementName: String,
			namespaceURI: String?,
			qualifiedName qName: String?,
			attributes attributeDict: [String: String]
		) {
			textBuffer = ""
			switch Self.localName(elementName) {
			case "response":
				currentEntry = Entry()
			case "collection":
				currentEntry?.isCollection = true
			default:
				break
			}
		}

		func parser(_ parser: XMLParser, foundCharacters string: String) {
			textBuffer += string
		}

		func parser(
			_ parser: XMLParser,
			didEndElement elementName: String,
			namespaceURI: String?,
			qualifiedName qName: String?
		) {
			let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
			switch Self.localName(elementName) {
			case "href":
				currentEntry?.href = trimmed
			case "getcontentlength":
				currentEntry?.contentLength = Int64(trimmed) ?? 0
			case "getlastmodified":
				currentEntry?.lastModified = Self.dateFormatter.date(from: trimmed)
			case "response":
				if let entry = currentEntry {
					entries.append(entry)
				}
				currentEntry = nil
			default:
				break
			}
			textBuffer = ""
		}
	}
}
