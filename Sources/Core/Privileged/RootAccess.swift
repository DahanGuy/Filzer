import Foundation

enum RootAccessStatus: Equatable {
	case disabled
	case active
	case unavailable(String)
}

final class RootAccess: @unchecked Sendable {
	static let shared = RootAccess()
	static let enabledDefaultsKey = "Filzer.Settings.UseRootAccess"

	private enum ProbeResult {
		case ready
		case failed(String)
	}

	private let lock = NSLock()
	private var probeResult: ProbeResult?

	var isEnabled: Bool {
		UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
	}

	func activeClient() async -> RootHelperClient? {
		guard isEnabled, let path = Bundle.main.executablePath else { return nil }
		let result: ProbeResult
		if let cached = cachedProbeResult() {
			result = cached
		} else {
			result = await probe(path)
			store(result)
		}
		if case .ready = result { return RootHelperClient(executablePath: path) }
		return nil
	}

	func status() async -> RootAccessStatus {
		guard isEnabled else { return .disabled }
		if await activeClient() != nil { return .active }
		if case .failed(let reason)? = cachedProbeResult() { return .unavailable(reason) }
		return .unavailable("Filzer couldn't find its own executable.")
	}

	func markUnavailable(_ reason: String) {
		store(.failed(reason))
	}

	func invalidate() {
		lock.lock()
		probeResult = nil
		lock.unlock()
	}

	private func cachedProbeResult() -> ProbeResult? {
		lock.lock()
		defer { lock.unlock() }
		return probeResult
	}

	private func store(_ result: ProbeResult) {
		lock.lock()
		probeResult = result
		lock.unlock()
	}

	private func probe(_ path: String) async -> ProbeResult {
		do {
			let isRoot = try await RootHelperClient(executablePath: path).ping()
			return isRoot ? .ready : .failed("Filzer started, but not with root privileges.")
		} catch RootHelperError.launchFailed(let reason) {
			return .failed(reason)
		} catch {
			return .failed(error.localizedDescription)
		}
	}
}
