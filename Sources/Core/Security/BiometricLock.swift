import Foundation
import LocalAuthentication

/// Thin wrapper over LocalAuthentication powering the optional app-lock (Filza's
/// "Access password" + Touch ID/Face ID gate).
enum BiometricLock {
	enum Kind {
		case faceID
		case touchID
		case passcodeOnly
	}

	enum Availability {
		case unavailable
		case available(Kind)
	}

	static func availability() -> Availability {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
			return .unavailable
		}
		switch context.biometryType {
		case .faceID: return .available(.faceID)
		case .touchID: return .available(.touchID)
		default: return .available(.passcodeOnly)
		}
	}

	/// Prompts Face ID / Touch ID / device passcode. Returns `true` only on success.
	static func authenticate(reason: String) async -> Bool {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
		return await withCheckedContinuation { continuation in
			context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
				continuation.resume(returning: success)
			}
		}
	}
}
