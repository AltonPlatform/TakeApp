import SwiftUI
import PhotosUI
import UIKit

/// Pure layout helper for shot comments sheet height above the keyboard.
enum ShotCommentsSheetLayout {
    static let heightRatio: CGFloat = 0.65
    static let minimumHeight: CGFloat = 280
    static let topMargin: CGFloat = 56

    /// Preferred sheet height that never exceeds the space above the keyboard.
    /// - When `availableAboveKeyboard` is still 0 (keyboard guide not ready), falls back to the preferred ratio.
    /// - `minHeight` applies only when there is enough room above the keyboard.
    static func sheetHeight(
        viewHeight: CGFloat,
        availableAboveKeyboard: CGFloat,
        ratio: CGFloat = heightRatio,
        minHeight: CGFloat = minimumHeight
    ) -> CGFloat {
        guard viewHeight > 1 else { return 0 }
        let preferred = max(0, viewHeight * ratio)
        let space = max(0, availableAboveKeyboard)

        // First layout passes often report an empty keyboard guide — keep preferred height.
        if space < 1 {
            return preferred
        }

        if space >= minHeight {
            // Never exceed available space; floor to minHeight when there is room.
            return min(space, max(minHeight, preferred))
        }
        return min(preferred, space)
    }
}

struct ShotCommentsSheet: UIViewControllerRepresentable {
    @Bindable var viewModel: CommentsViewModel
    let commentCount: Int
    let currentUser: User?
    var searchUseCase: SearchUseCase?
    var session: AuthSession?
    var container: DependencyContainer?
    var onDismiss: () -> Void
    var onCommentAdded: ((Int) -> Void)?

    func makeUIViewController(context: Context) -> ShotCommentsSheetViewController {
        let controller = ShotCommentsSheetViewController(
            viewModel: viewModel,
            commentCount: commentCount,
            currentUser: currentUser,
            searchUseCase: searchUseCase,
            session: session,
            container: container,
            onDismiss: onDismiss,
            onCommentAdded: onCommentAdded
        )
        return controller
    }

    func updateUIViewController(_ controller: ShotCommentsSheetViewController, context: Context) {
        controller.updateCommentCount(commentCount)
    }
}

@MainActor
final class ShotCommentsSheetViewController: UIViewController {
    private let viewModel: CommentsViewModel
    private var commentCount: Int
    private let currentUser: User?
    private let searchUseCase: SearchUseCase?
    private let session: AuthSession?
    private let container: DependencyContainer?
    private let onDismiss: () -> Void
    private let onCommentAdded: ((Int) -> Void)?

    private let dimmingView = UIView()
    private let sheetView = UIView()
    private var hostingController: UIHostingController<ShotCommentsSheetContent>?
    private var commentsScrollView: UIScrollView?
    private var sheetHeightConstraint: NSLayoutConstraint?
    private var sheetTopConstraint: NSLayoutConstraint?
    private weak var scrollPanRecognizer: UIPanGestureRecognizer?

    private var translationY: CGFloat = 0
    private var activeDismissDirection: DismissDirection = .none

    private let sheetHeightRatio: CGFloat = ShotCommentsSheetLayout.heightRatio
    private let dismissDistanceThreshold: CGFloat = 120
    private let dismissVelocityThreshold: CGFloat = 0.5
    private let directionLockDistance: CGFloat = 10

    private enum DismissDirection {
        case none
        case down
        case right
    }

    init(
        viewModel: CommentsViewModel,
        commentCount: Int,
        currentUser: User?,
        searchUseCase: SearchUseCase?,
        session: AuthSession?,
        container: DependencyContainer?,
        onDismiss: @escaping () -> Void,
        onCommentAdded: ((Int) -> Void)?
    ) {
        self.viewModel = viewModel
        self.commentCount = commentCount
        self.currentUser = currentUser
        self.searchUseCase = searchUseCase
        self.session = session
        self.container = container
        self.onDismiss = onDismiss
        self.onCommentAdded = onCommentAdded
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimmingView.alpha = 0
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)

        sheetView.backgroundColor = .systemBackground
        sheetView.layer.cornerRadius = 12
        sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetView.layer.masksToBounds = true
        sheetView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheetView)

        let content = ShotCommentsSheetContent(
            viewModel: viewModel,
            commentCount: commentCount,
            currentUser: currentUser,
            searchUseCase: searchUseCase,
            session: session,
            container: container,
            onClose: { [weak self] in self?.animateDismiss() },
            onCommentAdded: onCommentAdded
        )
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hostingController = hosting
        addChild(hosting)
        sheetView.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: sheetView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor),
        ])
        hosting.didMove(toParent: self)

        sheetHeightConstraint = sheetView.heightAnchor.constraint(equalToConstant: 0)
        sheetHeightConstraint?.priority = UILayoutPriority(999)
        sheetTopConstraint = sheetView.topAnchor.constraint(
            greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
            constant: ShotCommentsSheetLayout.topMargin
        )

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            sheetHeightConstraint!,
            sheetTopConstraint!,
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDimmingTap))
        dimmingView.addGestureRecognizer(tap)

        Task {
            viewModel.currentUserAvatarURL = currentUser?.avatarURL
            await viewModel.loadInitial()
            refreshHostingContent()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSheetHeightForAvailableSpace()
    }

    private func updateSheetHeightForAvailableSpace() {
        let viewHeight = view.bounds.height
        guard viewHeight > 1 else { return }
        let keyboardTop = view.keyboardLayoutGuide.layoutFrame.minY
        let topLimit = view.safeAreaInsets.top + ShotCommentsSheetLayout.topMargin
        let available = max(0, keyboardTop - topLimit)
        let height = ShotCommentsSheetLayout.sheetHeight(
            viewHeight: viewHeight,
            availableAboveKeyboard: available,
            ratio: sheetHeightRatio
        )
        guard abs((sheetHeightConstraint?.constant ?? 0) - height) > 0.5 else { return }
        sheetHeightConstraint?.constant = height
    }

    private func refreshHostingContent() {
        guard let hostingController else { return }
        hostingController.rootView = ShotCommentsSheetContent(
            viewModel: viewModel,
            commentCount: commentCount,
            currentUser: currentUser,
            searchUseCase: searchUseCase,
            session: session,
            container: container,
            onClose: { [weak self] in self?.animateDismiss() },
            onCommentAdded: onCommentAdded
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lockFeedScroll(true)
        DispatchQueue.main.async { [weak self] in
            self?.attachCommentsScrollViewIfNeeded()
        }
        presentSheetAnimated()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lockFeedScroll(false)
        if let scrollPanRecognizer {
            scrollPanRecognizer.removeTarget(self, action: #selector(handleScrollPan(_:)))
            self.scrollPanRecognizer = nil
        }
    }

    func updateCommentCount(_ count: Int) {
        commentCount = count
    }

    private func attachCommentsScrollViewIfNeeded() {
        guard commentsScrollView == nil, let hostingView = hostingController?.view else { return }
        commentsScrollView = findScrollView(in: hostingView)
        guard let scrollView = commentsScrollView else { return }

        scrollView.alwaysBounceVertical = true
        let pan = scrollView.panGestureRecognizer
        pan.addTarget(self, action: #selector(handleScrollPan(_:)))
        scrollPanRecognizer = pan
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }

    private func presentSheetAnimated() {
        sheetView.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        dimmingView.alpha = 0
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.4
        ) {
            self.sheetView.transform = .identity
            self.dimmingView.alpha = 1
        }
    }

    @objc private func handleDimmingTap() {
        animateDismiss()
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.view === commentsScrollView else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let scrollOffsetY = commentsScrollView?.contentOffset.y ?? 0

        switch gesture.state {
        case .began:
            activeDismissDirection = .none
        case .changed:
            if activeDismissDirection == .none {
                updateDismissDirectionIfNeeded(translation: translation, velocity: velocity, scrollOffsetY: scrollOffsetY)
                if activeDismissDirection == .none, scrollOffsetY > 0 {
                    return
                }
            }
            applyActiveDismissTransform(translation: translation)
        case .ended, .cancelled:
            if activeDismissDirection == .none {
                translationY = 0
            } else {
                finishInteractiveDismiss(velocity: velocity)
            }
            activeDismissDirection = .none
        default:
            break
        }
    }

    private func updateDismissDirectionIfNeeded(translation: CGPoint, velocity: CGPoint, scrollOffsetY: CGFloat) {
        guard activeDismissDirection == .none else { return }
        guard hypot(translation.x, translation.y) >= directionLockDistance else { return }

        if abs(velocity.x) > abs(velocity.y), velocity.x > 0 {
            activeDismissDirection = .right
            return
        }

        if abs(velocity.y) >= abs(velocity.x),
           velocity.y > 0,
           scrollOffsetY <= 0 {
            activeDismissDirection = .down
        }
    }

    private func applyActiveDismissTransform(translation: CGPoint) {
        switch activeDismissDirection {
        case .right:
            translationY = max(0, translation.x)
            commentsScrollView?.contentOffset = .zero
        case .down:
            translationY = max(0, translation.y)
            commentsScrollView?.contentOffset = .zero
        case .none:
            translationY = 0
            return
        }

        sheetView.transform = CGAffineTransform(translationX: 0, y: translationY)
        let sheetHeight = max(sheetView.bounds.height, 1)
        dimmingView.alpha = 1 - min(translationY / sheetHeight, 1) * 0.85
    }

    private func finishInteractiveDismiss(velocity: CGPoint) {
        let sheetHeight = max(sheetView.bounds.height, 1)

        switch activeDismissDirection {
        case .down:
            let normalizedVelocity = velocity.y / sheetHeight
            if translationY > dismissDistanceThreshold || normalizedVelocity > dismissVelocityThreshold {
                animateDismiss()
            } else {
                resetSheetPosition()
            }
        case .right:
            let normalizedVelocity = velocity.x / max(view.bounds.width, 1)
            if translationY > dismissDistanceThreshold || normalizedVelocity > dismissVelocityThreshold {
                animateDismiss()
            } else {
                resetSheetPosition()
            }
        case .none:
            if translationY > 0 {
                resetSheetPosition()
            }
        }
    }

    private func resetSheetPosition() {
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.5
        ) {
            self.sheetView.transform = .identity
            self.dimmingView.alpha = 1
        } completion: { _ in
            self.translationY = 0
        }
    }

    private func animateDismiss() {
        let sheetHeight = sheetView.bounds.height
        let targetTransform = CGAffineTransform(translationX: 0, y: sheetHeight + 40)

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseIn]
        ) {
            self.sheetView.transform = targetTransform
            self.dimmingView.alpha = 0
        } completion: { _ in
            self.lockFeedScroll(false)
            self.onDismiss()
        }
    }

    private func lockFeedScroll(_ locked: Bool) {
        ShotFeedPagingViewController.activeInstance?.setFeedScrollingEnabled(!locked)
    }
}

private struct ShotCommentsSheetContent: View {
    @Bindable var viewModel: CommentsViewModel
    let commentCount: Int
    let currentUser: User?
    var searchUseCase: SearchUseCase?
    var session: AuthSession?
    var container: DependencyContainer?
    var onClose: () -> Void
    var onCommentAdded: ((Int) -> Void)?

    @FocusState private var isComposerFocused: Bool
    @State private var mentionPicker: MentionPickerModel
    @State private var authorProfileUserID: String?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showStickerPicker = false
    @State private var showGIFPicker = false
    @State private var reportCommentID: String?

    init(
        viewModel: CommentsViewModel,
        commentCount: Int,
        currentUser: User?,
        searchUseCase: SearchUseCase?,
        session: AuthSession?,
        container: DependencyContainer?,
        onClose: @escaping () -> Void,
        onCommentAdded: ((Int) -> Void)?
    ) {
        self.viewModel = viewModel
        self.commentCount = commentCount
        self.currentUser = currentUser
        self.searchUseCase = searchUseCase
        self.session = session
        self.container = container
        self.onClose = onClose
        self.onCommentAdded = onCommentAdded
        _mentionPicker = State(initialValue: MentionPickerModel(searchUseCase: searchUseCase))
    }

    private var canSend: Bool {
        viewModel.canSubmitDraft
    }

    private var remainingAttachmentSlots: Int {
        max(0, CommentsUseCase.maxAttachments - viewModel.attachments.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dragHandle
                header
                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if viewModel.isLoading && viewModel.comments.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else if let errorMessage = viewModel.errorMessage, viewModel.comments.isEmpty {
                            ContentUnavailableView(
                                "Couldn't load comments",
                                systemImage: "exclamationmark.bubble",
                                description: Text(errorMessage)
                            )
                            .padding(.vertical, 24)
                        } else if viewModel.comments.isEmpty {
                            Text("No comments yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.takeComments) { item in
                                VideoCommentRow(
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
                                    onDelete: { Task { await viewModel.delete(comment: item.comment) } },
                                    onReport: { reportCommentID = item.comment.id }
                                )
                                .padding(.leading, 16 + CGFloat(item.depth) * 28)
                                .padding(.trailing, 16)
                                .padding(.vertical, 12)
                                .onAppear {
                                    Task { await viewModel.loadMoreIfNeeded(current: item.comment) }
                                }
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
            .navigationBarHidden(true)
            .keyboardDoneButton(focus: $isComposerFocused)
            .onChange(of: viewModel.draft) { _, newValue in
                mentionPicker.update(from: newValue)
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
                            submitComment()
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

    private var dragHandle: some View {
        Capsule()
            .fill(Color(.systemGray3))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Comments · \(formattedCount(commentCount))")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Image(systemName: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(0.4)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            if let currentUser {
                UserAvatarView(user: currentUser, size: 32)
            } else {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 8) {
                TextField("Add comment...", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit { submitComment() }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(1, remainingAttachmentSlots),
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(remainingAttachmentSlots > 0 ? Color.secondary : Color.secondary.opacity(0.35))
                }
                .disabled(remainingAttachmentSlots == 0)
                .buttonStyle(.plain)
                .accessibilityLabel("Attach photos")

                Button {
                    showGIFPicker = true
                } label: {
                    Text("GIF")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("GIF")

                if container?.stickersUseCase != nil {
                    Button {
                        showStickerPicker = true
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stickers")
                }

                Button {
                    var draft = viewModel.draft
                    mentionPicker.showAfterInsertingAt(into: &draft)
                    viewModel.draft = draft
                    isComposerFocused = true
                } label: {
                    Image(systemName: "at")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mention user")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: Capsule())

            Button {
                submitComment()
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send comment")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
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

    private func submitComment() {
        Task {
            await viewModel.submit()
            if viewModel.errorMessage == nil {
                onCommentAdded?(viewModel.comments.count)
            }
        }
    }

    private func formattedCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

private struct VideoCommentRow: View {
    let comment: Comment
    var currentUser: User? = nil
    let isOwner: Bool
    var depth: Int = 0
    var onAuthorTap: (() -> Void)? = nil
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    var onReport: (() -> Void)? = nil

    private var avatarSize: CGFloat { depth > 0 ? 32 : 40 }
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
                }

                if showUnderReview {
                    Text("Under review")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if !comment.content.isEmpty {
                    Text(comment.content)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
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

            Spacer(minLength: 0)

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
            } else if comment.canReport, let onReport {
                Button(role: .destructive, action: onReport) {
                    Label("Report", systemImage: "flag")
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

