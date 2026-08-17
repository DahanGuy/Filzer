import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class OAuthAuthorizationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
	enum AuthError: LocalizedError {
		case cancelled
		case missingCode
		case invalidCallback

		var errorDescription: String? {
			switch self {
			case .cancelled: return "Sign-in was cancelled."
			case .missingCode: return "The sign-in page didn't return an authorization code."
			case .invalidCallback: return "Filzer couldn't understand the sign-in response."
			}
		}
	}

	private var session: ASWebAuthenticationSession?

	func authorize(url: URL, callbackScheme: String) async throws -> URL {
		try await withCheckedThrowingContinuation { continuation in
			let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
				if let callbackURL {
					continuation.resume(returning: callbackURL)
				} else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
					continuation.resume(throwing: AuthError.cancelled)
				} else {
					continuation.resume(throwing: error ?? AuthError.invalidCallback)
				}
			}
			session.presentationContextProvider = self
			session.prefersEphemeralWebBrowserSession = false
			self.session = session
			if !session.start() {
				continuation.resume(throwing: AuthError.invalidCallback)
			}
		}
	}

	nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
		MainActor.assumeIsolated {
			UIApplication.shared.connectedScenes
				.compactMap { ($0 as? UIWindowScene)?.keyWindow }
				.first ?? ASPresentationAnchor()
		}
	}
}

extension URL {
	func oauthQueryValue(_ name: String) -> String? {
		URLComponents(url: self, resolvingAgainstBaseURL: false)?
			.queryItems?
			.first { $0.name == name }?
			.value
	}
}
