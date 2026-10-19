import SwiftUI

private struct FeedItemNavigation: Identifiable, Hashable {
    let id: String
    let item: FeedItem
    let focusComposer: Bool

    init(item: FeedItem, focusComposer: Bool = false) {
        self.id = focusComposer ? "\(item.id)-compose" : item.id
        self.item = item
        self.focusComposer = focusComposer
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FeedItemNavigation, rhs: FeedItemNavigation) -> Bool {
        lhs.id == rhs.id
    }
}

struct TakesFeedView: View {
    @Bindable var viewModel: TakesFeedViewModel
    let session: AuthSession
    let container: DependencyContainer
    let onCompose: () -> Void
    var onSearch: (() -> Void)?

    @State private var detailItem: FeedItemNavigation?
    @State private var mentionProfileUserID: String?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                LoadingView(message: "Loading takes...")
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                VStack(spacing: 0) {
                    inlineComposer
                    ErrorView(message: errorMessage) {
                        Task { await viewModel.loadInitial() }
                    }
                }
            } else {
                feedScroll
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onSearch?()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
            ToolbarItem(placement: .principal) {
                Picker("Feed", selection: Binding(
                    get: { viewModel.feedMode },
                    set: { newMode in Task { await viewModel.switchFeedMode(newMode) } }
                )) {
                    Text("For You").tag(FeedMode.forYou)
                    Text("Following").tag(FeedMode.following)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }
        }
        .task {
            async let adsReady: Void = CASManager.shared.waitUntilReady()
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            }
            await adsReady
            NativeAdPool.shared.warmUp()
        }
        .navigationDestination(item: $detailItem) { navigation in
            TakePostDetailView(
                item: navigation.item,
                currentUser: session.user,
                container: container,
                session: session,
                userUseCase: container.userUseCase,
                engagementController: viewModel.engagementController,
                commentsViewModelFactory: { viewModel.makeCommentsViewModel(for: $0, userID: session.user.id) },
                analyticsUseCase: container.analyticsUseCase,
                postUseCase: container.postUseCase,
                onDeleted: { viewModel.removePost(id: navigation.item.id) },
                focusComposerOnAppear: navigation.focusComposer
            )
        }
        .navigationDestination(item: $mentionProfileUserID) { userID in
            UserProfileView(userID: userID, session: session, container: container)
        }
    }

    private var feedScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                inlineComposer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                if viewModel.displayRows.isEmpty {
                    ContentUnavailableView(
                        "No takes yet",
                        systemImage: "text.bubble",
                        description: Text("Be the first to start a conversation.")
                    )
                    .padding(.vertical, 40)
                }

                ForEach(viewModel.displayRows) { row in
                    Group {
                        switch row {
                        case .timeline(let item):
                            switch item {
                            case .post(let feedItem):
                                TakePostView(
                                    item: feedItem,
                                    currentUser: session.user,
                                    container: container,
                                    session: session,
                                    engagementController: viewModel.engagementController,
                                    commentsViewModelFactory: { viewModel.makeCommentsViewModel(for: $0, userID: session.user.id) },
                                    onReply: { _ in
                                        detailItem = FeedItemNavigation(item: feedItem, focusComposer: true)
                                    },
                                    onDeleted: { id in
                                        viewModel.removePost(id: id)
                                    },
                                    onOpenDetail: {
                                        detailItem = FeedItemNavigation(item: feedItem, focusComposer: false)
                                    },
                                    onOpenMentionProfile: { userID in
                                        mentionProfileUserID = userID
                                    }
                                )
                            case .reply(let replyItem):
                                FeedReplyView(
                                    item: replyItem,
                                    currentUser: session.user,
                                    container: container,
                                    session: session,
                                    engagementController: viewModel.engagementController,
                                    onReply: { post in
                                        detailItem = FeedItemNavigation(
                                            item: FeedItem(
                                                post: post,
                                                finalScore: 0,
                                                userScore: 0,
                                                creatorScore: 0,
                                                brandScore: 0
                                            ),
                                            focusComposer: true
                                        )
                                    },
                                    onOpenMentionProfile: { userID in
                                        mentionProfileUserID = userID
                                    },
                                    onOpenParent: { post in
                                        detailItem = FeedItemNavigation(
                                            item: FeedItem(
                                                post: post,
                                                finalScore: 0,
                                                userScore: 0,
                                                creatorScore: 0,
                                                brandScore: 0
                                            ),
                                            focusComposer: false
                                        )
                                    }
                                )
                            }
                        case .nativeAd(let placementID, let position):
                            NativeAdView(
                                placementID: placementID,
                                adRepository: container.adRepository,
                                adjacentPostID: adjacentPostID(beforePosition: position),
                                feedSessionID: AppSessionTracker.shared.sessionID
                            )
                        }
                    }
                    .onAppear {
                        if case .timeline(let item) = row {
                            Task { await viewModel.loadMoreIfNeeded(currentItem: item) }
                            viewModel.prefetchAhead(currentItem: item)
                        }
                    }

                    Divider()
                        .overlay(PostColor.border)
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if viewModel.isExhausted && !viewModel.items.isEmpty {
                    Text("You've seen everything")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var inlineComposer: some View {
        InlineTakeComposerRow(user: session.user, onTap: onCompose)
    }

    private func adjacentPostID(beforePosition: Int) -> String? {
        var postIndex = 0
        for item in viewModel.items {
            guard case .post(let feedItem) = item else { continue }
            postIndex += 1
            if postIndex == beforePosition {
                return feedItem.post.id
            }
        }
        return nil
    }
}

private struct InlineTakeComposerRow: View {
    let user: User
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    UserAvatarView(user: user, size: 40)

                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 8)
                }
                .frame(width: 40)

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("What's new?")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
