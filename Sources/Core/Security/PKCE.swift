import CryptoKit
import Foundation

enum PKCE {
	struct Pair {
		let verifier: String
		let challenge: String
	}

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
