import PartyUI
import SwiftUI

struct MobileProvisionView: View {
	let url: URL

	@State private var profile: MobileProvisionParser.Profile?
	@State private var errorMessage: String?
	@State private var isLoading = true

	var body: some View {
		Group {
			if let profile {
				List {
					Section(header: HeaderLabel(text: "Profile", icon: "checkmark.seal")) {
						infoRow("Name", profile.name ?? "\u{2014}")
						infoRow("App ID", profile.appIDName ?? "\u{2014}")
						infoRow("Team", profile.teamName ?? "\u{2014}")
						if !profile.teamIdentifiers.isEmpty {
							infoRow("Team ID", profile.teamIdentifiers.joined(separator: ", "))
						}
						infoRow("UUID", profile.uuid ?? "\u{2014}")
						infoRow("Platforms", profile.platforms.isEmpty ? "\u{2014}" : profile.platforms.joined(separator: ", "))
					}

					Section(header: HeaderLabel(text: "Validity", icon: "calendar")) {
						infoRow("Created", profile.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "\u{2014}")
						infoRow("Expires", profile.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "\u{2014}")
					}

					Section(header: HeaderLabel(text: "Devices", icon: "iphone")) {
						if profile.provisionsAllDevices {
							Text("Provisions all devices (distribution profile)")
								.foregroundStyle(.secondary)
						} else {
							infoRow("Registered Devices", "\(profile.provisionedDeviceCount ?? 0)")
						}
					}

					if !profile.entitlements.isEmpty {
						Section(header: HeaderLabel(text: "Entitlements", icon: "key")) {
							ForEach(profile.entitlements, id: \.key) { entitlement in
								infoRow(entitlement.key, entitlement.value)
							}
						}
					}
				}
			} else if isLoading {
				ProgressView()
			} else {
				EmptyStateView(icon: "xmark.seal", title: "Couldn't Read Profile", message: errorMessage)
			}
		}
		.navigationTitle(profile?.name ?? "Provisioning Profile")
		.task { await load() }
	}

	private func infoRow(_ label: String, _ value: String) -> some View {
		HStack {
			Text(label).foregroundStyle(.secondary)
			Spacer()
			Text(value).multilineTextAlignment(.trailing)
		}
	}

	private func load() async {
		do {
			let data = try await FileSystem.current.readFile(at: url)
			profile = try MobileProvisionParser.parse(data)
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}
}
