import PartyUI
import SwiftUI

struct DebInspectorView: View {
	let url: URL

	@State private var summary: DebSummary?
	@State private var errorMessage: String?
	@State private var isLoading = true
	@State private var canInstall = false
	@State private var installError: String?

	private static let primaryKeys = ["Package", "Name", "Version", "Architecture", "Author", "Maintainer", "Section", "Installed-Size", "Homepage", "Depends", "Description"]

	var body: some View {
		Group {
			if let summary {
				content(for: summary)
			} else if isLoading {
				ProgressView()
			} else {
				List {
					Section(footer: Text(errorMessage ?? "")) {
						Label("Couldn't Read Package", systemImage: "questionmark.folder")
					}
					installSection(isIOSPackage: true)
					browseSection
				}
			}
		}
		.navigationTitle(summary?.displayName ?? url.lastPathComponent)
		.task { await load() }
		.task { canInstall = await SileoInstaller.isInstalled() }
		.errorAlert($installError)
	}

	private func content(for summary: DebSummary) -> some View {
		List {
			Section {
				identityRow(summary)
			}
			Section(header: HeaderLabel(text: "Details", icon: "info.circle")) {
				infoRow("Type", summary.isIOSPackage ? "iOS \(summary.kind.lowercased())" : "Generic Debian package")
				infoRow("Platform", summary.platform)
				ForEach(Self.primaryKeys.filter { $0 != "Description" }, id: \.self) { key in
					if let value = summary.value(for: key), !value.isEmpty {
						fieldRow(key, value)
					}
				}
				infoRow("File Size", ByteCountFormat.string(for: summary.fileSize))
				if !summary.maintainerScripts.isEmpty {
					infoRow("Scripts", summary.maintainerScripts.joined(separator: ", "))
				}
			}
			if let description = summary.value(for: "Description"), description.contains("\n") {
				Section(header: HeaderLabel(text: "Description", icon: "text.alignleft")) {
					Text(description)
				}
			}
			let otherFields = summary.fields.filter { field in
				!Self.primaryKeys.contains { $0.caseInsensitiveCompare(field.key) == .orderedSame }
			}
			if !otherFields.isEmpty {
				Section(header: HeaderLabel(text: "Other Fields", icon: "list.bullet")) {
					ForEach(otherFields) { field in
						fieldRow(field.key, field.value)
					}
				}
			}
			installSection(isIOSPackage: summary.isIOSPackage)
			browseSection
		}
	}

	@ViewBuilder
	private func installSection(isIOSPackage: Bool) -> some View {
		if canInstall {
			if isIOSPackage {
				Section(footer: Text("Choose Sileo in the share sheet to install this package.")) {
					Button { installWithSileo() } label: {
						Label("Install with Sileo", systemImage: "square.and.arrow.down")
					}
				}
			} else {
				Section {
					Text("This package isn't built for iOS, so Sileo can't install it.")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	private var browseSection: some View {
		Section {
			NavigationLink(destination: ArchiveBrowserView(url: url)) {
				NavigationLabel(text: "Browse Contents", icon: "archivebox")
			}
		}
	}

	private func identityRow(_ summary: DebSummary) -> some View {
		HStack(spacing: 16) {
			Image(systemName: "shippingbox.fill")
				.font(.title)
				.foregroundStyle(.white)
				.frame(width: 60, height: 60)
				.background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(summary.isIOSPackage ? Color.accentColor : Color.gray))
			VStack(alignment: .leading, spacing: 4) {
				Text(summary.displayName)
					.font(.headline)
				if let synopsis = summary.synopsis, !synopsis.isEmpty {
					Text(synopsis)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.padding(.vertical, 4)
	}

	private func infoRow(_ label: String, _ value: String) -> some View {
		HStack {
			Text(label).foregroundStyle(.secondary)
			Spacer()
			Text(value).multilineTextAlignment(.trailing)
		}
	}

	private func fieldRow(_ label: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label).font(.caption).foregroundStyle(.secondary)
			Text(value)
		}
	}

	private func installWithSileo() {
		if !SileoInstaller.install(url) {
			installError = "Couldn't open the share sheet."
		}
	}

	private func load() async {
		do {
			summary = try await DebInspector.summarize(debURL: url)
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}
}
