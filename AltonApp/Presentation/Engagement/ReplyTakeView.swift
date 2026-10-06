import SwiftUI
import PhotosUI

/// Owns `CommentsViewModel` in `@State` so navigation re-renders don't wipe loaded comments.
struct ReplyTakeHost: View {
    let post: Post
    let currentUser: User?
    @Bindable var engagementController: PostEngagementController
    let commentsViewModelFactory: (Post) -> CommentsViewModel
    var userUseCase: UserUseCase?
    var searchUseCase: SearchUseCase?
    var session: AuthSession?
    var container: DependencyContainer?
    /// When set, focuses the composer as a reply to this comment after load.
    var initialReplyTo: Comment?

    @State private var viewModel: CommentsViewModel
    @State private var didApplyInitialReply = false

    init(
        post: Post,
        currentUser: User?,
        engagementController: PostEngagementController,
        commentsViewModelFactory: @escaping (Post) -> CommentsViewModel,
        userUseCase: UserUseCase? = nil,
        searchUseCase: SearchUseCase? = nil,
        session: AuthSession? = nil,
        container: DependencyContainer? = nil,
        initialReplyTo: Comment? = nil
    ) {
        self.post = post
        self.currentUser = currentUser
        self.engagementController = engagementController
        self.commentsViewModelFactory = commentsViewModelFactory
        self.userUseCase = userUseCase
        self.searchUseCase = searchUseCase
        self.session = session
        self.container = container
        self.initialReplyTo = initialReplyTo
        _viewModel = State(initialValue: commentsViewModelFactory(post))
    }

    var body: some View {
        ReplyTakeView(
            viewModel: viewModel,
            post: post,
            currentUser: currentUser,
            engagementController: engagementController,
            userUseCase: userUseCase,
            searchUseCase: searchUseCase,
            session: session,
            container: container
        )
        .task {
            guard !didApplyInitialReply, let initialReplyTo else { return }
            didApplyInitialReply = true
            viewModel.beginReply(to: initialReplyTo)
        }
    }
}

struct ReplyTakeView: View {
    @Bindable var viewModel: CommentsViewModel
    let post: Post
    let currentUser: User?
    @Bindable var engagementController: PostEngagementController
    var userUseCase: UserUseCase?
    var searchUseCase: SearchUseCase?
    var session: AuthSession?
    var container: DependencyContainer?

    @State private var localPost: Post
    @State private var showShareSheet = false
    @State private var showFullComposer = false
    @State private var mentionPicker: MentionPickerModel
    @State private var mentionProfileUserID: String?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showGIFPicker = false
    @FocusState private var isComposerFocused: Bool
    private static let composerBarHeight: CGFloat = 64
    @State private var dismissController = KeyboardDismissController()

    init(
        viewModel: CommentsViewModel,
        post: Post,
        currentUser: User?,
        engagementController: PostEngagementController,
        userUseCase: UserUseCase? = nil,
        searchUseCase: SearchUseCase? = nil,
        session: AuthSession? = nil,
        container: DependencyContainer? = nil
    ) {
        self.viewModel = viewModel
        self.post = post
        self.currentUser = currentUser
        self.engagementController = engagementController
        self.userUseCase = userUseCase
        self.searchUseCase = searchUseCase
        self.session = session
        self.container = container
        _localPost = State(initialValue: post)
        _mentionPicker = State(initialValue: MentionPickerModel(searchUseCase: searchUseCase))
    }

    private var canSend: Bool {
        viewModel.canSubmitDraft
    }

    private var remainingAttachmentSlots: Int {
        max(0, CommentsUseCase.maxAttachments - viewModel.attachments.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    postPreview
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Divider()
                        .padding(.top, 12)

                    if viewModel.isLoading && viewModel.comments.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if viewModel.comments.isEmpty {
                        Text("No replies yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else {
                        ForEach(viewModel.takeComments) { item in
                            ReplyCommentRow(
                                comment: item.comment,
                                currentUser: currentUser,
                                isOwner: item.comment.authorID == viewModel.currentUserID,
                                depth: item.depth,
                                onAuthorTap: { openAuthorProfile(item.comment.authorID) },
                                onLike: { Task { await viewModel.toggleCommentLike(comment: item.comment) } },
                                onReply: {
                                    viewModel.beginReply(to: item.comment)
                                    isComposerFocused = true
                                },
                                onDelete: { Task { await viewModel.delete(comment: item.comment) } }
                            )
                            .padding(.leading, 16 + CGFloat(item.depth) * 28)
                            .padding(.trailing, 16)
                            .padding(.vertical, 10)
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(current: item.comment) }
                            }

                            Divider()
                                .padding(.leading, 68 + CGFloat(item.depth) * 28)
                        }
                    }
                }
            }

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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        viewModel.clearReplyTarget()
                    }
                    .font(.caption.weight(.semibold))
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

            inlineComposer
        }
        .onChange(of: viewModel.draft) { _, newValue in
            mentionPicker.update(from: newValue)
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadSelectedPhotos(items) }
        }
        .navigationTitle("Reply")
        .navigationBarTitleDisplayMode(.inline)
        .liquidGlassKeyboardDismiss(controller: dismissController, bottomInset: Self.composerBarHeight)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Reply")
                        .font(.headline)
                    if localPost.viewCount > 0 {
                        Text("\(formatCount(localPost.viewCount)) views")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let activityVM = PostActivityViewModel(
                        postID: localPost.id,
                        post: localPost,
                        currentUser: currentUser,
                        activityUseCase: viewModel.activityUseCase,
                        userUseCase: userUseCase
                    )
                    AltonSheetPresenter.present {
                        PostSheetChrome(title: "Post activity", onClose: { AltonSheetPresenter.dismiss() }) {
                            NavigationStack {
                                PostActivityView(viewModel: activityVM, embeddedInSheet: true)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "bell")
                }
            }
        }
        .task {
            viewModel.currentUserAvatarURL = currentUser?.avatarURL
            await viewModel.loadInitial()
        }
        .navigationDestination(item: $mentionProfileUserID) { userID in
            if let session, let container {
                UserProfileView(userID: userID, session: session, container: container)
            }
        }
        .fullScreenCover(isPresented: $showFullComposer) {
            CommentComposerFullScreenView(
                draft: $viewModel.draft,
                attachments: $viewModel.attachments,
                pendingSticker: $viewModel.pendingSticker,
                pendingGIF: $viewModel.pendingGIF,
                isSubmitting: viewModel.isSubmitting,
                searchUseCase: searchUseCase,
                onCancel: { showFullComposer = false },
                onSubmit: {
                    Task {
                        await viewModel.submit()
                        if viewModel.errorMessage == nil {
                            showFullComposer = false
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showGIFPicker) {
            CommentGIFPickerSheet { gif in
                viewModel.enqueuePickedGIF(gif)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let payload = engagementController.makeSharePayload(for: localPost) {
                ActivityShareSheet(payload: payload) { completed, channel in
                    showShareSheet = false
                    if completed, let channel {
                        Task {
                            localPost = await engagementController.completeShare(
                                post: localPost,
                                channel: channel
                            )
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var postPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                UserAvatarView(
                    user: User(
                        id: localPost.creatorID,
                        username: localPost.creatorUsername ?? "",
                        displayName: localPost.resolvedCreatorDisplayName(currentUser: currentUser),
                        bio: nil,
                        avatarURL: localPost.resolvedCreatorAvatarURL(currentUser: currentUser),
                        suiWallet: nil,
                        createdAt: nil
                    ),
                    size: 40
                )

                VStack(alignment: .leading, spacing: 8) {
                    UserHandleLabel.forPost(localPost, currentUser: currentUser)

                    AgeRestrictedMediaGate(isAgeGated: localPost.ageGated, contentID: localPost.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let content = localPost.content, !content.isEmpty {
                                TakeMarkdownContent(
                                    content: content,
                                    onMentionTap: openMentionProfile
                                )
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            if !localPost.imageURLs.isEmpty {
                                PostMediaStripView(
                                    urls: localPost.imageURLs,
                                    post: localPost,
                                    currentUser: currentUser,
                                    engagementController: engagementController,
                                    commentsViewModelFactory: { _ in viewModel },
                                    session: session,
                                    container: container,
                                    onPostChange: { localPost = $0 }
                                )
                            } else if let thumbnailURL = localPost.thumbnailURL {
                                PostMediaStripView(
                                    urls: [thumbnailURL],
                                    post: localPost,
                                    currentUser: currentUser,
                                    engagementController: engagementController,
                                    commentsViewModelFactory: { _ in viewModel },
                                    session: session,
                                    container: container,
                                    onPostChange: { localPost = $0 }
                                )
                            }
                        }
                    }
                    .id(localPost.id)

                    PostActionBar(
                        post: localPost,
                        layout: .horizontal,
                        showsRepost: true,
                        onLike: { Task { localPost = await engagementController.toggleLike(for: localPost) } },
                        onComment: { isComposerFocused = true },
                        onRepost: { Task { localPost = await engagementController.toggleRepost(for: localPost) } },
                        onShare: {
                            Task {
                                if await engagementController.prepareShare(postID: localPost.id) {
                                    showShareSheet = true
                                }
                            }
                        }
                    )
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var inlineComposer: some View {
        HStack(spacing: 10) {
            if let currentUser {
                UserAvatarView(user: currentUser, size: 32)
            } else {
                Circle()
                    .fill(.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 8) {
                TextField("Add a reply...", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit { submitReply() }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(1, remainingAttachmentSlots),
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .foregroundStyle(remainingAttachmentSlots > 0 ? Color.secondary : Color.secondary.opacity(0.35))
                }
                .disabled(remainingAttachmentSlots == 0)
                .buttonStyle(.borderless)
                .accessibilityLabel("Attach photos")

                Button {
                    showGIFPicker = true
                } label: {
                    Text("GIF")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("GIF")

                Button {
                    var draft = viewModel.draft
                    mentionPicker.showAfterInsertingAt(into: &draft)
                    viewModel.draft = draft
                    isComposerFocused = true
                } label: {
                    Image(systemName: "at")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Mention user")

                Button { showFullComposer = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Expand composer")
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: Capsule())

            Button(action: submitReply) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? ComposerPalette.monochrome.accent : Color.secondary.opacity(0.45))
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send reply")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        guard remainingAttachmentSlots > 0 else { return }
        guard await DevicePermissions.requestPhotoLibraryAccess() else {
            viewModel.errorMessage = "Photo library access is required to attach media."
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
        viewModel.appendAttachments(loaded)
    }

    private func submitReply() {
        Task { await viewModel.submit() }
    }

    private func openMentionProfile(_ username: String) {
        guard let searchUseCase else { return }
        Task {
            if let userID = await MentionNavigation.resolveUserID(username: username, searchUseCase: searchUseCase) {
                mentionProfileUserID = userID
            } else {
                container?.appState.showToast("User @\(username) not found")
            }
        }
    }

    private func openAuthorProfile(_ userID: String) {
        guard session != nil, container != nil, !userID.isEmpty else { return }
        mentionProfileUserID = userID
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

/// Shared comment row used by reply take and post detail.
struct ReplyCommentRow: View {
    let comment: Comment
    let currentUser: User?
    let isOwner: Bool
    var depth: Int = 0
    var onAuthorTap: (() -> Void)? = nil
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void

    private var avatarSize: CGFloat { depth > 0 ? 28 : 36 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if depth > 0 {
                // Branch rail under the parent comment.
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(.separator))
                    .frame(width: 2)
                    .padding(.vertical, 2)
            }

            authorTappable {
                UserAvatarView(
                    user: comment.authorAsUser(currentUser: currentUser),
                    size: avatarSize
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    authorTappable {
                        UserHandleLabel.forComment(
                            displayName: comment.authorDisplayName,
                            username: comment.authorUsername,
                            fallbackID: comment.authorID
                        )
                    }
                    if let createdAt = comment.createdAt {
                        Text(PostRelativeTimestamp.string(from: createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if !comment.content.isEmpty {
                    Text(comment.content)
                        .font(.body)
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

                Button("Reply", action: onReply)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }

            Button(action: onLike) {
                VStack(spacing: 2) {
                    Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundStyle(comment.isLiked ? Color.red : Color.primary)
                    Text("\(comment.likeCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(comment.isLiked ? "Unlike comment" : "Like comment")
        }
        .contextMenu {
            if isOwner {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
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
