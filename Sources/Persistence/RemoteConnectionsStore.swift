import Combine
import Foundation

@MainActor
final class RemoteConnectionsStore: ObservableObject {
	@Published private(set) var connections: [RemoteConnection] = []

	static let defaultsKey = "Filzer.RemoteConnections"

	init() {
		load()
	}

	func add(_ connection: RemoteConnection, password: String) {
		connections.append(connection)
		save()
		KeychainStore.set(password, forKey: connection.id.uuidString)
	}

	func update(_ connection: RemoteConnection, password: String?) {
		guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
		connections[index] = connection
		save()
		if let password {
			KeychainStore.set(password, forKey: connection.id.uuidString)
		}
		Task { await RemoteProviderRegistry.shared.invalidate(connection.id) }
	}

	func remove(_ connection: RemoteConnection) {
		connections.removeAll { $0.id == connection.id }
		save()
		KeychainStore.remove(connection.id.uuidString)
		OAuthTokenStore.remove(for: connection.id)
		Task { await RemoteProviderRegistry.shared.invalidate(connection.id) }
	}

	func password(for connection: RemoteConnection) -> String? {
		KeychainStore.get(connection.id.uuidString)
	}

	private func load() {
		guard
			let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
			let decoded = try? JSONDecoder().decode([RemoteConnection].self, from: data)
		else { return }
		connections = decoded
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(connections) else { return }
		UserDefaults.standard.set(data, forKey: Self.defaultsKey)
	}
}
