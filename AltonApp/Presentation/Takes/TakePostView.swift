import SwiftUI

struct TakePostView: View {
    let item: FeedItem
    var currentUser: User?
    var container: DependencyContainer?
    var session: AuthSession?
    @Bindable var engagementController: PostEngagementController
    let commentsViewModelFactory: (Post) -> CommentsViewModel
    let onReply: (Post) -> Void
    var onDeleted: ((String) -> Void)? = nil
    var onOpenDetail: () -> Void = {}
    var onOpenMentionProfile: (String) -> Void = { _ in }

    @State private var post: Post
    @State private var showShareSheet = false
    @State private var hasRecordedView = false
    @State private var showReportSheet = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isTextExpanded = false

    init(
        item: FeedItem,
        currentUser: User?,
        container: DependencyContainer? = nil,
        session: AuthSession? = nil,
        engagementController: PostEngagementController,
        commentsViewModelFactory: @escaping (Post) -> CommentsViewModel,
        onReply: @escaping (Post) -> Void = { _ in },
        onDeleted: ((String) -> Void)? = nil,
        onOpenDetail: @escaping () -> Void = {},
        onOpenMentionProfile: @escaping (String) -> Void = { _ in }
    ) {
        self.item = item
        self.currentUser = currentUser
        self.container = container
        self.session = session
        self.engagementController = engagementController
        self.commentsViewModelFactory = commentsViewModelFactory
        self.onReply = onReply
        self.onDeleted = onDeleted
        self.onOpenDetail = onOpenDetail
        self.onOpenMentionProfile = onOpenMentionProfile
        _post = State(initialValue: item.post)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let repostedBy = item.repostedByDisplayName {
                HStack(spacing: 8) {
                    Image("post.reposted")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text("\(repostedBy) reposted")
                        .font(PostFont.repostLabel)
                        .foregroundStyle(PostColor.repostLabel)
                        .lineLimit(1)
                }
                .padding(.leading, 40)
            }

            HStack(alignment: .top, spacing: 8) {
                profileLink {
                    UserAvatarView(
                        user: User(
                            id: post.creatorID,
                            username: post.creatorUsername ?? "",
                            displayName: post.resolvedCreatorDisplayName(currentUser: currentUser),
                            bio: nil,
                            avatarURL: post.resolvedCreatorAvatarURL(currentUser: currentUser),
                            suiWallet: nil,
                            createdAt: nil
                        ),
                        size: 32
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    headerRow

                    AgeRestrictedMediaGate(isAgeGated: post.ageGated, contentID: post.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let content = post.content, !content.isEmpty {
                                let needsTruncation = content.count > 250
                                let isTruncated = needsTruncation && !isTextExpanded
                                VStack(alignment: .leading, spacing: 0) {
                                    TakeMarkdownContent(
                                        content: isTruncated
                                            ? Self.truncateAtWordBoundary(content, limit: 250)
                                            : content,
                                        onContentTap: { onOpenDetail() },
                                        onMentionTap: openMentionProfile
                                    )
                                    .clipped()
                                    if isTruncated {
                                        Button {
                                            isTextExpanded = true
                                        } label: {
                                            Text("Show More...")
                                                .font(PostFont.showMore)
                                                .foregroundStyle(PostColor.showMore)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Show More")
                                    }
                                }
                            }

                            mediaBlock
                        }
                    }
                    .id(post.id)

                    if let parent = item.quotedParent {
                        PostReplyEmbedCard(preview: parent, currentUser: currentUser) {
                            onOpenDetail()
                        }
                    }

                    PostActionBar(
                        post: post,
                        layout: .horizontal,
                        feedStyle: true,
                        onLike: { Task { await toggleLike() } },
                        onComment: { onReply(post) },
                        onRepost: { Task { await toggleRepost() } },
                        onShare: {
                            Task {
                                if await engagementController.prepareShare(postID: post.id) {
                                    showShareSheet = true
                                }
                            }
                        },
                        onBookmark: { Task { await toggleBookmark() } }
                    )
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deletePost() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
        .onAppear {
            guard !hasRecordedView else { return }
            hasRecordedView = true
            Task { await engagementController.recordView(postID: post.id, source: .feed) }
        }
        .onChange(of: item.post) { _, newPost in
            post = newPost
        }
        .sheet(isPresented: $showShareSheet) {
            if let payload = engagementController.makeSharePayload(for: post) {
                ActivityShareSheet(payload: payload) { completed, channel in
                    showShareSheet = false
                    if completed, let channel {
                        Task {
                            post = await engagementController.completeShare(
                                post: post,
                                channel: channel
                            )
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let container {
                ReportPostSheet(postID: post.id, userUseCase: container.userUseCase)
            }
        }
        .alert("Error", isPresented: .constant(engagementController.errorMessage != nil)) {
            Button("OK") { engagementController.errorMessage = nil }
        } message: {
            Text(engagementController.errorMessage ?? "")
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            profileLink {
                HStack(spacing: 8) {
                    Text(post.resolvedCreatorDisplayName(currentUser: currentUser))
                        .font(PostFont.name)
                        .foregroundStyle(PostColor.labelPrimary)
                        .lineLimit(1)
                    Text(post.resolvedAtUsername(currentUser: currentUser))
                        .font(PostFont.handle)
                        .foregroundStyle(PostColor.handle)
                        .lineLimit(1)
                    if let createdAt = post.createdAt {
                        Text(PostRelativeTimestamp.string(from: createdAt))
                            .font(PostFont.handle)
                            .foregroundStyle(PostColor.handle)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            PostContextMenuButton(
                post: post,
                feedStyle: true,
                onBookmark: { Task { await toggleBookmark() } },
                onRepost: { Task { await toggleRepost() } },
                onInsights: isOwnPost && container != nil ? { openInsights() } : nil,
                onDelete: isOwnPost ? { showDeleteConfirm = true } : nil,
                onReport: (!isOwnPost && post.canReport) ? { showReportSheet = true } : nil,
                onCopy: {}
            )
        }
    }

    @ViewBuilder
    private var mediaBlock: some View {
        if !post.imageURLs.isEmpty {
            PostMediaStripView(
                urls: post.imageURLs,
                post: post,
                currentUser: currentUser,
                engagementController: engagementController,
                commentsViewModelFactory: commentsViewModelFactory,
                session: session,
                container: container,
                onPostChange: { post = $0 }
            )
        } else if let thumbnailURL = post.thumbnailURL {
            PostMediaStripView(
                urls: [thumbnailURL],
                post: post,
                currentUser: currentUser,
                engagementController: engagementController,
                commentsViewModelFactory: commentsViewModelFactory,
                session: session,
                container: container,
                onPostChange: { post = $0 }
            )
        }
    }

    private func openInsights() {
        guard let container else { return }
        let viewModel = AnalyticsDashboardViewModel(
            postID: post.id,
            analyticsUseCase: container.analyticsUseCase
        )
        AltonSheetPresenter.present {
            PostSheetChrome(title: "Post insights", onClose: { AltonSheetPresenter.dismiss() }) {
                AnalyticsDashboardView(viewModel: viewModel, embeddedInSheet: true)
            }
        }
    }

    private var isOwnPost: Bool {
        guard let currentUser else { return false }
        return post.creatorID == currentUser.id
    }

    private func openMentionProfile(_ username: String) {
        guard let container else { return }
        Task {
            if let userID = await MentionNavigation.resolveUserID(
                username: username,
                searchUseCase: container.searchUseCase
            ) {
                onOpenMentionProfile(userID)
            } else {
                container.appState.showToast("User @\(username) not found")
            }
        }
    }

    private func toggleLike() async {
        let wasLiked = post.isLiked
        post = await engagementController.toggleLike(for: post)
        if !wasLiked, post.isLiked {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func toggleBookmark() async {
        post = await engagementController.toggleBookmark(for: post)
    }

    private func toggleRepost() async {
        post = await engagementController.toggleRepost(for: post)
    }

    private func deletePost() async {
        guard let container, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await container.postUseCase.deletePost(id: post.id)
            onDeleted?(post.id)
        } catch {
            engagementController.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        var truncated = String(text[..<endIndex])
        if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            truncated = String(truncated[..<lastSpace])
        }
        truncated = Self.trimIncompleteMarkdown(truncated)
        let trimmed = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? String(text.prefix(limit)) : trimmed) + "…"
    }

    private static func trimIncompleteMarkdown(_ text: String) -> String {
        var result = text

        if let openParen = result.lastIndex(of: "("),
           result[openParen...].contains(")") == false,
           let openBracket = result[..<openParen].lastIndex(of: "["),
           result[openBracket..<openParen].contains("]") {
            result = String(result[..<openBracket])
        }

        if let openBracket = result.lastIndex(of: "["),
           result[openBracket...].contains("]") == false {
            result = String(result[..<openBracket])
        }

        if result.hasSuffix("`") {
            var i = result.endIndex
            var ticks = 0
            while i > result.startIndex {
                let prev = result.index(before: i)
                if result[prev] == "`" {
                    ticks += 1
                    i = prev
                } else {
                    break
                }
            }
            if ticks % 2 == 1 {
                result = String(result[..<i])
            }
        }

        result = Self.trimTrailingUnpairedMarkers(result, marker: "*")
        result = Self.trimTrailingUnpairedMarkers(result, marker: "_")

        return result
    }

    private static func trimTrailingUnpairedMarkers(_ text: String, marker: Character) -> String {
        var result = text
        while result.last == marker {
            let total = result.filter { $0 == marker }.count
            guard total % 2 == 1 else { break }
            result.removeLast()
        }
        return result
    }

    @ViewBuilder
    private func profileLink<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let container, let session, post.creatorID != session.user.id {
            NavigationLink {
                UserProfileView(
                    userID: post.creatorID,
                    session: session,
                    container: container,
                    initialTab: .takes
                )
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }
}
