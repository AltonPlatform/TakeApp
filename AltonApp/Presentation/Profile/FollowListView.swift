import SwiftUI

enum FollowListMode: String, Sendable, Hashable, Identifiable {
    case followers
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }
}

@MainActor
@Observable
final class FollowListViewModel {
    private let userID: String
    private let mode: FollowListMode
    private let userUseCase: UserUseCase

    var users: [FollowUser] = []
    var isLoading = false
    var errorMessage: String?
    var hasMore = true
    private var cursor: String?

    init(userID: String, mode: FollowListMode, userUseCase: UserUseCase) {
        self.userID = userID
        self.mode = mode
        self.userUseCase = userUseCase
    }

    func load(reset: Bool = false) async {
        if reset {
            cursor = nil
            users = []
            hasMore = true
            errorMessage = nil
        }
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page: (users: [FollowUser], nextCursor: String?)
            switch mode {
            case .followers:
                page = try await userUseCase.listFollowers(userID: userID, cursor: cursor, limit: 30)
            case .following:
                page = try await userUseCase.listFollowing(userID: userID, cursor: cursor, limit: 30)
            }
            users.append(contentsOf: page.users)
            cursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }
}

struct FollowListView: View {
    @State private var viewModel: FollowListViewModel
    let session: AuthSession
    let container: DependencyContainer
    private let mode: FollowListMode

    init(
        userID: String,
        mode: FollowListMode,
        session: AuthSession,
        container: DependencyContainer
    ) {
        self.mode = mode
        self.session = session
        self.container = container
        _viewModel = State(initialValue: FollowListViewModel(
            userID: userID,
            mode: mode,
            userUseCase: container.userUseCase
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.users.isEmpty {
                ContentUnavailableView(
                    "Unable to load",
                    systemImage: "person.2",
                    description: Text(errorMessage)
                )
            } else if viewModel.users.isEmpty {
                ContentUnavailableView(
                    mode == .followers ? "No followers yet" : "Not following anyone",
                    systemImage: "person.2"
                )
            } else {
                List {
                    ForEach(viewModel.users) { user in
                        NavigationLink {
                            UserProfileView(
                                userID: user.id,
                                session: session,
                                container: container
                            )
                        } label: {
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
                                    size: 44
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName.isEmpty ? "@\(user.username)" : user.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("@\(user.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if viewModel.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await viewModel.load(reset: false) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(reset: true) }
        .refreshable { await viewModel.load(reset: true) }
    }
}
