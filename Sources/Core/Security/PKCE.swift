import CryptoKit
import Foundation

/// RFC 7636 Proof Key for Code Exchange — required for every OAuth flow in this app
/// since Filzer is an unsigned, sideloaded IPA and can never safely embed a shared
/// client secret. PKCE lets a "public client" (no secret) prove to the authorization
/// server that the app exchanging the code is the same one that started the flow.
enum PKCE {
	struct Pair {
		let verifier: String
		let challenge: String
	}

	/// Generates a random verifier (RFC 7636 §4.1: 43-128 characters from the
	/// unreserved URL-safe alphabet) and its S256 challenge.
	static func generate() -> Pair {
		var bytes = [UInt8](repeating: 0, count: 32)
		_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		let verifier = base64URLEncode(Data(bytes))
		let digest = SHA256.hash(data: Data(verifier.utf8))
		let challenge = base64URLEncode(Data(digest))
		return Pair(verifier: verifier, challenge: challenge)
	}

	private static func base64URLEncode(_ data: Data) -> String {
		data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
}
