import SwiftUI

@MainActor
@Observable
final class PostActivityViewModel {
    var activity: PostActivity?
    var likers: [PostLiker] = []
    var isLoading = false
    var errorMessage: String?
    private var nextCursor: String?

    let postID: String
    let post: Post
    let currentUser: User?
    let activityUseCase: PostActivityUseCase
    let userUseCase: UserUseCase?

    init(
        postID: String,
        post: Post,
        currentUser: User?,
        activityUseCase: PostActivityUseCase,
        userUseCase: UserUseCase? = nil
    ) {
        self.postID = postID
        self.post = post
        self.currentUser = currentUser
        self.activityUseCase = activityUseCase
        self.userUseCase = userUseCase
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let activityTask = activityUseCase.fetchActivity(postID: postID)
            async let likersTask = activityUseCase.fetchLikers(postID: postID)
            activity = try await activityTask
            let likersPage = try await likersTask
            likers = likersPage.likers
            nextCursor = likersPage.nextCursor
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreLikersIfNeeded(current: PostLiker) async {
        guard let nextCursor, !nextCursor.isEmpty else { return }
        guard likers.last?.id == current.id else { return }

        do {
            let page = try await activityUseCase.fetchLikers(postID: postID, cursor: nextCursor)
            likers.append(contentsOf: page.likers)
            self.nextCursor = page.nextCursor
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct PostActivityView: View {
    @Bindable var viewModel: PostActivityViewModel
    var embeddedInSheet: Bool = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.activity == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        postPreview
                    }

                    if let activity = viewModel.activity {
                        Section {
                            NavigationLink {
                                PostLikersListView(
                                    postID: viewModel.postID,
                                    activityUseCase: viewModel.activityUseCase,
                                    userUseCase: viewModel.userUseCase
                                )
                            } label: {
                                activityRow(
                                    icon: "heart",
                                    title: "Likes",
                                    count: activity.likeCount
                                )
                            }

                            activityRow(
                                icon: "arrow.2.squarepath",
                                title: "Reposts",
                                count: activity.repostCount
                            )
                        }
                    }

                    Section("Likes") {
                        ForEach(viewModel.likers) { liker in
                            LikerRow(liker: liker, userUseCase: viewModel.userUseCase)
                                .onAppear {
                                    Task { await viewModel.loadMoreLikersIfNeeded(current: liker) }
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle(embeddedInSheet ? "" : "Post activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(embeddedInSheet ? .hidden : .automatic, for: .navigationBar)
        .task { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var postPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                UserHandleLabel.forPost(viewModel.post, currentUser: viewModel.currentUser)
                if let createdAt = viewModel.post.createdAt {
                    Text(PostRelativeTimestamp.string(from: createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let content = viewModel.post.listSnippet {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func activityRow(icon: String, title: String, count: Int) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }

}

private struct LikerRow: View {
    let liker: PostLiker
    let userUseCase: UserUseCase?
    @State private var isFollowing = false
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(.gray.gradient)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(liker.username.prefix(1).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink)
                    .padding(2)
                    .background(.white, in: Circle())
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(liker.username)
                        .font(.subheadline.weight(.semibold))
                    if let likedAt = liker.likedAt {
                        Text(PostRelativeTimestamp.string(from: likedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !liker.displayName.isEmpty, liker.displayName != liker.username {
                    Text(liker.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let userUseCase {
                Button(isFollowing ? "Following" : "Follow") {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do {
                            if isFollowing {
                                _ = try await userUseCase.unfollow(userID: liker.userID)
                                isFollowing = false
                            } else {
                                _ = try await userUseCase.follow(userID: liker.userID)
                                isFollowing = true
                            }
                        } catch {}
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isLoading)
            }
        }
        .padding(.vertical, 4)
    }

}

private struct PostLikersListView: View {
    let postID: String
    let activityUseCase: PostActivityUseCase
    let userUseCase: UserUseCase?
    @State private var likers: [PostLiker] = []
    @State private var nextCursor: String?
    @State private var isLoading = false

    var body: some View {
        List {
            ForEach(likers) { liker in
                LikerRow(liker: liker, userUseCase: userUseCase)
                    .onAppear { Task { await loadMoreIfNeeded(current: liker) } }
            }
        }
        .navigationTitle("Likes")
        .task { await loadInitial() }
    }

    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let page = try? await activityUseCase.fetchLikers(postID: postID) {
            likers = page.likers
            nextCursor = page.nextCursor
        }
    }

    private func loadMoreIfNeeded(current: PostLiker) async {
        guard let nextCursor, !nextCursor.isEmpty else { return }
        guard likers.last?.id == current.id else { return }
        if let page = try? await activityUseCase.fetchLikers(postID: postID, cursor: nextCursor) {
            likers.append(contentsOf: page.likers)
            self.nextCursor = page.nextCursor
        }
    }
}
