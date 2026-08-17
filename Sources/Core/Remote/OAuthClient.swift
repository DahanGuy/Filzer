import Foundation

struct OAuthEndpoints {
	let authorizationURL: URL
	let tokenURL: URL
	let redirectURI: String
	let scope: String
	let extraAuthorizeParams: [String: String]
}

struct OAuthTokenSet: Codable {
	var accessToken: String
	var refreshToken: String?
	var expiresAt: Date

	var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

enum OAuthClient {
	enum OAuthError: LocalizedError {
		case missingCode
		case invalidAuthorizationURL
		case tokenExchangeFailed(String)

		var errorDescription: String? {
			switch self {
			case .missingCode: return "The sign-in page didn't return an authorization code."
			case .invalidAuthorizationURL: return "Couldn't build a valid sign-in URL — check the Client ID."
			case .tokenExchangeFailed(let message): return "Sign-in failed: \(message)"
			}
		}
	}

	@MainActor
	static func authorize(clientID: String, endpoints: OAuthEndpoints) async throws -> OAuthTokenSet {
		let pkce = PKCE.generate()
		guard var components = URLComponents(url: endpoints.authorizationURL, resolvingAgainstBaseURL: false) else {
			throw OAuthError.invalidAuthorizationURL
		}
		var items = [
			URLQueryItem(name: "client_id", value: clientID),
			URLQueryItem(name: "response_type", value: "code"),
			URLQueryItem(name: "redirect_uri", value: endpoints.redirectURI),
			URLQueryItem(name: "scope", value: endpoints.scope),
			URLQueryItem(name: "code_challenge", value: pkce.challenge),
			URLQueryItem(name: "code_challenge_method", value: "S256"),
		]
		items.append(contentsOf: endpoints.extraAuthorizeParams.map { URLQueryItem(name: $0.key, value: $0.value) })
		components.queryItems = items

		guard
			let authorizeURL = components.url,
			let scheme = URLComponents(string: endpoints.redirectURI)?.scheme
		else {
			throw OAuthError.invalidAuthorizationURL
		}

		let callbackURL = try await OAuthAuthorizationSession().authorize(url: authorizeURL, callbackScheme: scheme)
		guard let code = callbackURL.oauthQueryValue("code") else {
			throw OAuthError.missingCode
		}

		return try await exchangeToken(clientID: clientID, endpoints: endpoints, body: [
			"grant_type": "authorization_code",
			"code": code,
			"redirect_uri": endpoints.redirectURI,
			"code_verifier": pkce.verifier,
		])
	}

	static func refresh(clientID: String, endpoints: OAuthEndpoints, refreshToken: String) async throws -> OAuthTokenSet {
		try await exchangeToken(
			clientID: clientID,
			endpoints: endpoints,
			body: ["grant_type": "refresh_token", "refresh_token": refreshToken],
			previousRefreshToken: refreshToken
		)
	}

	private static func exchangeToken(
		clientID: String,
		endpoints: OAuthEndpoints,
		body: [String: String],
		previousRefreshToken: String? = nil
	) async throws -> OAuthTokenSet {
		var fullBody = body
		fullBody["client_id"] = clientID

		var request = URLRequest(url: endpoints.tokenURL)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.httpBody = Data(formEncode(fullBody).utf8)

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
			let message = String(data: data, encoding: .utf8) ?? "unknown error"
			throw OAuthError.tokenExchangeFailed(message)
		}

		struct TokenResponse: Decodable {
			let access_token: String
			let refresh_token: String?
			let expires_in: Double?
		}
		let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
		return OAuthTokenSet(
			accessToken: decoded.access_token,
			refreshToken: decoded.refresh_token ?? previousRefreshToken,
			expiresAt: Date().addingTimeInterval(decoded.expires_in ?? 3600)
		)
	}

	private static func formEncode(_ params: [String: String]) -> String {
		let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
		return params
			.map { key, value in
				let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
				let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
				return "\(encodedKey)=\(encodedValue)"
			}
			.joined(separator: "&")
	}
}
