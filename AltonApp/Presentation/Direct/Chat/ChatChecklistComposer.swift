import SwiftUI

struct ChatChecklistComposer: View {
    var onSend: (DMChecklist) -> Void

    @State private var title = ""
    @State private var items: [String] = [""]
    @State private var othersCanMark = true
    @State private var othersCanAdd = false
    @FocusState private var focusedIndex: Int?

    private var canSend: Bool {
        items.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                    .onChange(of: title) { _, newValue in
                        if newValue.count > 255 {
                            title = String(newValue.prefix(255))
                        }
                    }
            }
            Section("Items") {
                ForEach(items.indices, id: \.self) { index in
                    TextField("Item", text: binding(for: index))
                        .focused($focusedIndex, equals: index)
                        .onSubmit { addRow(after: index) }
                }
                .onDelete { offsets in
                    items.remove(atOffsets: offsets)
                    if items.isEmpty { items = [""] }
                }
                if items.count < 30 {
                    Button("Add Item", systemImage: "plus") {
                        addRow(after: items.count - 1)
                    }
                }
            }
            Section {
                Toggle("Others can mark", isOn: $othersCanMark)
                Toggle("Others can add items", isOn: $othersCanAdd)
            }
            Section {
                ChatComposerSendButton(isEnabled: canSend, action: send)
            }
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { items.indices.contains(index) ? items[index] : "" },
            set: { newValue in
                guard items.indices.contains(index) else { return }
                items[index] = String(newValue.prefix(100))
            }
        )
    }

    private func addRow(after index: Int) {
        guard items.count < 30 else { return }
        let insertAt = min(index + 1, items.count)
        items.insert("", at: insertAt)
        focusedIndex = insertAt
    }

    private func send() {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        let checklist = DMChecklist(
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255)),
            items: cleaned.enumerated().map { DMChecklistItem(id: $0.offset + 1, text: $0.element) },
            nextID: cleaned.count + 1,
            othersCanMark: othersCanMark,
            othersCanAdd: othersCanAdd
        )
        onSend(checklist)
    }
}

struct ChatComposerSendButton: View {
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Send")
                .font(.headline)
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color.primary.opacity(isEnabled ? 1 : 0.35),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }
}
