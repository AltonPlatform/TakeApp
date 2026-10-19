import SwiftUI

/// Multi-select up to 10 existing conversations to forward a message into.
struct ForwardPickerSheet: View {
    let messageID: String
    let deps: DirectShareDependencies
    let onForward: ([String]) -> Void

    @State private var recent: [DMConversation] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && recent.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if recent.isEmpty {
                    ContentUnavailableView(
                        "No chats yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a conversation first, then forward here.")
                    )
                } else {
                    List {
                        Section("Recent") {
                            ForEach(recent) { conversation in
                                Button {
                                    toggle(conversation.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: conversation.peerAvatarURL) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Circle().fill(Color.gray.opacity(0.2))
                                        }
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(
                                                conversation.peerDisplayName.isEmpty
                                                    ? conversation.peerUsername
                                                    : conversation.peerDisplayName
                                            )
                                            .foregroundStyle(.primary)
                                            Text("@\(conversation.peerUsername)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(conversation.id) ? Color.accentColor : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending…" : "Send") {
                        Task { await send() }
                    }
                    .disabled(selected.isEmpty || isSending)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await load() }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else if selected.count < 10 {
            selected.insert(id)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await deps.directUseCase.inbox(folder: "primary", cursor: nil)
            recent = page.conversations
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        onForward(Array(selected))
        dismiss()
    }
}
