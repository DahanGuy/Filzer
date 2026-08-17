import PartyUI
import SwiftUI

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

	@State private var pendingConnectionID = UUID()
	@State private var clientID = ""
	@State private var isSignedIn = false
	@State private var isSigningIn = false
	@State private var errorMessage: String?

	var body: some View {
		Form {
			Section(header: HeaderLabel(text: "Type", icon: "network")) {
				Picker(selection: $kind) {
					ForEach(RemoteConnectionKind.allCases) { kind in
						Label(kind.title, systemImage: kind.systemImageName).tag(kind)
					}
				} label: {
					Label(kind.title, systemImage: kind.systemImageName)
				}
				.pickerStyle(.menu)
				.onChange(of: kind) { _ in resetSignIn() }
			}

			if kind.isOAuthBased {
				cloudSections
			} else {
				hostBasedSections
			}
		}
		.navigationTitle("Add Location")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
			ToolbarItem(placement: .navigationBarTrailing) { Button("Save", action: save).disabled(!canSave) }
		}
		.errorAlert($errorMessage)
	}

	@ViewBuilder
	private var hostBasedSections: some View {
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

	@ViewBuilder
	private var cloudSections: some View {
		Section(header: HeaderLabel(text: "Name", icon: "tag")) {
			TextField("Name", text: $displayName)
		}

		Section(
			header: HeaderLabel(text: "Your App Registration", icon: "key"),
			footer: Text(setupInstructions)
		) {
			TextField("Client ID", text: $clientID)
				.autocapitalization(.none)
				.disableAutocorrection(true)
				.onChange(of: clientID) { _ in resetSignIn() }
			HStack {
				Text("Redirect URI")
				Spacer()
				Text(redirectURI)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.trailing)
			}
			.font(.footnote)
			.textSelection(.enabled)
		}

		Section {
			Button {
				Task { await signIn() }
			} label: {
				HStack {
					Text(isSignedIn ? "Signed In" : "Sign In")
					if isSigningIn {
						Spacer()
						ProgressView()
					}
				}
			}
			.disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || isSigningIn || isSignedIn)
		}
	}

	private var redirectURI: String {
		switch kind {
		case .dropbox: return DropboxProvider.redirectURI
		case .googleDrive: return GoogleDriveProvider.redirectURI
		case .oneDrive: return OneDriveProvider.redirectURI
		case .webDAV, .ftp, .smb: return ""
		}
	}

	private var setupInstructions: String {
		switch kind {
		case .dropbox:
			return "Create an app at dropbox.com/developers/apps, add \(redirectURI) under OAuth 2 → Redirect URIs, and paste its App Key above."
		case .googleDrive:
			return "In Google Cloud Console, create an OAuth client of type \"Desktop app\" (not \"iOS\" — that type can't use a fixed redirect URI), add \(redirectURI) as an authorized redirect URI, and paste its Client ID above."
		case .oneDrive:
			return "In the Entra admin center, register an app for \"Accounts in any organizational directory and personal Microsoft accounts\", add a Mobile/Desktop platform with redirect URI \(redirectURI), and paste the Application (client) ID above."
		case .webDAV, .ftp, .smb:
			return ""
		}
	}

	private var canSave: Bool {
		if kind.isOAuthBased {
			return isSignedIn
		}
		return !host.trimmingCharacters(in: .whitespaces).isEmpty
	}

	private func resetSignIn() {
		if isSignedIn {
			OAuthTokenStore.remove(for: pendingConnectionID)
		}
		pendingConnectionID = UUID()
		isSignedIn = false
	}

	private func signIn() async {
		isSigningIn = true
		defer { isSigningIn = false }
		do {
			let endpoints: OAuthEndpoints
			switch kind {
			case .dropbox: endpoints = DropboxProvider.endpoints
			case .googleDrive: endpoints = GoogleDriveProvider.endpoints
			case .oneDrive: endpoints = OneDriveProvider.endpoints
			case .webDAV, .ftp, .smb: return
			}
			let tokens = try await OAuthClient.authorize(clientID: clientID, endpoints: endpoints)
			OAuthTokenStore.save(tokens, for: pendingConnectionID)
			isSignedIn = true
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func save() {
		if kind.isOAuthBased {
			let connection = RemoteConnection(
				id: pendingConnectionID,
				kind: kind,
				displayName: displayName.isEmpty ? kind.title : displayName,
				basePath: "/",
				clientID: clientID
			)
			remoteConnections.add(connection, password: "")
		} else {
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
		}
		dismiss()
	}
}
