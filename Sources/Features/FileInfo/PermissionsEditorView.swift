import PartyUI
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
			Section(header: HeaderLabel(text: "Owner", icon: "person.fill")) { triadToggles(\.owner) }
			Section(header: HeaderLabel(text: "Group", icon: "person.2.fill")) { triadToggles(\.group) }
			Section(header: HeaderLabel(text: "Others", icon: "globe")) { triadToggles(\.others) }

			Section(header: HeaderLabel(text: "Special", icon: "sparkles")) {
				PlainToggle(text: "Set UID", icon: "person.fill.viewfinder", isOn: $permissions.setUID)
				PlainToggle(text: "Set GID", icon: "person.3.fill", isOn: $permissions.setGID)
				PlainToggle(text: "Sticky", icon: "pin.fill", isOn: $permissions.sticky)
			}

			if node.isDirectory {
				Section {
					PlainToggle(text: "Apply to Enclosed Items", icon: "square.stack.3d.up.fill", isOn: $applyToEnclosedItems)
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
		PlainToggle(text: "Read", icon: "eye.fill", isOn: binding(keyPath, \.read))
		PlainToggle(text: "Write", icon: "pencil", isOn: binding(keyPath, \.write))
		PlainToggle(text: "Execute", icon: "play.fill", isOn: binding(keyPath, \.execute))
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
