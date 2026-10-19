import PhotosUI
import SwiftUI
import UIKit

struct ChatView: View {
    @State var viewModel: ChatViewModel
    let shareDeps: DirectShareDependencies?
    var container: DependencyContainer?
    var session: AuthSession?
    /// When false, history and the socket wait (open fade still in flight).
    var liveEnabled: Bool = true
    /// Set when the chat is the inbox overlay. The header then lives in this tree so it fades with the screen.
    var onClose: (() -> Void)? = nil

    @State private var fullscreenMedia: ChatFullscreenMedia?
    @State private var locationPreview: ChatLocationPreview?
    @Namespace private var messageZoom
    @State private var showPhotoPicker = false
    @State private var showExpressionSheet = false
    @State private var photoLibrary = ChatPhotoLibraryModel()
    @State private var openedPost: ChatOpenedPost?
    @State private var openPostError: String?
    @State private var isOpeningPost = false
    @State private var profileUserID: String?
    @State private var actionTarget: ChatActionTarget?
    @State private var contentFrameBox = FrameBox()
    @State private var fieldFrameBox = FrameBox()
    @State private var frameRegistry = ChatFrameRegistry()
    @State private var reactionFlight: ReactionFlight?
    @State private var flightBurst: ReactionFlight?
    @State private var bigReactionEffect: ReactionBigEffect?
    @State private var incomingReaction: (messageID: String, emoji: String)?
    @State private var revealReaction: (messageID: String, emoji: String)?
    @State private var sendMorph: ChatSendMorph?
    @State private var copiedToastVisible = false
    @State private var copiedToastToken = 0
    @State private var composerFocusToken = 0
    @State private var reactionFinger: CGPoint?
    @State private var reactionFingerRelease = 0
    /// Bottom spacer until the reader leaves the latest message.
    @State private var pinnedID: String? = ChatView.bottomAnchorID
    @State private var listRevealed = false
    /// How many of the latest rows are built. Grows when the reader scrolls up.
    @State private var messageWindow = 18
    @State private var highlightedRowID: String?
    @State private var highlightClearTask: Task<Void, Never>?
    @State private var engagementController: PostEngagementController?
    @State private var sharePostTarget: Post?
    @State private var showPostShareSheet = false
    @State private var showGroupMembers = false

    private static let bottomAnchorID = "chat-bottom-anchor"

    init(
        viewModel: ChatViewModel,
        shareDeps: DirectShareDependencies? = nil,
        container: DependencyContainer? = nil,
        session: AuthSession? = nil,
        liveEnabled: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.shareDeps = shareDeps
        self.container = container
        self.session = session
        self.liveEnabled = liveEnabled
        self.onClose = onClose
        if let container {
            _engagementController = State(initialValue: container.makeEngagementController())
        }
    }

    var body: some View {
        ZStack {
            chatBackground
            ScrollViewReader { proxy in
                messageScroll(proxy: proxy)
            }

            if let actionTarget {
                ChatMessageActionOverlay(
                    target: actionTarget,
                    safeArea: contentFrameBox.frame.width > 1 ? contentFrameBox.frame : overlaySafeArea,
                    fingerPoint: reactionFinger,
                    fingerRelease: reactionFingerRelease,
                    onReact: { emoji, source, isLarge in
                        launchReactionFlight(
                            message: actionTarget.message,
                            emoji: emoji,
                            source: source,
                            isMine: actionTarget.isMine,
                            isLarge: isLarge
                        )
                    },
                    onAction: { action in
                        handleMessageAction(action, for: actionTarget.message)
                    },
                    onDismiss: {
                        self.actionTarget = nil
                        self.reactionFinger = nil
                    }
                )
                .zIndex(10)
            }

            if let bigReactionEffect {
                ReactionBigEffectView(effect: bigReactionEffect) {
                    let effect = bigReactionEffect
                    self.bigReactionEffect = nil
                    beginFlightAfterBigEffect(effect)
                }
                .zIndex(19)
            }

            if let reactionFlight {
                ReactionFlightLayer(flight: reactionFlight) {
                    completeReactionFlight(reactionFlight)
                }
                .zIndex(20)
            }

            if let flightBurst {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global)
                    ReactionBurstView(
                        emoji: flightBurst.emoji,
                        particleCount: flightBurst.isLarge ? 10 : 6,
                        radius: flightBurst.isLarge ? 60 : 28
                    ) {
                        self.flightBurst = nil
                    }
                    .position(
                        x: flightBurst.target.midX - origin.minX,
                        y: flightBurst.target.midY - origin.minY
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(21)
            }

            if copiedToastVisible {
                VStack {
                    Text("Copied")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .directGlass(Capsule(), interactive: false)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(30)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: copiedToastVisible)
        .sensoryFeedback(.success, trigger: copiedToastToken)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(onClose == nil ? .automatic : .hidden, for: .navigationBar)
        // The inbox overlay covers the tab bar itself. Hiding it again from here
        // changes the inbox safe area and the list jumps.
        .toolbar(onClose == nil ? .hidden : .automatic, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if onClose != nil {
                chatOverlayHeader
            }
        }
        .background(ChatPopGestureLock(isLocked: actionTarget != nil))
        .preference(
            key: ChatBackSwipeLockedKey.self,
            value: actionTarget != nil || profileUserID != nil || openedPost != nil
        )
        .toolbar {
            if onClose == nil {
                ToolbarItem(placement: .principal) {
                    chatTitleButton
                }
            }
        }
        .navigationDestination(item: $profileUserID) { userID in
            if let session, let container {
                UserProfileView(userID: userID, session: session, container: container)
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $viewModel.photoSelection,
            maxSelectionCount: ChatComposerLimits.maxPasteImages,
            matching: .images
        )
        .onChange(of: viewModel.photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await viewModel.stagePickedPhotos()
                composerFocusToken += 1
            }
        }
        .sheet(isPresented: $viewModel.showAttachSheet) {
            ChatAttachSheet(
                library: photoLibrary,
                onSend: { ids, captured, caption in
                    Task { await viewModel.sendAttachedSelection(ids: ids, captured: captured, caption: caption) }
                },
                onSendLocation: { location in
                    Task { await viewModel.sendLocation(location) }
                },
                onSendChecklist: { checklist in
                    Task { await viewModel.sendChecklist(checklist) }
                },
                onSendPoll: { poll in
                    Task { await viewModel.sendPoll(poll) }
                },
                onBrowseAll: { showPhotoPicker = true }
            )
        }
        .sheet(isPresented: $showExpressionSheet) {
            ChatExpressionSheet(
                stickersUseCase: container?.stickersUseCase,
                onPickSticker: { sticker in
                    Task { await viewModel.sendSticker(sticker) }
                },
                onPickGIF: { gif in
                    Task { await viewModel.sendGIF(gif) }
                },
                onInsertEmoji: { emoji in
                    viewModel.insertEmoji(emoji)
                }
            )
        }
        .fullScreenCover(item: $viewModel.pendingDMCrop, onDismiss: {
            viewModel.cropCoverDismissed()
        }) { draft in
            PhotoCropEditorView(
                image: draft.image,
                mask: .rectangle,
                initialAspect: DMImageRules.preferredCropAspect(for: draft.image)
            ) {
                viewModel.cancelDMCrop()
            } onComplete: { cropped in
                Task { await viewModel.finishDMCrop(cropped) }
            }
        }
        .sheet(item: $viewModel.forwardMessage) { message in
            if let deps = shareDeps {
                ForwardPickerSheet(messageID: message.id, deps: deps) { ids in
                    Task { await viewModel.forward(message, to: ids) }
                }
            } else {
                Text("Forward unavailable")
                    .padding()
            }
        }
        .fullScreenCover(item: $locationPreview) { item in
            ChatLocationMapScreen(location: item.location)
                .navigationTransition(.zoom(sourceID: item.id, in: messageZoom))
        }
        .fullScreenCover(item: $fullscreenMedia) { item in
            ImageLightboxView(
                urls: [item.url],
                animatedFlags: [item.isAnimated],
                initialIndex: 0
            )
        }
        .navigationDestination(item: $openedPost) { opened in
            if let container, let session {
                switch opened.kind {
                case .take(let item):
                    TakePostDetailView(
                        item: item,
                        currentUser: session.user,
                        container: container,
                        session: session,
                        userUseCase: container.userUseCase,
                        engagementController: container.makeEngagementController(),
                        commentsViewModelFactory: { post in
                            container.makeCommentsViewModel(
                                postID: post.id,
                                currentUserID: session.user.id
                            )
                        },
                        analyticsUseCase: container.analyticsUseCase,
                        postUseCase: container.postUseCase,
                        onDeleted: { openedPost = nil }
                    )
                case .shot(let posts, let index, let isOwnProfile):
                    ProfileShotsFeedView(
                        posts: posts,
                        initialIndex: index,
                        session: session,
                        container: container,
                        isOwnProfile: isOwnProfile
                    )
                }
            }
        }
        .alert("Message", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Can't open post", isPresented: Binding(
            get: { openPostError != nil },
            set: { if !$0 { openPostError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openPostError ?? "")
        }
        .postShareSheet(
            isPresented: $showPostShareSheet,
            payload: sharePostTarget.flatMap { post in
                engagementController?.makeSharePayload(for: post)
            },
            directShare: container.flatMap { c in
                c.sessionStore.session.map {
                    c.makeDirectShareDependencies(currentUserID: $0.user.id)
                }
            }
        ) { completed, channel in
            showPostShareSheet = false
            guard completed, let channel, let post = sharePostTarget, let engagementController else {
                sharePostTarget = nil
                return
            }
            Task {
                let updated = await engagementController.completeShare(post: post, channel: channel)
                viewModel.updateSharedPost(updated)
                sharePostTarget = nil
            }
        }
        .task {
            viewModel.prepareCached()
            if !viewModel.messages.isEmpty, !listRevealed {
                withAnimation(.easeOut(duration: 0.15)) {
                    listRevealed = true
                }
            }
        }
        .task(id: liveEnabled) {
            guard liveEnabled else { return }
            viewModel.startLive()
        }
        .onDisappear { viewModel.stop() }
    }

    private func messageScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            ChatMessageStack(viewModel: viewModel, window: messageWindow) { row in
                chatRow(row, scrollProxy: proxy)
            }
            .padding(.top, 8)
            Color.clear
                .frame(height: 28)
                .id(Self.bottomAnchorID)
        }
        .opacity(listRevealed ? 1 : 0)
        .scrollPosition(id: $pinnedID, anchor: .bottom)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(sizeChangeAnchor, for: .sizeChanges)
        .onScrollGeometryChange(for: ChatOlderScrollGate.self, of: olderScrollGate, action: applyOlderScroll)
        .environment(\.chatZoomNamespace, messageZoom)
        .environment(\.chatTracksBubbleFrames, tracksBubbleFrames)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: viewModel.rows.count) { old, count in
            growWindow(old, count)
        }
        .onChange(of: viewModel.messages.count) { old, count in
            revealLoadedMessages(old, count)
        }
        .onChange(of: pinnedID) { _, id in
            trackPinnedPosition(id)
        }
        .overlay(alignment: .bottomTrailing) { jumpToBottomButton }
        .directBottomBar { composerBar }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: storeContentFrame)
    }

    private var sizeChangeAnchor: UnitPoint {
        isPinnedToBottom ? .bottom : .top
    }

    private var tracksBubbleFrames: Bool {
        actionTarget != nil || sendMorph != nil || reactionFlight != nil
    }

    private func olderScrollGate(_ geo: ScrollGeometry) -> ChatOlderScrollGate {
        ChatOlderScrollGate(
            window: messageWindow,
            contentShort: geo.contentSize.height < geo.containerSize.height + 40,
            nearTop: geo.visibleRect.minY < 48
        )
    }

    private func applyOlderScroll(_ previous: ChatOlderScrollGate, _ gate: ChatOlderScrollGate) {
        let hidden = viewModel.rows.count - messageWindow
        if hidden > 0, gate.contentShort || gate.nearTop {
            messageWindow = min(viewModel.rows.count, messageWindow + 24)
            return
        }
        guard gate.nearTop, !gate.contentShort else { return }
        Task { await viewModel.loadOlder() }
    }

    private func growWindow(_ old: Int, _ count: Int) {
        guard count > old, !isPinnedToBottom else { return }
        messageWindow = min(count, messageWindow + (count - old))
    }

    private func revealLoadedMessages(_ old: Int, _ count: Int) {
        guard count > 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if !listRevealed { listRevealed = true }
            if old == 0 { pinnedID = Self.bottomAnchorID }
        }
    }

    private func trackPinnedPosition(_ id: String?) {
        let near = id == nil || id == Self.bottomAnchorID || id == latestMessageID
        guard viewModel.isNearBottom != near else { return }
        Task { @MainActor in
            guard viewModel.isNearBottom != near else { return }
            viewModel.isNearBottom = near
            if near { viewModel.unreadWhileScrolled = 0 }
        }
    }

    private func storeContentFrame(_ frame: CGRect) {
        let previous = contentFrameBox.frame
        guard frame != previous else { return }
        guard abs(frame.minX - previous.minX) > 0.5
            || abs(frame.minY - previous.minY) > 0.5
            || abs(frame.width - previous.width) > 0.5
            || abs(frame.height - previous.height) > 0.5
        else { return }
        contentFrameBox.frame = frame
    }

    @ViewBuilder
    private var jumpToBottomButton: some View {
        if !isPinnedToBottom {
            Button {
                withAnimation(.easeOut(duration: 0.28)) {
                    pinnedID = Self.bottomAnchorID
                }
                viewModel.unreadWhileScrolled = 0
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .directGlass(Circle(), interactive: true)
                    if viewModel.unreadWhileScrolled > 0 {
                        Text("\(viewModel.unreadWhileScrolled)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(12)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var composerBar: some View {
        ChatComposerHost(
            viewModel: viewModel,
            focusToken: composerFocusToken,
            fieldFrameBox: fieldFrameBox,
            onSend: { Task { await performSend() } },
            onAttach: {
                photoLibrary.prepare()
                viewModel.showAttachSheet = true
            },
            onExpressions: {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
                showExpressionSheet = true
            }
        )
        .equatable()
    }

    private func openSharedPost(id: String) async {
        guard !isOpeningPost, let container, let session else { return }
        isOpeningPost = true
        defer { isOpeningPost = false }
        do {
            let post: Post
            if let cached = viewModel.sharedPosts[id] {
                post = cached
            } else {
                post = try await container.postUseCase.fetchPost(id: id)
                viewModel.updateSharedPost(post)
            }
            if let blocked = ViewerContentFilterPolicy.blockedOpenMessage(
                for: post,
                viewerIsAdult: session.user.isAdult,
                showSensitiveContent: session.user.showSensitiveContent
            ) {
                openPostError = blocked
                return
            }
            if post.postType == .shot {
                let feed = await sharedShotFeed(opened: post)
                openedPost = ChatOpenedPost(
                    kind: .shot(
                        posts: feed.posts,
                        index: feed.index,
                        isOwnProfile: false
                    )
                )
            } else {
                openedPost = ChatOpenedPost(
                    kind: .take(
                        FeedItem(
                            post: post,
                            finalScore: 0,
                            userScore: 0,
                            creatorScore: 0,
                            brandScore: 0
                        )
                    )
                )
            }
        } catch {
            openPostError = "This post couldn't be opened. It may have been deleted."
        }
    }

    /// Shots already sent in this chat, in message order. Profile shots stay on the profile.
    private func sharedShotFeed(opened: Post) async -> (posts: [Post], index: Int) {
        let ids = conversationShotIDs(including: opened.id)
        guard let container else { return ([opened], 0) }
        var fetched: [String: Post] = [opened.id: opened]
        await withTaskGroup(of: (String, Post?).self) { group in
            for id in ids where id != opened.id {
                group.addTask {
                    let post = try? await container.postUseCase.fetchPost(id: id)
                    return (id, post)
                }
            }
            for await (id, post) in group {
                if let post, post.postType == .shot {
                    fetched[id] = post
                }
            }
        }
        let posts = ids.compactMap { fetched[$0] }
        let list = posts.isEmpty ? [opened] : posts
        let index = list.firstIndex(where: { $0.id == opened.id }) ?? 0
        return (list, index)
    }

    private func conversationShotIDs(including openedID: String) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        for message in viewModel.messages where message.deletedAt == nil && message.kind == .postShare {
            guard let postID = message.postID else { continue }
            let type = message.postType ?? viewModel.postCards[postID]?.postType
            guard postID == openedID || type == "shot" else { continue }
            if seen.insert(postID).inserted {
                ids.append(postID)
            }
        }
        if seen.insert(openedID).inserted {
            ids.append(openedID)
        }
        return ids
    }

    private var chatBackground: some View {
        ChatScreenBackground()
            .ignoresSafeArea()
    }

    private var chatOverlayHeader: some View {
        HStack(spacing: 8) {
            Button {
                onClose?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .directGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer(minLength: 0)
            chatTitleButton
            Spacer(minLength: 0)
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var chatTitleButton: some View {
        Button {
            if viewModel.conversation.isGroup {
                showGroupMembers = true
                return
            }
            let peer = viewModel.conversation.peerUserID
            guard !peer.isEmpty else { return }
            profileUserID = peer
        } label: {
            ChatTitleView(
                viewModel: viewModel,
                avatar: { chatPeerAvatar(size: 28) }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.conversation.isGroup ? "Group members" : "Open profile")
        .sheet(isPresented: $showGroupMembers) {
            GroupMembersSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
    }

    private var overlaySafeArea: CGRect {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let insets = scene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets
            ?? scene?.windows.first?.safeAreaInsets
            ?? .zero
        let bounds = scene?.screen.bounds ?? UIScreen.main.bounds
        return CGRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.top,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom
        )
    }

    private var latestMessageID: String? {
        guard let message = viewModel.messages.last(where: { $0.deletedAt == nil }) else { return nil }
        return message.clientMsgID.isEmpty ? message.id : message.clientMsgID
    }

    /// The list is born on the bottom anchor, so this stays true until the reader moves up.
    private var isPinnedToBottom: Bool {
        guard let pinnedID else { return true }
        return pinnedID == Self.bottomAnchorID || pinnedID == latestMessageID
    }

    private func presentActionOverlay(
        for message: DMMessage,
        bubbleFrame: CGRect,
        startScale: CGFloat,
        showTail: Bool,
        groupedWithPrevious: Bool
    ) {
        guard bubbleFrame.width > 1, bubbleFrame.height > 1 else { return }
        actionTarget = ChatActionTarget(
            message: message,
            bubbleFrame: bubbleFrame,
            isMine: viewModel.isMine(message),
            isReadByPeer: viewModel.isReadByPeer(message),
            replyPreview: viewModel.message(forSeq: message.replyToSeq),
            postCard: message.postID.flatMap { viewModel.postCards[$0] },
            sharedPost: message.postID.flatMap { viewModel.sharedPosts[$0] },
            infoLine: viewModel.actionInfoLine(for: message),
            myEmoji: message.myReaction(currentUserID: viewModel.currentUserID),
            currentUserID: viewModel.currentUserID,
            startScale: startScale,
            showTail: showTail,
            groupedWithPrevious: groupedWithPrevious
        )
    }

    private func sharedPostActions(for message: DMMessage) -> ChatSharedPostActions {
        ChatSharedPostActions(
            onAppear: { postID in
                viewModel.loadSharedPost(postID: postID)
            },
            onOpen: {
                guard let postID = message.postID else { return }
                Task { await openSharedPost(id: postID) }
            },
            onLike: { post in
                guard let engagementController else { return }
                Task {
                    let updated = await engagementController.toggleLike(for: post)
                    viewModel.updateSharedPost(updated)
                }
            },
            onRepost: { post in
                guard let engagementController else { return }
                Task {
                    let updated = await engagementController.toggleRepost(for: post)
                    viewModel.updateSharedPost(updated)
                }
            },
            onBookmark: { post in
                guard let engagementController else { return }
                Task {
                    let updated = await engagementController.toggleBookmark(for: post)
                    viewModel.updateSharedPost(updated)
                }
            },
            onComment: { post in
                Task { await openSharedPost(id: post.id) }
            },
            onShare: { post in
                guard let engagementController else { return }
                Task {
                    if await engagementController.prepareShare(postID: post.id) {
                        sharePostTarget = post
                        showPostShareSheet = true
                    }
                }
            },
            onForward: {
                viewModel.forwardMessage = message
            }
        )
    }

    private func checklistMemberAvatar(_ userID: String) -> URL? {
        if let member = viewModel.conversation.members.first(where: { $0.userID == userID }) {
            return member.avatarURL
        }
        if userID == viewModel.conversation.peerUserID {
            return viewModel.conversation.peerAvatarURL
        }
        return nil
    }

    private func checklistMemberName(_ userID: String) -> String {
        if userID == viewModel.currentUserID || userID == "me" { return "you" }
        if let member = viewModel.conversation.members.first(where: { $0.userID == userID }) {
            return "@\(member.username)"
        }
        if userID == viewModel.conversation.peerUserID, !viewModel.conversation.peerUsername.isEmpty {
            return "@\(viewModel.conversation.peerUsername)"
        }
        return ""
    }

    private func beginReply(to message: DMMessage) {
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.replyTo = message
        }
        composerFocusToken += 1
    }

    private func jumpToReply(_ reply: DMMessage, proxy: ScrollViewProxy) {
        guard let targetID = ChatReplyJump.targetRowID(reply: reply, rows: viewModel.rows) else {
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        // Clear any previous flash so the target can pulse again after it arrives.
        highlightedRowID = nil
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(targetID, anchor: .center)
        }
        highlightClearTask?.cancel()
        highlightClearTask = Task { @MainActor in
            // Wait until the scroll settles, then flash — same beat as Telegram.
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            highlightedRowID = targetID
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            if highlightedRowID == targetID {
                highlightedRowID = nil
            }
        }
    }

    private func launchReactionFlight(
        message: DMMessage,
        emoji: String,
        source: CGRect,
        isMine: Bool,
        isLarge: Bool
    ) {
        let messageID = message.id
        // Same emoji toggles off — no flight animation.
        if message.myReaction(currentUserID: viewModel.currentUserID) == emoji {
            Task { await viewModel.react(to: message, emoji: emoji) }
            return
        }
        incomingReaction = (messageID, emoji)
        Task { await viewModel.react(to: message, emoji: emoji) }

        let safeSource = source.width > 1
            ? source
            : CGRect(x: source.midX - 16, y: source.midY - 16, width: 32, height: 32)

        if isLarge {
            let bubble = actionTarget?.bubbleFrame
                ?? frameRegistry.bubbleFrame(messageID: messageID)
                ?? safeSource
            bigReactionEffect = ReactionBigEffect(
                emoji: emoji,
                messageID: messageID,
                isMine: isMine,
                source: safeSource,
                bubbleCenter: CGPoint(x: bubble.midX, y: bubble.midY)
            )
            return
        }

        DispatchQueue.main.async {
            startReactionFlight(
                emoji: emoji,
                messageID: messageID,
                isMine: isMine,
                source: safeSource,
                isLarge: false
            )
        }
    }

    private func beginFlightAfterBigEffect(_ effect: ReactionBigEffect) {
        let enlarged = CGRect(
            x: effect.bubbleCenter.x - 36,
            y: effect.bubbleCenter.y - 36,
            width: 72,
            height: 72
        )
        startReactionFlight(
            emoji: effect.emoji,
            messageID: effect.messageID,
            isMine: effect.isMine,
            source: enlarged,
            isLarge: true
        )
    }

    private func startReactionFlight(
        emoji: String,
        messageID: String,
        isMine: Bool,
        source: CGRect,
        isLarge: Bool
    ) {
        let target: CGRect
        if let badge = frameRegistry.badgeFrame(messageID: messageID, emoji: emoji) {
            target = badge
        } else if let center = frameRegistry.predictedBadgeCenter(messageID: messageID, isMine: isMine) {
            target = CGRect(x: center.x - 14, y: center.y - 12, width: 28, height: 24)
        } else {
            let bubble = frameRegistry.bubbleFrame(messageID: messageID) ?? source
            let x = isMine ? bubble.maxX - 28 : bubble.minX
            target = CGRect(x: x, y: bubble.maxY + 6, width: 28, height: 24)
        }
        reactionFlight = ReactionFlight(
            emoji: emoji,
            messageID: messageID,
            source: source,
            target: target,
            isLarge: isLarge
        )
    }

    private func completeReactionFlight(_ flight: ReactionFlight) {
        ChatReactionHaptics.reactionSelected()
        flightBurst = flight
        reactionFlight = nil
        incomingReaction = nil
        revealReaction = (flight.messageID, flight.emoji)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if revealReaction?.messageID == flight.messageID,
               revealReaction?.emoji == flight.emoji
            {
                revealReaction = nil
            }
        }
    }

    private func handleMessageAction(_ action: ChatMessageAction, for message: DMMessage) {
        switch action {
        case .reply:
            beginReply(to: message)
        case .copy:
            ChatPasteboard.copyText(message.body)
            showCopiedToast()
        case .copyMedia:
            Task {
                let ok = await ChatPasteboard.copyMedia(from: message)
                if ok { showCopiedToast() }
            }
        case .edit:
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.beginEdit(message)
            }
            composerFocusToken += 1
        case .forward:
            viewModel.forwardMessage = message
        case .delete:
            Task { await viewModel.delete(message) }
        case .retry:
            Task { await viewModel.retry(message) }
        case .retractVote:
            Task { await viewModel.retractPollVote(messageID: message.id) }
        case .stopPoll:
            Task { await viewModel.closePoll(messageID: message.id) }
        }
    }

    private func showCopiedToast() {
        copiedToastToken += 1
        withAnimation {
            copiedToastVisible = true
        }
        let token = copiedToastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard token == copiedToastToken else { return }
            withAnimation {
                copiedToastVisible = false
            }
        }
    }

    @ViewBuilder
    private func chatRow(_ row: ChatRow, scrollProxy: ScrollViewProxy) -> some View {
        let message = row.message
        if message.deletedAt == nil {
            if row.showDate {
                ChatDateSeparator(isoDate: message.createdAt)
            }
            ChatFreshRow(
                isFresh: viewModel.freshRowKeys.contains(row.id) || viewModel.growingRowKeys.contains(row.id),
                skipsReveal: sendMorph?.id == row.id
            ) {
                messageBubble(row, message: message, scrollProxy: scrollProxy)
                    .equatable()
                    .id(row.id)
                    .padding(.horizontal, 10)
                    .padding(.top, row.grouped ? 2 : 8)
            }
        }
    }

    private func messageBubble(
        _ row: ChatRow,
        message: DMMessage,
        scrollProxy: ScrollViewProxy
    ) -> ChatMessageBubble {
        ChatMessageBubble(
            message: message,
            isMine: viewModel.isMine(message),
            showTail: row.showTail,
            groupedWithPrevious: row.grouped,
            isReadByPeer: viewModel.isReadByPeer(message),
            replyPreview: row.replyPreview,
            postCard: message.postID.flatMap { viewModel.postCards[$0] },
            sharedPost: message.postID.flatMap { viewModel.sharedPosts[$0] },
            sharedPostActions: sharedPostActions(for: message),
            currentUserID: viewModel.currentUserID,
            onRetry: { Task { await viewModel.retry(message) } },
            onReply: { beginReply(to: message) },
            onOpenMedia: {
                guard let url = message.mediaURL ?? message.mediaThumbURL else { return }
                fullscreenMedia = ChatFullscreenMedia(
                    url: url,
                    isAnimated: message.kind == .gif
                )
            },
            onOpenPost: {
                guard let postID = message.postID else { return }
                Task { await openSharedPost(id: postID) }
            },
            onToggleChecklistItem: { itemID in
                Task { await viewModel.toggleChecklistItem(messageID: message.id, itemID: itemID) }
            },
            onAppendChecklistItem: { text in
                Task { await viewModel.appendChecklistItem(messageID: message.id, text: text) }
            },
            onVotePoll: { optionIDs in
                Task { await viewModel.votePoll(messageID: message.id, optionIDs: optionIDs) }
            },
            onAppendPollOption: { text in
                Task { await viewModel.appendPollOption(messageID: message.id, text: text) }
            },
            memberName: { userID in
                checklistMemberName(userID)
            },
            memberAvatarURL: { userID in
                checklistMemberAvatar(userID)
            },
            onOpenLocation: {
                guard let location = message.location else { return }
                locationPreview = ChatLocationPreview(rowID: row.id, location: location)
            },
            isFresh: viewModel.freshRowKeys.contains(row.id),
            onReact: { emoji in
                Task { await viewModel.react(to: message, emoji: emoji) }
            },
            onDoubleTapReact: {
                Task { await viewModel.doubleTapReact(message) }
            },
            onLongPress: { frame, scale in
                reactionFinger = nil
                presentActionOverlay(
                    for: message,
                    bubbleFrame: frame,
                    startScale: scale,
                    showTail: row.showTail,
                    groupedWithPrevious: row.grouped
                )
            },
            onPressMove: { reactionFinger = $0 },
            onPressRelease: { reactionFingerRelease += 1 },
            isGroup: viewModel.conversation.isGroup,
            senderName: row.senderName,
            senderAvatarURL: row.senderAvatarURL,
            seenLabel: viewModel.seenLabel(for: message),
            onOpenSenderProfile: {
                guard !message.senderID.isEmpty else { return }
                profileUserID = message.senderID
            },
            isLifted: actionTarget?.message.id == message.id,
            sendMorphSource: sendMorph?.id == row.id ? sendMorph?.source : nil,
            onSendMorphSettled: {
                if sendMorph?.id == row.id {
                    sendMorph = nil
                }
            },
            incomingReactionEmoji: incomingReaction?.messageID == message.id
                ? incomingReaction?.emoji
                : nil,
            revealReactionEmoji: revealReaction?.messageID == message.id
                ? revealReaction?.emoji
                : nil,
            frameRegistry: frameRegistry,
            onTapReply: {
                guard let reply = row.replyPreview else { return }
                jumpToReply(reply, proxy: scrollProxy)
            },
            isHighlighted: highlightedRowID == row.id
        )
    }

    @MainActor
    private func performSend() async {
        if !viewModel.pendingPasteImages.isEmpty || viewModel.editingMessage != nil || !viewModel.hasDraftText {
            _ = await viewModel.send()
            return
        }
        let clientID = UUID().uuidString
        let source = fieldFrameBox.frame
        if !AccessibilitySettings.reduceMotion, source.width > 1, source.height > 1 {
            sendMorph = ChatSendMorph(id: clientID, source: source)
        } else if !AccessibilitySettings.reduceMotion, viewModel.isNearBottom {
            viewModel.markRowGrowing(clientID)
        }
        var pin = Transaction()
        pin.disablesAnimations = true
        withTransaction(pin) {
            pinnedID = Self.bottomAnchorID
        }
        _ = await viewModel.send(clientID: clientID)
    }

    @ViewBuilder
    private func chatPeerAvatar(size: CGFloat) -> some View {
        if viewModel.conversation.isGroup {
            UserAvatarView(
                user: User(
                    id: viewModel.conversation.id,
                    username: "",
                    displayName: viewModel.conversation.displayTitle,
                    bio: nil,
                    avatarURL: viewModel.conversation.groupAvatarURL,
                    suiWallet: nil,
                    createdAt: nil
                ),
                size: size
            )
        } else {
            UserAvatarView(
                user: User(
                    id: viewModel.conversation.peerUserID,
                    username: viewModel.conversation.peerUsername,
                    displayName: viewModel.conversation.peerDisplayName,
                    bio: nil,
                    avatarURL: viewModel.conversation.peerAvatarURL,
                    suiWallet: nil,
                    createdAt: nil
                ),
                size: size,
                showOnlineIndicator: true,
                presenceStore: container?.presenceStore
            )
        }
    }
}

/// One route so the inbox `NavigationPath` pushes both a take and a shot.
private struct ChatOpenedPost: Identifiable, Hashable {
    enum Kind: Hashable {
        case take(FeedItem)
        case shot(posts: [Post], index: Int, isOwnProfile: Bool)

        func hash(into hasher: inout Hasher) {
            switch self {
            case .take(let item):
                hasher.combine("take")
                hasher.combine(item.id)
            case .shot(let posts, let index, let isOwnProfile):
                hasher.combine("shot")
                hasher.combine(posts.map(\.id))
                hasher.combine(index)
                hasher.combine(isOwnProfile)
            }
        }

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case (.take(let lhsItem), .take(let rhsItem)):
                return lhsItem.id == rhsItem.id
            case (.shot(let lhsPosts, let lhsIndex, let lhsOwn), .shot(let rhsPosts, let rhsIndex, let rhsOwn)):
                return lhsPosts.map(\.id) == rhsPosts.map(\.id)
                    && lhsIndex == rhsIndex
                    && lhsOwn == rhsOwn
            default:
                return false
            }
        }
    }

    let kind: Kind
    var id: String {
        switch kind {
        case .take(let item):
            return "take-\(item.id)"
        case .shot(let posts, let index, _):
            let postID = posts.indices.contains(index) ? posts[index].id : posts.first?.id ?? "shot"
            return "shot-\(postID)"
        }
    }
}

private struct ChatFullscreenMedia: Identifiable, Equatable {
    let url: URL
    let isAnimated: Bool
    var id: String { "\(isAnimated ? "anim" : "still")-\(url.absoluteString)" }
}

/// Isolates composer observation so keystrokes / draft flips don't rebuild the message list.
private struct ChatComposerHost: View, Equatable {
    var viewModel: ChatViewModel
    var focusToken: Int
    var fieldFrameBox: FrameBox
    var onSend: () -> Void
    var onAttach: () -> Void
    var onExpressions: () -> Void

    static func == (lhs: ChatComposerHost, rhs: ChatComposerHost) -> Bool {
        lhs.focusToken == rhs.focusToken
            && lhs.viewModel === rhs.viewModel
            && lhs.fieldFrameBox === rhs.fieldFrameBox
            && lhs.viewModel.editingMessage?.id == rhs.viewModel.editingMessage?.id
            && lhs.viewModel.hasDraftText == rhs.viewModel.hasDraftText
            && lhs.viewModel.pendingPasteImages.isEmpty == rhs.viewModel.pendingPasteImages.isEmpty
            && lhs.viewModel.draftRevision == rhs.viewModel.draftRevision
    }

    var body: some View {
        ChatComposerBar(
            draftText: viewModel.draft,
            draftRevision: viewModel.draftRevision,
            hasText: viewModel.hasDraftText,
            replyTo: viewModel.replyTo,
            editingMessage: viewModel.editingMessage,
            pendingPasteImages: viewModel.pendingPasteImages,
            focusToken: focusToken,
            fieldFrameBox: fieldFrameBox,
            onCancelReply: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.replyTo = nil
                }
            },
            onCancelEdit: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.cancelEdit()
                }
            },
            onAttach: onAttach,
            onExpressions: onExpressions,
            onSend: onSend,
            onTextChange: { viewModel.updateDraftFromInput($0) },
            onDraftChange: { viewModel.notifyTyping() },
            onPasteImages: { viewModel.queuePastedImages($0) },
            onConfirmPasteImages: { images in
                Task { await viewModel.sendPastedImages(images) }
            },
            onCancelPasteImages: { viewModel.cancelPastedImages() }
        )
    }
}

/// Title / typing subtitle with its own observation scope — keeps the list off peerTyping.
private struct ChatTitleView<Avatar: View>: View {
    var viewModel: ChatViewModel
    @ViewBuilder var avatar: () -> Avatar

    var body: some View {
        HStack(spacing: 8) {
            avatar()
            VStack(spacing: 2) {
                Text(viewModel.conversation.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if viewModel.peerTyping {
                    Text("typing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if viewModel.conversation.isGroup {
                    Text("\(max(viewModel.conversation.memberCount, viewModel.conversation.members.count)) members")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if !viewModel.conversation.peerUsername.isEmpty {
                    Text("@\(viewModel.conversation.peerUsername)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .directGlass(Capsule(), interactive: true)
    }
}

/// Blocks the system back-swipe while the message action overlay is up.
private struct ChatPopGestureLock: UIViewControllerRepresentable {
    var isLocked: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isLocked = isLocked
        controller.apply()
    }

    final class Controller: UIViewController {
        var isLocked = false

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func apply() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = !isLocked
        }
    }
}

struct ChatFreshRow<Content: View>: View {
    var isFresh: Bool
    var skipsReveal: Bool
    @ViewBuilder var content: () -> Content
    @State private var progress: CGFloat
    /// Frozen at creation so the clip branch does not rebuild the bubble when the morph ends.
    @State private var clipsOverflow: Bool

    init(isFresh: Bool, skipsReveal: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.isFresh = isFresh
        self.skipsReveal = skipsReveal
        self.content = content
        _progress = State(initialValue: isFresh && !skipsReveal ? 0 : 1)
        _clipsOverflow = State(initialValue: !skipsReveal)
    }

    var body: some View {
        let reveal = ChatRowReveal(progress: progress) {
            content()
        }
        Group {
            if clipsOverflow {
                reveal.clipped()
            } else {
                reveal
            }
        }
        .onAppear {
            guard isFresh, !skipsReveal, progress < 1 else { return }
            withAnimation(.smooth(duration: 0.28)) {
                progress = 1
            }
        }
    }
}

/// The open paints only the latest screen of bubbles. Older ones join as you scroll up,
/// so a long chat does not build every row before the first frame.
private struct ChatMessageStack<RowContent: View>: View {
    var viewModel: ChatViewModel
    var window: Int
    @ViewBuilder var row: (ChatRow) -> RowContent

    var body: some View {
        let rows = viewModel.rows
        let start = max(0, rows.count - window)
        VStack(spacing: 0) {
            if viewModel.isLoadingOlder {
                ProgressView()
                    .padding(.vertical, 8)
            }
            ForEach(Array(rows[start...])) { item in
                row(item)
            }
        }
    }
}

/// Near the top of a list that is taller than the screen. Used to page older messages.
private struct ChatOlderScrollGate: Equatable {
    var window: Int
    var contentShort: Bool
    var nearTop: Bool
}

struct ChatSendMorph: Equatable {
    var id: String
    var source: CGRect
}

struct ChatLocationPreview: Identifiable {
    let rowID: String
    let location: DMLocation
    var id: String { rowID }
}
