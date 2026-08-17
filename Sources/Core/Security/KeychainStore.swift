import Foundation
import Security

enum KeychainStore {
	private static let service = "com.guy.filzer.remote-credentials"

	static func set(_ value: String, forKey key: String) {
		let data = Data(value.utf8)
		var query = baseQuery(for: key)
		SecItemDelete(query as CFDictionary)
		query[kSecValueData as String] = data
		query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
		SecItemAdd(query as CFDictionary, nil)
	}

	static func get(_ key: String) -> String? {
		var query = baseQuery(for: key)
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne

		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess, let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func remove(_ key: String) {
		SecItemDelete(baseQuery(for: key) as CFDictionary)
	}

	private static func baseQuery(for key: String) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: key,
		]
	}
}
