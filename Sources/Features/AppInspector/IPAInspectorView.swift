import PartyUI
import SwiftUI

/// Read-only inspector for `.ipa` app archives — icon, identity, and version at a
/// glance, plus a link into `ArchiveBrowserView` to browse the raw contents. There is
/// no install action anywhere on this screen, by design.
struct IPAInspectorView: View {
	let url: URL

	@State private var summary: IPASummary?
	@State private var errorMessage: String?
	@State private var isLoading = true

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
					Section {
						NavigationLink(destination: ArchiveBrowserView(url: url)) {
							NavigationLabel(text: "Browse Contents", icon: "archivebox")
						}
					}
				}
			} else if isLoading {
				ProgressView()
			} else {
				EmptyStateView(icon: "questionmark.app.dashed", title: "Couldn't Read IPA", message: errorMessage)
			}
		}
		.navigationTitle(summary?.displayName ?? url.lastPathComponent)
		.task { await load() }
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

	private func load() async {
		do {
			summary = try await IPAInspector.summarize(ipaURL: url)
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}
}
