import PartyUI
import SwiftUI

/// Add-connection form for a WebDAV, FTP, or SMB network location. The password is
/// never held in `@State` beyond this form's lifetime — it's written straight to the
/// Keychain by `RemoteConnectionsStore.add`, never through `UserDefaults`.
struct AddRemoteLocationView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var remoteConnections: RemoteConnectionsStore

	@State private var kind: RemoteConnectionKind = .webDAV
	@State private var displayName = ""
	@State private var host = ""
	@State private var port = ""
	@State private var username = ""
	@State private var password = ""
	@State private var useSecureConnection = true
	@State private var basePath = "/"

	var body: some View {
		Form {
			Section(header: HeaderLabel(text: "Type", icon: "network")) {
				Picker("Type", selection: $kind) {
					ForEach(RemoteConnectionKind.allCases) { kind in
						Text(kind.title).tag(kind)
					}
				}
				.pickerStyle(.segmented)
			}

			Section(header: HeaderLabel(text: "Server", icon: "server.rack")) {
				TextField("Name", text: $displayName)
				TextField("Host", text: $host)
					.keyboardType(.URL)
					.autocapitalization(.none)
					.disableAutocorrection(true)
				TextField("Port (default \(kind.defaultPort))", text: $port)
					.keyboardType(.numberPad)
				TextField(kind == .smb ? "Share Name/Path" : "Base Path", text: $basePath)
					.autocapitalization(.none)
					.disableAutocorrection(true)
				if kind.supportsSecureToggle {
					PlainToggle(text: kind == .ftp ? "Use FTPS" : "Use HTTPS", isOn: $useSecureConnection)
				}
			}

			Section(header: HeaderLabel(text: "Credentials", icon: "person.badge.key")) {
				TextField("Username", text: $username)
					.autocapitalization(.none)
					.disableAutocorrection(true)
				SecureField("Password", text: $password)
			}
		}
		.navigationTitle("Add Location")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
			ToolbarItem(placement: .navigationBarTrailing) { Button("Save", action: save).disabled(!canSave) }
		}
	}

	private var canSave: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty }

	private func save() {
		let connection = RemoteConnection(
			kind: kind,
			displayName: displayName.isEmpty ? host : displayName,
			host: host,
			port: Int(port) ?? kind.defaultPort,
			username: username,
			useSecureConnection: useSecureConnection,
			basePath: basePath.isEmpty ? "/" : basePath
		)
		remoteConnections.add(connection, password: password)
		dismiss()
	}
}
