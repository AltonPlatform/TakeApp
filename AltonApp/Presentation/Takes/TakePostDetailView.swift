import SwiftUI
import PhotosUI

struct TakePostDetailView: View {
    private enum CommentSort: String, CaseIterable, Identifiable {
        case relevant
        case latest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .relevant: return "Relevant"
            case .latest: return "Latest"
            }
        }
    }

    let item: FeedItem
    let currentUser: User?
    var container: DependencyContainer?
    var session: AuthSession?
    let userUseCase: UserUseCase?
    @Bindable var engagementController: PostEngagementController
    let commentsViewModelFactory: (Post) -> CommentsViewModel
    /// When opened via the comment action (not the post body), focus Write comment + keyboard.
    var focusComposerOnAppear: Bool = false

    @State private var post: Post
    @State private var commentsViewModel: CommentsViewModel
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var hasRecordedView = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var mentionProfileUserID: String?
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    @State private var commentSort: CommentSort = .relevant
    @State private var showFullComposer = false
    @State private var showStickerPicker = false
    @State private var showGIFPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var mentionPicker: MentionPickerModel
    @State private var didApplyComposerFocus = false
    @FocusState private var isComposerFocused: Bool
    private static let composerBarHeight: CGFloat = 76
    @State private var dismissController = KeyboardDismissController()
    @Environment(\.dismiss) private var dismiss

    init(
        item: FeedItem,
        currentUser: User?,
        container: DependencyContainer? = nil,
        session: AuthSession? = nil,
        userUseCase: UserUseCase? = nil,
        engagementController: PostEngagementController,
        commentsViewModelFactory: @escaping (Post) -> CommentsViewModel,
        analyticsUseCase: PostAnalyticsUseCase? = nil,
        postUseCase: PostUseCase? = nil,
        onDeleted: (() -> Void)? = nil,
        focusComposerOnAppear: Bool = false
    ) {
        self.item = item
        self.currentUser = currentUser
        self.container = container
        self.session = session
        self.userUseCase = userUseCase
        self.engagementController = engagementController
        self.commentsViewModelFactory = commentsViewModelFactory
        self.analyticsUseCase = analyticsUseCase
        self.postUseCase = postUseCase
        self.onDeleted = onDeleted
        self.focusComposerOnAppear = focusComposerOnAppear
        _post = State(initialValue: item.post)
        _commentsViewModel = State(initialValue: commentsViewModelFactory(item.post))
        _mentionPicker = State(initialValue: MentionPickerModel(searchUseCase: container?.searchUseCase))
    }

    private let analyticsUseCase: PostAnalyticsUseCase?
    private let postUseCase: PostUseCase?
    private let onDeleted: (() -> Void)?

    private var isOwnPost: Bool {
        guard let currentUser else { return false }
        return post.creatorID == currentUser.id
    }

    private var remainingAttachmentSlots: Int {
        max(0, CommentsUseCase.maxAttachments - commentsViewModel.attachments.count)
    }

    private var sortedComments: [CommentTakeItem] {
        let items = commentsViewModel.takeComments
        var roots: [CommentTakeItem] = []
        var repliesByRoot: [String: [CommentTakeItem]] = [:]
        var currentRootID: String?

        for item in items {
            if item.depth == 0 {
                currentRootID = item.comment.id
                roots.append(item)
            } else if let currentRootID {
                repliesByRoot[currentRootID, default: []].append(item)
            }
        }

        switch commentSort {
        case .relevant:
            roots.sort { lhs, rhs in
                if lhs.comment.likeCount != rhs.comment.likeCount {
                    return lhs.comment.likeCount > rhs.comment.likeCount
                }
                let l = lhs.comment.createdAt ?? .distantPast
                let r = rhs.comment.createdAt ?? .distantPast
                return l > r
            }
        case .latest:
            roots.sort { lhs, rhs in
                let l = lhs.comment.createdAt ?? .distantPast
                let r = rhs.comment.createdAt ?? .distantPast
                if l != r { return l > r }
                return lhs.comment.id > rhs.comment.id
            }
        }

        var result: [CommentTakeItem] = []
        for root in roots {
            result.append(root)
            result.append(contentsOf: repliesByRoot[root.comment.id] ?? [])
        }
        return result
    }

    var body: some View {
        @Bindable var commentsViewModel = commentsViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                postSection
                infoRow
                commentsSection
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .liquidGlassKeyboardDismiss(controller: dismissController, bottomInset: Self.composerBarHeight)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("nav.take")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 24)
                    .foregroundStyle(PostColors.labelPrimary)
                    .accessibilityLabel("Take")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if post.viewCount > 0 {
                        HStack(spacing: 4) {
                            Text(formatCount(post.viewCount))
                                .font(PostTypography.medium(14, relativeTo: .subheadline))
                                .foregroundStyle(PostColors.labelSecondary)
                            Image("post.eye")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(PostColors.labelSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(formatCount(post.viewCount)) views")
                    }

                    PostContextMenuButton(
                        post: post,
                        feedStyle: true,
                        onBookmark: { Task { await toggleBookmark() } },
                        onRepost: { Task { await toggleRepost() } },
                        onInsights: isOwnPost && analyticsUseCase != nil ? { openInsights() } : nil,
                        onActivity: { openActivity() },
                        onDelete: isOwnPost && postUseCase != nil ? { showDeleteConfirm = true } : nil,
                        onReport: (!isOwnPost && post.canReport) ? { showReportSheet = true } : nil,
                        onCopy: {}
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            writeCommentBar(viewModel: commentsViewModel)
        }
        .task {
            commentsViewModel.currentUserAvatarURL = currentUser?.avatarURL
            await commentsViewModel.loadInitial()
            await loadFollowState()
            await focusComposerIfNeeded()
        }
        .onAppear {
            guard !hasRecordedView else { return }
            hasRecordedView = true
            Task { await engagementController.recordView(postID: post.id, source: .internalLink) }
        }
        .onChange(of: item.post) { _, newPost in
            post = newPost
        }
        .onChange(of: commentsViewModel.draft) { _, newValue in
            mentionPicker.update(from: newValue)
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadSelectedPhotos(items) }
        }
        .fullScreenCover(isPresented: $showFullComposer) {
            CommentComposerFullScreenView(
                draft: $commentsViewModel.draft,
                attachments: $commentsViewModel.attachments,
                pendingSticker: $commentsViewModel.pendingSticker,
                pendingGIF: $commentsViewModel.pendingGIF,
                isSubmitting: commentsViewModel.isSubmitting,
                searchUseCase: container?.searchUseCase,
                stickersUseCase: container?.stickersUseCase,
                onCancel: { showFullComposer = false },
                onSubmit: {
                    Task {
                        await submitComment()
                        if commentsViewModel.errorMessage == nil {
                            showFullComposer = false
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showStickerPicker) {
            if let stickersUseCase = container?.stickersUseCase {
                CommentStickerPickerSheet(stickersUseCase: stickersUseCase) { sticker in
                    commentsViewModel.setPendingSticker(sticker)
                    let sendNow = commentsViewModel.draft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        && commentsViewModel.attachments.isEmpty
                    if sendNow {
                        Task { await submitComment() }
                    }
                }
            }
        }
        .sheet(isPresented: $showGIFPicker) {
            CommentGIFPickerSheet { gif in
                commentsViewModel.enqueuePickedGIF(gif)
            }
        }
        .navigationDestination(item: $mentionProfileUserID) { userID in
            if let session, let container {
                UserProfileView(userID: userID, session: session, container: container)
            }
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteOwnPost() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
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
            if let userUseCase {
                ReportPostSheet(postID: post.id, userUseCase: userUseCase)
            }
        }
        .alert("Error", isPresented: .constant(engagementController.errorMessage != nil || commentsViewModel.errorMessage != nil)) {
            Button("OK") {
                engagementController.errorMessage = nil
                commentsViewModel.errorMessage = nil
            }
        } message: {
            Text(engagementController.errorMessage ?? commentsViewModel.errorMessage ?? "")
        }
    }

    private var postSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            authorHeader

            AgeRestrictedMediaGate(isAgeGated: post.ageGated, contentID: post.id) {
                VStack(alignment: .leading, spacing: 8) {
                    if let content = post.content, !content.isEmpty {
                        TakeMarkdownContent(
                            content: content,
                            onMentionTap: openMentionProfile
                        )
                    }

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
            }
            .id(post.id)

            if let parent = item.quotedParent {
                PostReplyEmbedCard(preview: parent, currentUser: currentUser)
            }

            PostActionBar(
                post: post,
                layout: .horizontal,
                feedStyle: true,
                onLike: { Task { await toggleLike() } },
                onComment: { focusComposer(replyTo: nil) },
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
        .padding(12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var authorHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                openAuthorProfile(post.creatorID)
            } label: {
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
                    size: 40
                )
            }
            .buttonStyle(.plain)

            Button {
                openAuthorProfile(post.creatorID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.resolvedCreatorDisplayName(currentUser: currentUser))
                        .font(PostTypography.semiBold(16, relativeTo: .headline))
                        .foregroundStyle(PostColors.labelPrimary)
                        .lineLimit(1)
                    Text(post.resolvedAtUsername(currentUser: currentUser))
                        .font(PostTypography.handle)
                        .foregroundStyle(PostColors.handle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !isOwnPost, userUseCase != nil {
                Button {
                    Task { await toggleFollow() }
                } label: {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(PostTypography.semiBold(14, relativeTo: .subheadline))
                        .foregroundStyle(isFollowing ? PostColors.labelPrimary : Color(.systemBackground))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isFollowing ? PostColors.border : PostColors.labelPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isFollowLoading)
            }
        }
    }

    private var infoRow: some View {
        HStack(spacing: 20) {
            Menu {
                ForEach(CommentSort.allCases) { sort in
                    Button {
                        commentSort = sort
                    } label: {
                        HStack {
                            Text(sort.title)
                            if commentSort == sort {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(commentSort.title)
                        .font(PostTypography.medium(14, relativeTo: .subheadline))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .foregroundStyle(PostColors.labelSecondary)
            }

            Spacer(minLength: 0)

            if let createdAt = post.createdAt {
                Text(PostRelativeTimestamp.absoluteString(from: createdAt))
                    .font(PostTypography.regular(14, relativeTo: .subheadline))
                    .foregroundStyle(PostColors.handle)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: openActivity) {
                HStack(spacing: 4) {
                    Text("Activity")
                        .font(PostTypography.medium(14, relativeTo: .subheadline))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .foregroundStyle(PostColors.labelSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        if commentsViewModel.isLoading && commentsViewModel.comments.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if commentsViewModel.comments.isEmpty {
            Text("No replies yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sortedComments) { item in
                    TakeDetailCommentRow(
                        comment: item.comment,
                        currentUser: currentUser,
                        replyCount: replyCount(for: item.comment.id),
                        isOwner: item.comment.authorID == commentsViewModel.currentUserID,
                        depth: item.depth,
                        onAuthorTap: { openAuthorProfile(item.comment.authorID) },
                        onMentionTap: openMentionProfile,
                        onLike: { Task { await commentsViewModel.toggleCommentLike(comment: item.comment) } },
                        onReply: { focusComposer(replyTo: item.comment) },
                        onDelete: { Task { await commentsViewModel.delete(comment: item.comment) } }
                    )
                    .onAppear {
                        Task { await commentsViewModel.loadMoreIfNeeded(current: item.comment) }
                    }

                    Divider()
                }

                if commentsViewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private func replyCount(for commentID: String) -> Int {
        commentsViewModel.comments.filter { $0.parentCommentID == commentID }.count
    }

    private func focusComposer(replyTo: Comment?) {
        if let replyTo {
            commentsViewModel.beginReply(to: replyTo)
        } else {
            commentsViewModel.clearReplyTarget()
        }
        isComposerFocused = true
    }

    private func focusComposerIfNeeded() async {
        guard focusComposerOnAppear, !didApplyComposerFocus else { return }
        didApplyComposerFocus = true
        // Wait for navigation transition so the text field can become first responder.
        try? await Task.sleep(for: .milliseconds(350))
        isComposerFocused = true
    }

    @ViewBuilder
    private func writeCommentBar(viewModel: CommentsViewModel) -> some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if mentionPicker.isVisible {
                MentionAutocompleteView(users: mentionPicker.users) { user in
                    var draft = viewModel.draft
                    mentionPicker.insert(user, into: &draft)
                    viewModel.draft = draft
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            if viewModel.replyParentCommentID != nil {
                HStack {
                    Text("Replying")
                        .font(PostTypography.medium(12, relativeTo: .caption))
                        .foregroundStyle(PostColors.labelSecondary)
                    Spacer()
                    Button("Cancel") {
                        viewModel.clearReplyTarget()
                    }
                    .font(PostTypography.medium(12, relativeTo: .caption))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if let pending = viewModel.pendingSticker {
                PendingStickerChip(sticker: pending) {
                    viewModel.clearPendingSticker()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if let pending = viewModel.pendingGIF {
                PendingGIFChip(gif: pending) {
                    viewModel.clearPendingGIF()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            if !viewModel.attachments.isEmpty {
                ComposerAttachmentStrip(
                    attachments: viewModel.attachments,
                    onRemove: { viewModel.removeAttachment($0) }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Figma `make-reply` (11432:37000): pill, avatar 48, “Write a comment…”, image / sticker / GIF / expand.
            HStack(spacing: 12) {
                if let currentUser {
                    UserAvatarView(user: currentUser, size: 40)
                        .frame(width: 48, height: 48)
                } else {
                    Circle()
                        .fill(PostColors.border)
                        .frame(width: 40, height: 40)
                        .frame(width: 48, height: 48)
                }

                TextField("Write a comment...", text: $viewModel.draft, axis: .vertical)
                    .font(PostTypography.semiBold(14, relativeTo: .subheadline))
                    .foregroundStyle(PostColors.labelPrimary)
                    .lineLimit(1...3)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        Task { await submitComment() }
                    }

                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: max(1, remainingAttachmentSlots),
                        matching: .images
                    ) {
                        Image("comment.image")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(PostColors.labelPrimary)
                    }
                    .disabled(remainingAttachmentSlots == 0)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach photos")

                    Button {
                        showStickerPicker = true
                    } label: {
                        Image("comment.sticker")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(PostColors.labelPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(container?.stickersUseCase == nil)
                    .accessibilityLabel("Stickers")

                    Button {
                        showGIFPicker = true
                    } label: {
                        ZStack {
                            Image("comment.gif")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("GIF")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(PostColors.labelPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("GIF")

                    Button {
                        showFullComposer = true
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .frame(width: 24, height: 24)
                        } else {
                            Image("comment.expand")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundStyle(PostColors.labelPrimary)
                        }
                    }
                    .disabled(viewModel.isSubmitting)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand composer")

                    if viewModel.canSubmitDraft {
                        Button {
                            Task { await submitComment() }
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(PostColors.labelPrimary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSubmitting)
                        .accessibilityLabel("Send comment")
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 20)
            .padding(.vertical, 6)
            .frame(minHeight: 60)
            .background(
                PostColors.labelPrimary.opacity(0.04),
                in: Capsule()
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Divider().overlay(PostColors.border)
        }
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        guard remainingAttachmentSlots > 0 else { return }
        guard await DevicePermissions.requestPhotoLibraryAccess() else {
            commentsViewModel.errorMessage = "Photo library access is required to attach media."
            return
        }

        var loaded: [PostAttachment] = []
        for item in items.prefix(remainingAttachmentSlots) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let contentType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let ext = contentType.contains("png") ? "png" : "jpg"
            loaded.append(
                PostAttachment(
                    id: UUID(),
                    data: data,
                    contentType: contentType,
                    filename: "comment-\(UUID().uuidString).\(ext)",
                    pickerItemID: nil
                )
            )
        }
        commentsViewModel.appendAttachments(loaded)
    }

    private func submitComment() async {
        let previousCount = commentsViewModel.comments.count
        await commentsViewModel.submit()
        if commentsViewModel.errorMessage == nil, commentsViewModel.comments.count > previousCount {
            post = post.updatingEngagement(commentCount: post.commentCount + 1)
            isComposerFocused = false
        }
    }

    private func loadFollowState() async {
        guard !isOwnPost, let userUseCase else { return }
        do {
            let profile = try await userUseCase.loadProfile(userID: post.creatorID)
            isFollowing = profile.isFollowing
        } catch {
            // Keep default; follow button still works optimistically.
        }
    }

    private func toggleFollow() async {
        guard let userUseCase, !isFollowLoading else { return }
        isFollowLoading = true
        defer { isFollowLoading = false }
        do {
            if isFollowing {
                _ = try await userUseCase.unfollow(userID: post.creatorID)
                isFollowing = false
            } else {
                _ = try await userUseCase.follow(userID: post.creatorID)
                isFollowing = true
            }
        } catch {
            engagementController.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func openMentionProfile(_ username: String) {
        guard let container else { return }
        Task {
            if let userID = await MentionNavigation.resolveUserID(
                username: username,
                searchUseCase: container.searchUseCase
            ) {
                mentionProfileUserID = userID
            } else {
                container.appState.showToast("User @\(username) not found")
            }
        }
    }

    private func openAuthorProfile(_ userID: String) {
        guard session != nil, container != nil, !userID.isEmpty else { return }
        mentionProfileUserID = userID
    }

    private func openInsights() {
        guard let analyticsUseCase else { return }
        let viewModel = AnalyticsDashboardViewModel(
            postID: post.id,
            analyticsUseCase: analyticsUseCase
        )
        AltonSheetPresenter.present {
            PostSheetChrome(title: "Post insights", onClose: { AltonSheetPresenter.dismiss() }) {
                AnalyticsDashboardView(viewModel: viewModel, embeddedInSheet: true)
            }
        }
    }

    private func openActivity() {
        let viewModel = PostActivityViewModel(
            postID: post.id,
            post: post,
            currentUser: currentUser,
            activityUseCase: commentsViewModelFactory(post).activityUseCase,
            userUseCase: userUseCase
        )
        AltonSheetPresenter.present {
            PostSheetChrome(title: "Post activity", onClose: { AltonSheetPresenter.dismiss() }) {
                NavigationStack {
                    PostActivityView(viewModel: viewModel, embeddedInSheet: true)
                }
            }
        }
    }

    private func toggleLike() async {
        post = await engagementController.toggleLike(for: post)
    }

    private func toggleBookmark() async {
        post = await engagementController.toggleBookmark(for: post)
    }

    private func toggleRepost() async {
        post = await engagementController.toggleRepost(for: post)
    }

    private func deleteOwnPost() async {
        guard let postUseCase, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await postUseCase.deletePost(id: post.id)
            onDeleted?()
            dismiss()
        } catch {
            engagementController.errorMessage =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

/// Comment card matching feed post chrome (Figma comment-as-post).
struct TakeDetailCommentRow: View {
    let comment: Comment
    var currentUser: User? = nil
    var replyCount: Int = 0
    let isOwner: Bool
    var depth: Int = 0
    var onAuthorTap: (() -> Void)? = nil
    var onMentionTap: ((String) -> Void)? = nil
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void

    @State private var showShareSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if depth > 0 {
                Color.clear.frame(width: CGFloat(depth) * 20)
            }

            authorTappable {
                UserAvatarView(user: comment.authorAsUser(currentUser: currentUser), size: 32)
            }

            VStack(alignment: .leading, spacing: 8) {
                headerRow

                if !comment.content.isEmpty {
                    TakeMarkdownContent(
                        content: comment.content,
                        onContentTap: onReply,
                        onMentionTap: onMentionTap
                    )
                }

                if let sticker = comment.sticker {
                    CommentStickerImageView(sticker: sticker)
                }

                if let gif = comment.gif {
                    CommentGifImageView(gif: gif)
                }

                if !comment.imageURLs.isEmpty {
                    PostMediaStripView(urls: comment.imageURLs)
                }

                PostActionBar(
                    metrics: .init(
                        likeCount: comment.likeCount,
                        isLiked: comment.isLiked,
                        commentCount: replyCount
                    ),
                    layout: .horizontal,
                    feedStyle: true,
                    onLike: onLike,
                    onComment: onReply,
                    onRepost: {},
                    onShare: { showShareSheet = true },
                    onBookmark: {}
                )
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(items: [comment.content]) { _ in
                showShareSheet = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            authorTappable {
                HStack(spacing: 8) {
                    Text(comment.resolvedDisplayName)
                        .font(PostTypography.name)
                        .foregroundStyle(PostColors.labelPrimary)
                        .lineLimit(1)
                    if let at = comment.atUsername {
                        Text(at)
                            .font(PostTypography.handle)
                            .foregroundStyle(PostColors.handle)
                            .lineLimit(1)
                    }
                    if let createdAt = comment.createdAt {
                        Text(PostRelativeTimestamp.string(from: createdAt))
                            .font(PostTypography.handle)
                            .foregroundStyle(PostColors.handle)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    UIPasteboard.general.string = comment.content
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if isOwner {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image("post.more")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(PostColors.labelSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("More")
        }
    }

    @ViewBuilder
    private func authorTappable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onAuthorTap {
            Button(action: onAuthorTap) {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View profile")
        } else {
            content()
        }
    }
}
