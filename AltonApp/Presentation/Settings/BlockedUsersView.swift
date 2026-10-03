import SwiftUI

struct BlockedUsersView: View {
    let userUseCase: UserUseCase

    @State private var users: [BlockedUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView("Loading blocked users...")
            } else if let errorMessage, users.isEmpty {
                ContentUnavailableView(
                    "Unable to load",
                    systemImage: "hand.raised",
                    description: Text(errorMessage)
                )
            } else if users.isEmpty {
                ContentUnavailableView("No blocked users", systemImage: "hand.raised")
            } else {
                List {
                    ForEach(users) { user in
                        HStack(spacing: 12) {
                            UserAvatarView(
                                user: User(
                                    id: user.id,
                                    username: user.username,
                                    displayName: user.displayName,
                                    bio: nil,
                                    avatarURL: user.avatarURL,
                                    suiWallet: nil,
                                    createdAt: nil
                                ),
                                size: 40
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unblock") {
                                Task { await unblock(user) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Blocked")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            users = try await userUseCase.listBlockedUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unblock(_ user: BlockedUser) async {
        do {
            try await userUseCase.unblockUser(userID: user.id)
            users.removeAll { $0.id == user.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
