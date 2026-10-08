import SwiftUI
import PhotosUI

struct CommentsView: View {
    private static let composerBarHeight: CGFloat = 68
    @Bindable var viewModel: CommentsViewModel
    var session: AuthSession?
    var container: DependencyContainer?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var authorProfileUserID: String?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showStickerPicker = false
    @State private var showGIFPicker = false
    @State private var reportCommentID: String?
    @State private var dismissController = KeyboardDismissController()

    private var canSend: Bool {
        viewModel.canSubmitDraft
    }

    private var remainingAttachmentSlots: Int {
        max(0, CommentsUseCase.maxAttachments - viewModel.attachments.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.comments.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.comments.isEmpty {
                    Spacer()
                    ContentUnavailableView("No comments yet", systemImage: "bubble.right")
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.takeComments) { item in
                            CommentRow(
                                comment: item.comment,
                                currentUser: session?.user,
                                isOwner: item.comment.authorID == viewModel.currentUserID,
                                depth: item.depth,
                                onAuthorTap: { openAuthorProfile(item.comment.authorID) },
                                onLike: { Task { await viewModel.toggleCommentLike(comment: item.comment) } },
                                onReply: {
                                    viewModel.beginReply(to: item.comment)
                                    isComposerFocused = true
                                },
                                onDelete: {
                                    Task { await viewModel.delete(comment: item.comment) }
                                },
                                onReport: {
                                    reportCommentID = item.comment.id
                                }
                            )
                            .listRowInsets(EdgeInsets(
                                top: 8,
                                leading: 16 + CGFloat(item.depth) * 28,
                                bottom: 8,
                                trailing: 16
                            ))
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(current: item.comment) }
                            }
                        }
                    }
                    .listStyle(.plain)
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

                composer
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .liquidGlassKeyboardDismiss(controller: dismissController, bottomInset: Self.composerBarHeight)
            .task {
                viewModel.currentUserAvatarURL = session?.user.avatarURL
                await viewModel.loadInitial()
            }
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadSelectedPhotos(items) }
            }
            .sheet(isPresented: $showStickerPicker) {
                if let stickersUseCase = container?.stickersUseCase {
                    CommentStickerPickerSheet(stickersUseCase: stickersUseCase) { sticker in
                        viewModel.setPendingSticker(sticker)
                        let sendNow = viewModel.draft
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                            && viewModel.attachments.isEmpty
                        if sendNow {
                            Task { await viewModel.submit() }
                        }
                    }
                }
            }
            .sheet(isPresented: $showGIFPicker) {
                CommentGIFPickerSheet { gif in
                    viewModel.enqueuePickedGIF(gif)
                }
            }
            .sheet(isPresented: Binding(
                get: { reportCommentID != nil },
                set: { if !$0 { reportCommentID = nil } }
            )) {
                if let reportCommentID, let container {
                    ReportCommentSheet(commentID: reportCommentID, userUseCase: container.userUseCase)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .navigationDestination(item: $authorProfileUserID) { userID in
            if let session, let container {
                UserProfileView(userID: userID, session: session, container: container)
            }
        }
    }

    private func openAuthorProfile(_ userID: String) {
        guard session != nil, container != nil, !userID.isEmpty else { return }
        authorProfileUserID = userID
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isComposerFocused)

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: max(1, remainingAttachmentSlots),
                matching: .images
            ) {
                Image(systemName: "photo")
                    .foregroundStyle(remainingAttachmentSlots > 0 ? ComposerPalette.monochrome.accent : Color.secondary.opacity(0.45))
            }
            .disabled(remainingAttachmentSlots == 0)
            .accessibilityLabel("Attach photos")

            Button {
                showGIFPicker = true
            } label: {
                Text("GIF")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(ComposerPalette.monochrome.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("GIF")

            if container?.stickersUseCase != nil {
                Button {
                    showStickerPicker = true
                } label: {
                    Image(systemName: "face.smiling")
                        .foregroundStyle(ComposerPalette.monochrome.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stickers")
            }

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .tint(ComposerPalette.monochrome.accent)
            .disabled(!canSend)
        }
        .padding()
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
}

private struct CommentRow: View {
    let comment: Comment
    var currentUser: User? = nil
    let isOwner: Bool
    var depth: Int = 0
    var onAuthorTap: (() -> Void)? = nil
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    var onReport: (() -> Void)? = nil

    private var avatarSize: CGFloat { depth > 0 ? 28 : 36 }
    private var showUnderReview: Bool {
        isOwner && comment.moderationStatus == .inReview
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if depth > 0 {
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

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    authorTappable {
                        UserHandleLabel(
                            displayName: comment.resolvedDisplayName,
                            atUsername: comment.atUsername,
                            font: .caption.weight(.semibold),
                            secondaryFont: .caption2
                        )
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let createdAt = comment.createdAt {
                        Text(PostRelativeTimestamp.string(from: createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if showUnderReview {
                    Text("Under review")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if !comment.content.isEmpty {
                    Text(comment.content)
                        .font(.body)
                        .opacity(showUnderReview ? 0.7 : 1)
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
        .padding(.vertical, 4)
        .contextMenu {
            if isOwner {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } else if comment.canReport, let onReport {
                Button(role: .destructive, action: onReport) {
                    Label("Report", systemImage: "flag")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
