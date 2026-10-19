import SwiftUI

struct NewMessageView: View {
    @State var viewModel: NewMessageViewModel
    @Environment(\.dismiss) private var dismiss
    var onOpened: (DMConversation) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.displayedUsers.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.displayedUsers.isEmpty {
                    ContentUnavailableView(
                        viewModel.isSearchMode ? "No users found" : "No following yet",
                        systemImage: "person.2",
                        description: Text(
                            viewModel.isSearchMode
                                ? "Try a different name or username."
                                : "Follow people to message them quickly, or search above."
                        )
                    )
                } else {
                    List {
                        if !viewModel.isSearchMode {
                            Section("Following") {
                                userRows
                            }
                        } else {
                            userRows
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $viewModel.query, prompt: "Search people")
            .onChange(of: viewModel.query) { _ in
                viewModel.onQueryChanged()
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await viewModel.loadFollowing() }
            .alert("Couldn't open chat", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.openedConversation?.id) { _ in
                guard let conversation = viewModel.openedConversation else { return }
                onOpened(conversation)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var userRows: some View {
        ForEach(viewModel.displayedUsers) { user in
            HStack(spacing: 12) {
                AsyncImage(url: user.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName.isEmpty ? user.username : user.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await viewModel.openChat(with: user) }
            }
        }
        if !viewModel.isSearchMode, viewModel.followingCursor != nil {
            ProgressView()
                .frame(maxWidth: .infinity)
                .task { await viewModel.loadMoreFollowing() }
        }
    }
}
