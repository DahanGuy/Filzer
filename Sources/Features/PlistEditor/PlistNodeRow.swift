import PartyUI
import SwiftUI

struct PlistNodeRow: View {
	@Binding var node: PlistNode
	var title: String
	var onRename: (() -> Void)?
	var onDelete: (() -> Void)?

	@State private var showingTypePicker = false

	var body: some View {
		rowContent
			.swipeActions(edge: .trailing) {
				if let onDelete {
					Button(role: .destructive, action: onDelete) {
						Label("Delete", systemImage: "trash")
					}
				}
				if let onRename {
					Button(action: onRename) {
						Label("Rename", systemImage: "pencil")
					}
					.tint(.orange)
				}
			}
			.contextMenu { contextMenuItems }
			.confirmationDialog("Change Type", isPresented: $showingTypePicker, titleVisibility: .visible) {
				ForEach(PlistNode.Kind.allCases) { kind in
					Button(kind.title) { node = PlistNode.defaultValue(for: kind) }
				}
			}
	}

	@ViewBuilder
	private var rowContent: some View {
		switch node {
		case .dictionary:
			DisclosureGroup {
				dictionaryChildren
				Button {
					addDictionaryChild()
				} label: {
					Label("Add Item", systemImage: "plus.circle")
				}
			} label: {
				header
			}
		case .array:
			DisclosureGroup {
				arrayChildren
				Button {
					addArrayChild()
				} label: {
					Label("Add Item", systemImage: "plus.circle")
				}
			} label: {
				header
			}
		default:
			leafRow
		}
	}

	private var header: some View {
		HStack {
			Text(title)
			Spacer()
			Text(node.previewText)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}

	private var leafRow: some View {
		HStack {
			Text(title)
			Spacer()
			leafEditor
		}
	}

	@ViewBuilder
	private var leafEditor: some View {
		switch node {
		case .string(let value):
			TextField("Value", text: Binding(get: { value }, set: { node = .string($0) }))
				.multilineTextAlignment(.trailing)
		case .number(let value):
			TextField("Value", value: Binding(get: { value }, set: { node = .number($0) }), format: .number)
				.keyboardType(.decimalPad)
				.multilineTextAlignment(.trailing)
		case .boolean(let value):
			Toggle("", isOn: Binding(get: { value }, set: { node = .boolean($0) }))
				.labelsHidden()
		case .date(let value):
			DatePicker("", selection: Binding(get: { value }, set: { node = .date($0) }))
				.labelsHidden()
		case .data(let value):
			TextField(
				"Base64",
				text: Binding(
					get: { value.base64EncodedString() },
					set: { newValue in
						if let data = Data(base64Encoded: newValue) { node = .data(data) }
					}
				)
			)
			.multilineTextAlignment(.trailing)
			.font(.system(.footnote, design: .monospaced))
		case .array, .dictionary:
			EmptyView()
		}
	}

	@ViewBuilder
	private var contextMenuItems: some View {
		Button {
			showingTypePicker = true
		} label: {
			Label("Change Type", systemImage: "arrow.triangle.2.circlepath")
		}
		if let onRename {
			Button(action: onRename) {
				Label("Rename", systemImage: "pencil")
			}
		}
		if let onDelete {
			Button(role: .destructive, action: onDelete) {
				Label("Delete", systemImage: "trash")
			}
		}
	}

	@ViewBuilder
	private var dictionaryChildren: some View {
		if case .dictionary(let entries) = node {
			ForEach(entries) { entry in
				PlistNodeRow(
					node: dictionaryEntryBinding(id: entry.id),
					title: entry.key,
					onRename: { promptRenameKey(id: entry.id, currentKey: entry.key) },
					onDelete: { removeDictionaryEntry(id: entry.id) }
				)
			}
		}
	}

	private func dictionaryEntryBinding(id: UUID) -> Binding<PlistNode> {
		Binding(
			get: {
				guard case .dictionary(let entries) = node, let entry = entries.first(where: { $0.id == id }) else { return .string("") }
				return entry.value
			},
			set: { newValue in
				guard case .dictionary(var entries) = node, let index = entries.firstIndex(where: { $0.id == id }) else { return }
				entries[index].value = newValue
				node = .dictionary(entries)
			}
		)
	}

	private func addDictionaryChild() {
		guard case .dictionary(var entries) = node else { return }
		var key = "New Key"
		var counter = 2
		while entries.contains(where: { $0.key == key }) {
			key = "New Key \(counter)"
			counter += 1
		}
		entries.append(PlistDictionaryEntry(key: key, value: .string("")))
		node = .dictionary(entries)
	}

	private func removeDictionaryEntry(id: UUID) {
		guard case .dictionary(var entries) = node else { return }
		entries.removeAll { $0.id == id }
		node = .dictionary(entries)
	}

	private func promptRenameKey(id: UUID, currentKey: String) {
		Alertinator.shared.prompt(title: "Rename Key", placeholder: "Key", text: currentKey) { newKey in
			guard let newKey, !newKey.isEmpty, newKey != currentKey else { return }
			guard case .dictionary(var entries) = node, let index = entries.firstIndex(where: { $0.id == id }) else { return }
			entries[index].key = newKey
			node = .dictionary(entries)
		}
	}

	@ViewBuilder
	private var arrayChildren: some View {
		if case .array(let entries) = node {
			ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
				PlistNodeRow(
					node: arrayEntryBinding(id: entry.id),
					title: "Item \(offset)",
					onRename: nil,
					onDelete: { removeArrayEntry(id: entry.id) }
				)
			}
			.onMove(perform: moveArrayEntries)
		}
	}

	private func arrayEntryBinding(id: UUID) -> Binding<PlistNode> {
		Binding(
			get: {
				guard case .array(let entries) = node, let entry = entries.first(where: { $0.id == id }) else { return .string("") }
				return entry.value
			},
			set: { newValue in
				guard case .array(var entries) = node, let index = entries.firstIndex(where: { $0.id == id }) else { return }
				entries[index].value = newValue
				node = .array(entries)
			}
		)
	}

	private func addArrayChild() {
		guard case .array(var entries) = node else { return }
		entries.append(PlistArrayEntry(value: .string("")))
		node = .array(entries)
	}

	private func removeArrayEntry(id: UUID) {
		guard case .array(var entries) = node else { return }
		entries.removeAll { $0.id == id }
		node = .array(entries)
	}

	private func moveArrayEntries(from source: IndexSet, to destination: Int) {
		guard case .array(var entries) = node else { return }
		entries.move(fromOffsets: source, toOffset: destination)
		node = .array(entries)
	}
}
