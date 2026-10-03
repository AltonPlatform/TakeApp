import NukeUI
import SwiftUI

struct ActivityView: View {
    @Bindable var viewModel: ActivityViewModel
    let session: AuthSession
    let container: DependencyContainer

    @State private var profileUserID: String?
    @State private var deepLinkPost: ActivityPostDestination?
    @State private var blockedOpenMessage: String?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    "Couldn't load activity",
                    systemImage: "bell.slash",
                    description: Text(errorMessage)
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "Nothing new yet",
                    systemImage: "bell",
                    description: Text("Likes, comments, follows and mentions will show up here.")
                )
            } else {
                List {
                    if !viewModel.recent7Days.isEmpty {
                        Section {
                            ForEach(viewModel.recent7Days) { item in
                                row(for: item)
                            }
                        } header: {
                            Text("Last 7 days")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }

                    if !viewModel.older30Days.isEmpty {
                        Section {
                            ForEach(viewModel.older30Days) { item in
                                row(for: item)
                            }
                        } header: {
                            Text("Last 30 days")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }

                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") {
                        Task { await viewModel.markAllRead() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .refreshable { await viewModel.refresh() }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            } else if viewModel.shouldAutoRefresh {
                await viewModel.refresh()
            }
        }
        .navigationDestination(item: $profileUserID) { userID in
            UserProfileView(userID: userID, session: session, container: container)
        }
        .navigationDestination(item: $deepLinkPost) { destination in
            TakePostDetailView(
                item: destination.item,
                currentUser: session.user,
                container: container,
                session: session,
                userUseCase: container.userUseCase,
                engagementController: container.makeEngagementController(),
                commentsViewModelFactory: { post in
                    container.makeCommentsViewModel(postID: post.id, currentUserID: session.user.id)
                },
                analyticsUseCase: container.analyticsUseCase,
                postUseCase: container.postUseCase
            )
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil && !viewModel.items.isEmpty },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(
            "Can't open post",
            isPresented: Binding(
                get: { blockedOpenMessage != nil },
                set: { if !$0 { blockedOpenMessage = nil } }
            )
        ) {
            Button("OK") { blockedOpenMessage = nil }
        } message: {
            Text(blockedOpenMessage ?? "")
        }
    }

    @ViewBuilder
    private func row(for item: NotificationItem) -> some View {
        Button {
            Task { await handleTap(item) }
        } label: {
            ActivityRow(
                item: item,
                onFollowBack: item.actorID.map { actorID in
                    { Task { await viewModel.followBack(actorID: actorID) } }
                },
                onAppeal: item.canAppeal ? {
                    Task { await viewModel.appealComment(item) }
                } : nil,
                onAppear: {
                    Task {
                        await viewModel.markRead(item)
                        await viewModel.loadMoreIfNeeded(current: item)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func handleTap(_ item: NotificationItem) async {
        await viewModel.markRead(item)
        switch item.type {
        case .follow, .profileView:
            if let actorID = item.actorID {
                profileUserID = actorID
            }
        case .like, .comment, .repost, .mention, .reply, .commentRemoved:
            guard let postID = item.postID else { return }
            do {
                let post = try await container.postUseCase.fetchPost(id: postID)
                if let blocked = ViewerContentFilterPolicy.blockedOpenMessage(
                    for: post,
                    viewerIsAdult: session.user.isAdult,
                    showSensitiveContent: session.user.showSensitiveContent
                ) {
                    blockedOpenMessage = blocked
                    return
                }
                let feedItem = FeedItem(
                    post: post,
                    finalScore: 0,
                    userScore: 0,
                    creatorScore: 0,
                    brandScore: 0
                )
                deepLinkPost = ActivityPostDestination(item: feedItem)
            } catch {
                viewModel.errorMessage = "Couldn't open this post."
            }
        }
    }
}

private struct ActivityPostDestination: Identifiable, Hashable {
    var id: String { item.post.id }
    let item: FeedItem

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ActivityPostDestination, rhs: ActivityPostDestination) -> Bool {
        lhs.id == rhs.id
    }
}
