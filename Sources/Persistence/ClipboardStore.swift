import Combine
import Foundation

enum ClipboardOperation {
	case copy
	case move
}

struct ClipboardPayload: Equatable {
	var urls: [URL]
	var operation: ClipboardOperation

	static func == (lhs: ClipboardPayload, rhs: ClipboardPayload) -> Bool {
		lhs.urls == rhs.urls && lhs.operation == rhs.operation
	}
}

extension ClipboardOperation: Equatable {}

/// Filza's "Pasteboard": a queue of cut/copied items that stays visible (as a banner)
/// until pasted or cleared. Session-only by design — URLs referencing files that may no
/// longer exist shouldn't silently survive a relaunch.
@MainActor
final class ClipboardStore: ObservableObject {
	@Published private(set) var payload: ClipboardPayload?

	var isEmpty: Bool { payload?.urls.isEmpty ?? true }
	var count: Int { payload?.urls.count ?? 0 }

	func set(_ urls: [URL], operation: ClipboardOperation) {
		guard !urls.isEmpty else { return }
		payload = ClipboardPayload(urls: urls, operation: operation)
	}

	func clear() {
		payload = nil
	}
}
