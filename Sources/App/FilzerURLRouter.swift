import SwiftUI

final class FilzerURLRouter: ObservableObject {
	static let shared = FilzerURLRouter()

	struct FolderRequest: Equatable {
		let id = UUID()
		let url: URL
	}

	struct ViewerTarget: Identifiable {
		let node: FileNode
		let kind: ViewerKind?
		var id: URL { node.url }
	}

	enum Action: Equatable {
		case open(path: String, viewer: ViewerKind?)
		case info(path: String)
	}

	@Published var folderRequest: FolderRequest?
	@Published var viewerTarget: ViewerTarget?
	@Published var infoTarget: FileNode?
	@Published var errorMessage: String?

	func handle(_ url: URL) {
		guard let action = Self.parse(url) else { return }
		Task { await resolve(action) }
	}

	static func parse(_ url: URL) -> Action? {
		guard
			url.scheme?.lowercased() == "filzer",
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			let command = components.host?.lowercased()
		else { return nil }

		let queryItems = components.queryItems ?? []
		var path = queryItems.first { $0.name == "path" }?.value ?? components.path
		if !path.hasPrefix("/") { path = "/" + path }

		switch command {
		case "open", "view":
			let viewer = queryItems.first { $0.name == "viewer" }?.value.flatMap { viewerKind(named: $0) }
			return .open(path: path, viewer: viewer)
		case "info":
			return .info(path: path)
		default:
			guard let viewer = viewerKind(named: command) else { return nil }
			return .open(path: path, viewer: viewer)
		}
	}

	private static func viewerKind(named name: String) -> ViewerKind? {
		let lowercased = name.lowercased()
		switch lowercased {
		case "edit": return .text
		case "plist": return .propertyList
		default: return ViewerKind.allCases.first { $0.rawValue.lowercased() == lowercased }
		}
	}

	private func resolve(_ action: Action) async {
		do {
			switch action {
			case .open(let path, let viewer):
				var url = URL(fileURLWithPath: path)
				var node = try await FileSystem.current.nodeInfo(at: url)
				if node.isSymbolicLink {
					url = url.resolvingSymlinksInPath()
					node = try await FileSystem.current.nodeInfo(at: url)
				}
				let target = node
				let folder = target.isDirectory ? url : url.deletingLastPathComponent()
				await MainActor.run {
					folderRequest = FolderRequest(url: folder)
					if !target.isDirectory {
						viewerTarget = ViewerTarget(node: target, kind: viewer)
					}
				}
			case .info(let path):
				let node = try await FileSystem.current.nodeInfo(at: URL(fileURLWithPath: path))
				await MainActor.run { infoTarget = node }
			}
		} catch {
			let message = error.localizedDescription
			await MainActor.run { errorMessage = message }
		}
	}
}

struct URLFolderRequestModifier: ViewModifier {
	let isRoot: Bool
	let onRequest: (URL) -> Void

	@ObservedObject private var router = FilzerURLRouter.shared

	func body(content: Content) -> some View {
		content.onReceive(router.$folderRequest.compactMap { $0 }) { request in
			guard isRoot else { return }
			router.folderRequest = nil
			DispatchQueue.main.async { onRequest(request.url) }
		}
	}
}
