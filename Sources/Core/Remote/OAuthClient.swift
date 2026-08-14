import Foundation

/// The provider-specific pieces of an OAuth 2.0 + PKCE flow (RFC 6749 / RFC 7636).
/// The wire format everything else needs — a form-encoded POST returning
/// `access_token`/`refresh_token`/`expires_in` JSON — is identical across
/// Dropbox/Google/Microsoft, so only this handful of values differs between them.
struct OAuthEndpoints {
	let authorizationURL: URL
	let tokenURL: URL
	let redirectURI: String
	let scope: String
	/// Extra query parameters appended to the authorize request only — e.g. Dropbox's
	/// `token_access_type=offline`, Google's `access_type=offline&prompt=consent`.
	let extraAuthorizeParams: [String: String]
}

struct OAuthTokenSet: Codable {
	var accessToken: String
	var refreshToken: String?
	var expiresAt: Date

	/// A minute of slack so a token doesn't expire mid-request.
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

	/// Runs the full interactive flow: presents the provider's own sign-in page,
	/// waits for the redirect back to Filzer, then exchanges the returned code for
	/// tokens. `clientID` is the user's own OAuth app Client ID — Filzer never ships
	/// with one, since a redistributed IPA can't hold a client secret safely and each
	/// provider requires that Client ID's registered redirect URI to match exactly.
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
			// A refresh grant sometimes omits refresh_token (it hasn't changed) —
			// keep using the one we already had in that case.
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
