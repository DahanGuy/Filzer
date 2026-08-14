import SwiftUI

/// Filza's "Access Permissions" screen: independent rwx toggles per owner/group/other,
/// special bits, a live octal mask, and (for folders) a recursive apply option.
struct PermissionsEditorView: View {
	let node: FileNode

	@Environment(\.dismiss) private var dismiss
	@State private var permissions: POSIXPermissions
	@State private var applyToEnclosedItems = false
	@State private var isSaving = false
	@State private var errorMessage: String?

	init(node: FileNode) {
		self.node = node
		_permissions = State(initialValue: POSIXPermissions(mode: node.posixPermissions))
	}

	var body: some View {
		Form {
			Section("Owner") { triadToggles(\.owner) }
			Section("Group") { triadToggles(\.group) }
			Section("Others") { triadToggles(\.others) }

			Section("Special") {
				Toggle("Set UID", isOn: $permissions.setUID)
				Toggle("Set GID", isOn: $permissions.setGID)
				Toggle("Sticky", isOn: $permissions.sticky)
			}

			if node.isDirectory {
				Section {
					Toggle("Apply to Enclosed Items", isOn: $applyToEnclosedItems)
				}
			}

			Section {
				HStack {
					Text("Mask")
					Spacer()
					Text(permissions.octalString)
						.font(.system(.body, design: .monospaced))
						.foregroundStyle(.secondary)
				}
			}
		}
		.navigationTitle("Permissions")
		.toolbar {
			ToolbarItem(placement: .navigationBarLeading) {
				Button("Cancel") { dismiss() }
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				Button("Save") { Task { await save() } }
					.disabled(isSaving)
			}
		}
		.errorAlert($errorMessage)
	}

	@ViewBuilder
	private func triadToggles(_ keyPath: WritableKeyPath<POSIXPermissions, POSIXPermissions.Triad>) -> some View {
		Toggle("Read", isOn: binding(keyPath, \.read))
		Toggle("Write", isOn: binding(keyPath, \.write))
		Toggle("Execute", isOn: binding(keyPath, \.execute))
	}

	private func binding(
		_ triad: WritableKeyPath<POSIXPermissions, POSIXPermissions.Triad>,
		_ field: WritableKeyPath<POSIXPermissions.Triad, Bool>
	) -> Binding<Bool> {
		Binding(
			get: { permissions[keyPath: triad][keyPath: field] },
			set: { permissions[keyPath: triad][keyPath: field] = $0 }
		)
	}

	private func save() async {
		isSaving = true
		defer { isSaving = false }
		do {
			try await FileSystem.current.setPermissions([node.url], posixPermissions: permissions.mode, recursive: applyToEnclosedItems)
			dismiss()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
