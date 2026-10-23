import PartyUI
import SwiftUI

struct IPAInspectorView: View {
	let url: URL

	@State private var summary: IPASummary?
	@State private var errorMessage: String?
	@State private var isLoading = true
	@State private var canInstall = false
	@State private var installError: String?

	var body: some View {
		Group {
			if let summary {
				List {
					Section {
						identityRow(summary)
					}
					Section(header: HeaderLabel(text: "Details", icon: "info.circle")) {
						infoRow("Bundle ID", summary.bundleIdentifier)
						infoRow("Version", summary.version)
						infoRow("Build", summary.buildNumber)
						infoRow("Minimum iOS", summary.minimumOSVersion ?? "\u{2014}")
						infoRow("Executable", summary.executableName ?? "\u{2014}")
					}
					if canInstall {
						Section(footer: Text("Hands this file to TrollStore to install.")) {
							Button { install() } label: {
								Label("Install App", systemImage: "square.and.arrow.down")
							}
						}
					}
					Section {
						NavigationLink(destination: ArchiveBrowserView(url: url)) {
							NavigationLabel(text: "Browse Contents", icon: "archivebox")
						}
					}
				}
			} else if isLoading {
				ProgressView()
			} else {
				EmptyStateView(icon: "questionmark.app.dashed", title: "Couldn't Read App", message: errorMessage)
			}
		}
		.navigationTitle(summary?.displayName ?? url.lastPathComponent)
		.task { await load() }
		.task { canInstall = await TrollStoreInstaller.isInstalled() }
		.errorAlert($installError)
	}

	private func identityRow(_ summary: IPASummary) -> some View {
		HStack(spacing: 16) {
			iconView(for: summary)
			VStack(alignment: .leading, spacing: 4) {
				Text(summary.displayName)
					.font(.headline)
				Text(summary.bundleIdentifier)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}

	private func iconView(for summary: IPASummary) -> some View {
		let icon = summary.iconData.flatMap(UIImage.init(data:))
		return AppIcon(image: Image(uiImage: icon ?? UIImage()))
	}

	private func infoRow(_ label: String, _ value: String) -> some View {
		HStack {
			Text(label).foregroundStyle(.secondary)
			Spacer()
			Text(value).multilineTextAlignment(.trailing)
		}
	}

	private func install() {
		Task {
			if await !TrollStoreInstaller.install(url) {
				installError = "Couldn't open TrollStore."
			}
		}
	}

	private func load() async {
		do {
			summary = try await IPAInspector.summarize(ipaURL: url)
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}
}
