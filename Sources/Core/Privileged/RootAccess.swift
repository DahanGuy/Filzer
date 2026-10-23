import Foundation

enum RootAccessStatus: Equatable {
	case notBundled
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

	var helperPath: String? {
		let path = (Bundle.main.bundlePath as NSString).appendingPathComponent(RootHelperProtocol.executableName)
		return FileManager.default.isExecutableFile(atPath: path) ? path : nil
	}

	var isHelperBundled: Bool { helperPath != nil }

	var isEnabled: Bool {
		UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
	}

	func activeClient() async -> RootHelperClient? {
		guard isEnabled, let path = helperPath else { return nil }
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
		guard helperPath != nil else { return .notBundled }
		guard isEnabled else { return .disabled }
		if await activeClient() != nil { return .active }
		if case .failed(let reason)? = cachedProbeResult() { return .unavailable(reason) }
		return .unavailable("The root helper didn't start.")
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
			return isRoot ? .ready : .failed("The helper started, but not with root privileges.")
		} catch RootHelperError.launchFailed(let reason) {
			return .failed(reason)
		} catch {
			return .failed(error.localizedDescription)
		}
	}
}
