import SwiftUI
import Nuke
import NukeUI
import UIKit

private struct ChatBubbleInteractionLockedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ChatZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct ChatFrameTrackingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var chatBubbleInteractionLocked: Bool {
        get { self[ChatBubbleInteractionLockedKey.self] }
        set { self[ChatBubbleInteractionLockedKey.self] = newValue }
    }

    var chatZoomNamespace: Namespace.ID? {
        get { self[ChatZoomNamespaceKey.self] }
        set { self[ChatZoomNamespaceKey.self] = newValue }
    }

    /// Bubble frames are published only while an overlay, flight, or send morph needs them.
    var chatTracksBubbleFrames: Bool {
        get { self[ChatFrameTrackingKey.self] }
        set { self[ChatFrameTrackingKey.self] = newValue }
    }
}

struct ChatDateSeparator: View {
    let isoDate: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(.systemGray5).opacity(0.9)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private var label: String {
        ChatDateCache.dayLabel(isoDate)
    }

    static func parse(_ iso: String) -> Date? {
        ChatDateCache.date(iso)
    }
}

/// Pure grouping helpers shared by `ChatViewModel` and unit tests.
enum ChatBubbleGrouping {
    static let windowSeconds: TimeInterval = 5 * 60

    static func sameGroup(_ a: DMMessage, _ b: DMMessage) -> Bool {
        guard a.senderID == b.senderID else { return false }
        guard let ta = ChatDateCache.date(a.createdAt),
              let tb = ChatDateCache.date(b.createdAt)
        else { return true }
        return abs(ta.timeIntervalSince(tb)) < windowSeconds
    }

    static func isGroupedWithPrevious(messages: [DMMessage], at index: Int) -> Bool {
        guard messages.indices.contains(index), index > 0 else { return false }
        return sameGroup(messages[index - 1], messages[index])
    }

    static func shouldShowTail(messages: [DMMessage], at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return false }
        let current = messages[index]
        let nextIndex = index + 1
        guard messages.indices.contains(nextIndex) else { return true }
        let next = messages[nextIndex]
        if current.senderID != next.senderID { return true }
        return !sameGroup(current, next)
    }
}

struct ChatMessageBubble: View, Equatable {
    @Environment(\.chatTracksBubbleFrames) private var chatTracksBubbleFrames
    let message: DMMessage
    let isMine: Bool
    let showTail: Bool
    let groupedWithPrevious: Bool
    let isReadByPeer: Bool
    let replyPreview: DMMessage?
    let postCard: DMPostCard?
    var sharedPost: Post? = nil
    var sharedPostActions: ChatSharedPostActions = .noop
    let currentUserID: String
    let onRetry: () -> Void
    let onReply: () -> Void
    let onOpenMedia: () -> Void
    let onOpenPost: () -> Void
    var onToggleChecklistItem: (Int) -> Void = { _ in }
    var onAppendChecklistItem: (String) -> Void = { _ in }
    var onVotePoll: ([Int]) -> Void = { _ in }
    var onAppendPollOption: (String) -> Void = { _ in }
    var memberName: (String) -> String = { _ in "" }
    var memberAvatarURL: (String) -> URL? = { _ in nil }
    var onOpenLocation: () -> Void = {}
    var isFresh: Bool = false
    let onReact: (String) -> Void
    let onDoubleTapReact: () -> Void
    let onLongPress: (CGRect, CGFloat) -> Void
    var onPressMove: ((CGPoint) -> Void)? = nil
    var onPressRelease: (() -> Void)? = nil
    var isGroup: Bool = false
    var senderName: String? = nil
    var senderAvatarURL: URL? = nil
    var seenLabel: String? = nil
    var onOpenSenderProfile: (() -> Void)? = nil
    /// When the action overlay is presenting this message, hide the original bubble.
    var isLifted: Bool = false
    /// Composer frame for a text send. The bubble springs from here into the row.
    var sendMorphSource: CGRect? = nil
    var onSendMorphSettled: () -> Void = {}
    /// Emoji currently flying in from the reaction panel — hide its badge until landing.
    var incomingReactionEmoji: String? = nil
    /// Reveal this badge with a spring pop after a flight lands.
    var revealReactionEmoji: String? = nil
    var frameRegistry: ChatFrameRegistry? = nil
    /// Jump to the quoted reply target.
    var onTapReply: () -> Void = {}
    /// Brief pulse after scrolling to this bubble via reply jump.
    var isHighlighted: Bool = false

    private var isVisuallyHidden: Bool { isLifted }

    static func == (lhs: ChatMessageBubble, rhs: ChatMessageBubble) -> Bool {
        lhs.message == rhs.message
            && lhs.isMine == rhs.isMine
            && lhs.showTail == rhs.showTail
            && lhs.groupedWithPrevious == rhs.groupedWithPrevious
            && lhs.isReadByPeer == rhs.isReadByPeer
            && lhs.replyPreview?.id == rhs.replyPreview?.id
            && lhs.replyPreview?.body == rhs.replyPreview?.body
            && lhs.postCard == rhs.postCard
            && lhs.sharedPost == rhs.sharedPost
            && lhs.currentUserID == rhs.currentUserID
            && lhs.isGroup == rhs.isGroup
            && lhs.senderName == rhs.senderName
            && lhs.senderAvatarURL == rhs.senderAvatarURL
            && lhs.seenLabel == rhs.seenLabel
            && lhs.isLifted == rhs.isLifted
            && lhs.sendMorphSource == rhs.sendMorphSource
            && lhs.incomingReactionEmoji == rhs.incomingReactionEmoji
            && lhs.revealReactionEmoji == rhs.revealReactionEmoji
            && lhs.isFresh == rhs.isFresh
            && lhs.isHighlighted == rhs.isHighlighted
    }

    private var sharedDisplay: ChatSharedPostDisplay {
        ChatSharedPostDisplay.merge(
            postID: message.postID ?? "",
            postTypeHint: message.postType,
            post: sharedPost,
            card: postCard
        )
    }

    private var showsShotForward: Bool {
        message.kind == .postShare
            && message.deletedAt == nil
            && sharedDisplay.isShot
            && !sharedDisplay.unavailable
            && !isVisuallyHidden
    }

    @State private var frameBox = FrameBox()
    @State private var pressProgress: CGFloat = 0
    @State private var contextActivated = false
    @State private var showDoubleTapHeart = false
    @State private var badgePopEmoji: String?
    @State private var badgePopToken = 0
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeArmed = false
    @State private var swipeIconScale: CGFloat = 0.1
    @State private var localBurstEmoji: String?
    @State private var freshArrived = false
    @State private var morphOffset: CGSize = .zero
    @State private var morphPrepared = false

    var body: some View {
        ZStack(alignment: .trailing) {
            swipeReplyIcon
                .padding(.trailing, 4)

            HStack(alignment: .center, spacing: 8) {
                if isMine { Spacer(minLength: 48) }
                if showsShotForward, isMine {
                    ChatShotForwardButton {
                        sharedPostActions.onForward()
                    }
                }
                if isGroup, !isMine {
                    groupSenderAvatar
                        .padding(.trailing, 6)
                }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    if isGroup, !isMine, !groupedWithPrevious, let senderName, !senderName.isEmpty {
                        Button {
                            onOpenSenderProfile?()
                        } label: {
                            Text(senderName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    ZStack {
                        ChatBubbleContent(
                            message: message,
                            isMine: isMine,
                            showTail: showTail,
                            groupedWithPrevious: groupedWithPrevious,
                            isReadByPeer: isReadByPeer,
                            replyPreview: replyPreview,
                            postCard: postCard,
                            sharedPost: sharedPost,
                            sharedPostActions: sharedPostActions,
                            currentUserID: currentUserID,
                            isGroup: isGroup,
                            memberName: memberName,
                            memberAvatarURL: memberAvatarURL,
                            onToggleChecklistItem: onToggleChecklistItem,
                            onAppendChecklistItem: onAppendChecklistItem,
                            onVotePoll: onVotePoll,
                            onAppendPollOption: onAppendPollOption,
                            onTapReply: onTapReply,
                            isHighlighted: isHighlighted
                        )
                        .environment(
                            \.chatBubbleInteractionLocked,
                            contextActivated || pressProgress > 0 || isVisuallyHidden
                        )
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            // Unscaled layout frame. Skip while the press shrinks the bubble,
                            // and skip sub-pixel scroll noise so this does not republish state.
                            guard pressProgress == 0, frame.width > 1, frame.height > 1 else { return }
                            let previous = frameBox.frame
                            guard frame != previous else { return }
                            guard abs(previous.minX - frame.minX) > 0.5
                                || abs(previous.minY - frame.minY) > 0.5
                                || abs(previous.width - frame.width) > 0.5
                                || abs(previous.height - frame.height) > 0.5
                            else { return }
                            frameBox.frame = frame
                            if chatTracksBubbleFrames {
                                frameRegistry?.setBubbleFrame(messageID: message.id, frame: frame)
                            }
                            beginSendMorphIfNeeded(bubble: frame)
                        }
                        .opacity(bubbleOpacity)
                        .allowsHitTesting(!isVisuallyHidden)
                        .offset(morphOffset)
                        .scaleEffect(pressScale)
                        .contentShape(Rectangle())
                        .gesture(
                            TapGesture(count: 2).onEnded {
                                guard !isVisuallyHidden, !contextActivated, swipeOffset == 0 else { return }
                                guard message.deletedAt == nil, !message.isPending else { return }
                                showDoubleTapHeart = true
                                localBurstEmoji = "❤️"
                                onDoubleTapReact()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                    showDoubleTapHeart = false
                                }
                            },
                            including: message.kind == .checklist
                                || message.kind == .poll
                                || message.kind == .postShare
                                ? .subviews
                                : .all
                        )
                        .onTapGesture {
                            guard !isVisuallyHidden, !contextActivated, swipeOffset == 0 else { return }
                            switch message.kind {
                            case .image, .gif:
                                onOpenMedia()
                            case .location:
                                onOpenLocation()
                            case .postShare where message.deletedAt == nil:
                                onOpenPost()
                            default:
                                if message.isFailed { onRetry() }
                            }
                        }
                        .gesture(
                            ChatContextPressGesture(
                                isEnabled: message.deletedAt == nil
                                    && !message.isPending
                                    && !isVisuallyHidden
                                    && swipeOffset == 0,
                                onProgress: { progress in
                                    pressProgress = progress
                                },
                                onActivate: { _ in
                                    contextActivated = true
                                    let frame = frameBox.frame.width > 1 ? frameBox.frame : .zero
                                    guard frame.width > 1, frame.height > 1 else {
                                        withAnimation(.easeOut(duration: ChatContextMotion.pressCancelDuration)) {
                                            pressProgress = 0
                                        }
                                        return
                                    }
                                    let minScale = ChatContextMotion.pressMinScale(width: frame.width)
                                    let scale = 1 - (1 - minScale) * pressProgress
                                    ChatReactionHaptics.longPressArmed()
                                    UIApplication.shared.sendAction(
                                        #selector(UIResponder.resignFirstResponder),
                                        to: nil,
                                        from: nil,
                                        for: nil
                                    )
                                    onLongPress(frame, scale)
                                    pressProgress = 0
                                },
                                onCancel: {
                                    withAnimation(.easeOut(duration: ChatContextMotion.pressCancelDuration)) {
                                        pressProgress = 0
                                    }
                                },
                                onMove: { point in
                                    onPressMove?(point)
                                },
                                onRelease: {
                                    onPressRelease?()
                                }
                            )
                        )

                        if showDoubleTapHeart {
                            DoubleTapHeartOverlay()
                        }
                        if let localBurstEmoji {
                            ReactionBurstView(emoji: localBurstEmoji) {
                                self.localBurstEmoji = nil
                            }
                        }
                    }

                    if let seenLabel {
                        Text(seenLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(isVisuallyHidden ? 0 : 1)
                    }

                    if message.deletedAt == nil {
                        reactionBadgeStrip
                            .opacity(isVisuallyHidden ? 0 : 1)
                    }
                }
                if showsShotForward, !isMine {
                    ChatShotForwardButton {
                        sharedPostActions.onForward()
                    }
                }
                if !isMine { Spacer(minLength: 48) }
            }
            .offset(x: swipeOffset)
            .scaleEffect(freshScale, anchor: isMine ? .bottomTrailing : .bottomLeading)
            .offset(y: freshOffset)
            .opacity(freshOpacity)
            .modifier(ChatLocationZoomSource(id: zoomID, enabled: message.kind == .location))
            .onAppear { playFreshEntranceIfNeeded() }
            .gesture(
                ChatSwipeToReplyGesture(
                    isEnabled: message.deletedAt == nil && !isVisuallyHidden,
                    onChanged: { offset in
                        swipeOffset = offset
                        let progress = ChatSwipeToReply.progress(offset: offset)
                        if progress > 0.05, swipeIconScale < 0.5 {
                            withAnimation(.easeOut(duration: ChatContextMotion.swipeReplyIconDuration)) {
                                swipeIconScale = 1
                            }
                        }
                        let armed = ChatSwipeToReply.shouldTrigger(offset: offset)
                        if armed != swipeArmed {
                            swipeArmed = armed
                            if armed {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(ChatContextMotion.bounce(damping: 72, duration: 0.22)) {
                                    swipeIconScale = 1.2
                                }
                                withAnimation(
                                    ChatContextMotion.bounce(damping: 88, duration: 0.22).delay(0.1)
                                ) {
                                    swipeIconScale = 1
                                }
                            }
                        }
                    },
                    onEnded: { offset in
                        if ChatSwipeToReply.shouldTrigger(offset: offset) {
                            onReply()
                        }
                        withAnimation(
                            ChatContextMotion.bounce(
                                damping: 80,
                                duration: ChatContextMotion.swipeReplySpringDuration
                            )
                        ) {
                            swipeOffset = 0
                        }
                        withAnimation(.easeOut(duration: 0.25)) {
                            swipeIconScale = 0.1
                            swipeArmed = false
                        }
                    },
                    onCancelPress: {
                        withAnimation(.easeOut(duration: ChatContextMotion.pressCancelDuration)) {
                            pressProgress = 0
                        }
                    }
                )
            )
        }
        .onChange(of: isLifted) { _, lifted in
            if lifted {
                contextActivated = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    contextActivated = false
                }
            }
        }
        .onChange(of: revealReactionEmoji) { _, emoji in
            guard let emoji else { return }
            popBadge(emoji)
        }
        .onChange(of: message.myReaction(currentUserID: currentUserID)) { old, emoji in
            // Badge tap / double-tap path (no flight): pop when mine appears.
            guard let emoji, incomingReactionEmoji == nil, revealReactionEmoji == nil else { return }
            if old != emoji {
                popBadge(emoji)
                localBurstEmoji = emoji
            }
        }
    }

    private var playsEntrance: Bool {
        ChatSendMotion.playsEntrance(
            isFresh: isFresh,
            hasMorphSource: sendMorphSource != nil,
            morphPrepared: morphPrepared
        )
    }

    private var freshScale: CGFloat {
        guard playsEntrance, !freshArrived else { return 1 }
        return ChatSendMotion.entranceScale
    }

    private var freshOffset: CGFloat {
        guard playsEntrance, !freshArrived else { return 0 }
        return ChatSendMotion.entranceOffset
    }

    private var freshOpacity: Double {
        guard playsEntrance, !freshArrived else { return 1 }
        return 0
    }

    private var bubbleOpacity: Double {
        if sendMorphSource != nil, !morphPrepared { return 0 }
        return isVisuallyHidden ? 0 : 1
    }

    private var zoomID: String {
        message.clientMsgID.isEmpty ? message.id : message.clientMsgID
    }

    private func beginSendMorphIfNeeded(bubble: CGRect) {
        guard let source = sendMorphSource, !morphPrepared else { return }
        morphPrepared = true
        let offset = ChatSendMorphMath.startOffset(source: source, bubble: bubble)
        if abs(offset.height) > 400 || AccessibilitySettings.reduceMotion {
            onSendMorphSettled()
            return
        }
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) {
            morphOffset = offset
        }
        DispatchQueue.main.async {
            withAnimation(ChatSendMotion.morphSpring, completionCriteria: .logicallyComplete) {
                morphOffset = .zero
            } completion: {
                onSendMorphSettled()
            }
        }
    }

    private func playFreshEntranceIfNeeded() {
        guard playsEntrance, !freshArrived else { return }
        withAnimation(ChatSendMotion.entrance) {
            freshArrived = true
        }
    }

    private var pressScale: CGFloat {
        guard pressProgress > 0 else { return 1 }
        let minScale = ChatContextMotion.pressMinScale(width: max(frameBox.frame.width, 1))
        return 1 - (1 - minScale) * pressProgress
    }

    @ViewBuilder
    private var swipeReplyIcon: some View {
        let progress = ChatSwipeToReply.progress(offset: swipeOffset)
        let armed = swipeArmed
        ZStack {
            Circle()
                .fill(armed ? Color.accentColor : Color.accentColor.opacity(0.18))
                .frame(width: ChatSwipeToReply.iconSize, height: ChatSwipeToReply.iconSize)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: ChatSwipeToReply.iconSize, height: ChatSwipeToReply.iconSize)
                .rotationEffect(.degrees(-90))
                .opacity(armed ? 0 : 1)
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(armed ? Color.white : Color.accentColor)
                .rotationEffect(ChatSwipeToReply.arrowRotation(offset: swipeOffset))
        }
        .scaleEffect(swipeIconScale)
        .opacity(ChatSwipeToReply.iconOpacity(offset: swipeOffset))
        // Ride with the bubble: sits just off the trailing edge and tracks swipeOffset.
        .offset(x: ChatSwipeToReply.iconSize + 12 + swipeOffset)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var groupSenderAvatar: some View {
        Group {
            if groupedWithPrevious {
                Color.clear.frame(width: 28, height: 28)
            } else {
                Button {
                    onOpenSenderProfile?()
                } label: {
                    UserAvatarView(
                        user: User(
                            id: message.senderID,
                            username: senderName ?? "",
                            displayName: senderName ?? "",
                            bio: nil,
                            avatarURL: senderAvatarURL,
                            suiWallet: nil,
                            createdAt: nil
                        ),
                        size: 28
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isVisuallyHidden ? 0 : 1)
    }

    private var reactionBadgeStrip: some View {
        let badges = message.reactionBadges
        let signature = badges.map { badge in
            let mine = message.myReaction(currentUserID: currentUserID) == badge.emoji
            return "\(badge.emoji):\(badge.count):\(mine ? 1 : 0)"
        }.joined(separator: "|")
        return Group {
            if badges.isEmpty {
                EmptyView()
            } else {
                reactionBadgeRow(badges, signature: signature)
            }
        }
    }

    private func reactionBadgeRow(
        _ badges: [(emoji: String, count: Int)],
        signature: String
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(badges, id: \.emoji) { badge in
                let mine = message.myReaction(currentUserID: currentUserID) == badge.emoji
                let hiddenForFlight = incomingReactionEmoji == badge.emoji
                Button {
                    let wasMine = mine
                    onReact(badge.emoji)
                    if !wasMine {
                        localBurstEmoji = badge.emoji
                        ChatReactionHaptics.reactionSelected()
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(badge.emoji)
                            .font(.caption2)
                            .scaleEffect(
                                badgePopEmoji == badge.emoji && badgePopToken > 0 ? 1 : 1
                            )
                        if badge.count > 1 {
                            Text("\(badge.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(mine ? Color.white.opacity(0.9) : .secondary)
                                .contentTransition(.numericText())
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(mine ? Color.accentColor : Color(.systemGray5))
                    )
                }
                .buttonStyle(.plain)
                .opacity(hiddenForFlight ? 0 : 1)
                .reactionBadgePop(trigger: badgePopEmoji == badge.emoji ? badgePopToken : 0)
                .transition(.scale(scale: 0.01).combined(with: .opacity))
                .onGeometryChange(for: CGRect.self) { proxy in
                    chatTracksBubbleFrames ? proxy.frame(in: .global) : .zero
                } action: { frame in
                    guard chatTracksBubbleFrames, frame.width > 1 else { return }
                    let previous = frameRegistry?.badgeFrame(messageID: message.id, emoji: badge.emoji) ?? .zero
                    guard frame != previous else { return }
                    guard abs(previous.minX - frame.minX) > 0.5
                        || abs(previous.minY - frame.minY) > 0.5
                        || abs(previous.width - frame.width) > 0.5
                    else { return }
                    frameRegistry?.setBadgeFrame(
                        messageID: message.id,
                        emoji: badge.emoji,
                        frame: frame
                    )
                }
            }
        }
        .animation(ChatContextMotion.bounce(damping: 72, duration: 0.35), value: signature)
    }

    private func popBadge(_ emoji: String) {
        badgePopEmoji = emoji
        badgePopToken += 1
    }
}

private struct ChatLocationZoomSource: ViewModifier {
    let id: String
    let enabled: Bool
    @Environment(\.chatZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if enabled, let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Visual bubble body shared by the list row and the lifted overlay copy.
struct ChatBubbleContent: View {
    let message: DMMessage
    let isMine: Bool
    let showTail: Bool
    let groupedWithPrevious: Bool
    let isReadByPeer: Bool
    let replyPreview: DMMessage?
    let postCard: DMPostCard?
    var sharedPost: Post? = nil
    var sharedPostActions: ChatSharedPostActions = .noop
    var currentUserID: String = ""
    var isGroup: Bool = false
    var memberName: (String) -> String = { _ in "" }
    var memberAvatarURL: (String) -> URL? = { _ in nil }
    var onToggleChecklistItem: (Int) -> Void = { _ in }
    var onAppendChecklistItem: (String) -> Void = { _ in }
    var onVotePoll: ([Int]) -> Void = { _ in }
    var onAppendPollOption: (String) -> Void = { _ in }
    var onTapReply: () -> Void = {}
    var isHighlighted: Bool = false

    @Environment(\.chatBubbleInteractionLocked) private var interactionLocked
    @State private var highlightPulse = false

    private var sharedDisplay: ChatSharedPostDisplay {
        ChatSharedPostDisplay.merge(
            postID: message.postID ?? "",
            postTypeHint: message.postType,
            post: sharedPost,
            card: postCard
        )
    }

    private var peerBubbleColor: Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? .secondarySystemBackground
                    : .systemGray5
            }
        )
    }

    private var textColor: Color {
        if isPostShare { return .primary }
        return isMine ? .white : .primary
    }

    private var metaForeground: Color {
        if isPostShare { return .secondary }
        return isMine ? Color.white.opacity(0.7) : Color.secondary
    }

    /// Single shape with an in-bounds tail so overlays and clips never cut it off.
    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            isMine: isMine,
            showTail: showTail && !isMediaOnly && !isPostShareWithoutTail,
            groupedWithPrevious: groupedWithPrevious
        )
    }

    /// Media-only uses the same radii but no tail nub.
    private var mediaClipShape: ChatBubbleShape {
        ChatBubbleShape(
            isMine: isMine,
            showTail: false,
            groupedWithPrevious: groupedWithPrevious
        )
    }

    private var isMediaKind: Bool {
        message.kind == .image || message.kind == .gif
    }

    private var hasCaption: Bool {
        !message.body.isEmpty
    }

    private var isMediaOnly: Bool {
        isMediaKind && !hasCaption && replyPreview == nil
            && (message.forwardedFromUsername ?? "").isEmpty
            && message.deletedAt == nil
    }

    private var isPostShare: Bool {
        message.kind == .postShare && message.deletedAt == nil
    }

    private var isPostShareWithoutTail: Bool {
        isPostShare && !ChatPostShareCard.showsTail(
            postType: message.postType,
            card: postCard,
            post: sharedPost,
            showTail: true
        )
    }

    private var skipsBubbleFill: Bool {
        isMediaOnly || isPostShare || message.kind == .sticker
    }

    private var postShareSurface: Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? .secondarySystemBackground
                    : .systemGray6
            }
        )
    }

    private var postShareBorder: Color {
        isMine ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08)
    }

    /// Reserve the tail strip so grouped bubbles share a common edge.
    private var bodyPadding: EdgeInsets {
        EdgeInsets(
            top: 6,
            leading: isMine ? 12 : 12 + ChatBubbleShape.tailWidth,
            bottom: 6,
            trailing: isMine ? 12 + ChatBubbleShape.tailWidth : 12
        )
    }

    var body: some View {
        Group {
            if message.deletedAt != nil {
                deletedBody
            } else if isMediaOnly {
                mediaOnlyBody
            } else if isMediaKind {
                mediaWithCaptionBody
            } else if isPostShare {
                postShareCardBody
            } else if message.kind == .location, let location = message.location {
                locationBody(location)
            } else if message.kind == .checklist, let checklist = message.checklist {
                checklistBody(checklist)
            } else if message.kind == .poll, let poll = message.poll {
                pollBody(poll)
            } else if message.kind == .sticker {
                stickerBody
            } else {
                standardBody
            }
        }
        .background {
            if !skipsBubbleFill {
                bubbleFill
                    .animation(
                        .spring(response: 0.32, dampingFraction: 0.8),
                        value: showTail && !skipsBubbleFill
                    )
            }
        }
        .overlay {
            bubbleShape
                .fill(Color.accentColor.opacity(isMine ? 0.42 : 0.32))
                .opacity(highlightPulse ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onAppear {
            playReplyHighlightIfNeeded()
        }
        .onChange(of: isHighlighted) { _, highlighted in
            if highlighted {
                playReplyHighlightIfNeeded()
            } else {
                highlightPulse = false
            }
        }
    }

    /// Telegram-style double flash once the scrolled-to bubble is on screen.
    private func playReplyHighlightIfNeeded() {
        guard isHighlighted else { return }
        if AccessibilitySettings.reduceMotion {
            highlightPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                highlightPulse = false
            }
            return
        }
        highlightPulse = false
        withAnimation(.easeIn(duration: 0.12)) {
            highlightPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.16)) {
                highlightPulse = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard isHighlighted else { return }
            withAnimation(.easeIn(duration: 0.12)) {
                highlightPulse = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            withAnimation(.easeOut(duration: 0.45)) {
                highlightPulse = false
            }
        }
    }

    @ViewBuilder
    private var bubbleFill: some View {
        if isMine {
            bubbleShape.fill(Color.accentColor)
        } else {
            bubbleShape.fill(peerBubbleColor)
        }
    }

    private var deletedBody: some View {
        Text("Message deleted")
            .italic()
            .foregroundStyle(isMine ? Color.white.opacity(0.8) : .secondary)
            .padding(bodyPadding)
    }

    private var mediaOnlyBody: some View {
        mediaImage(showGIFBadge: message.kind == .gif)
            .clipShape(mediaClipShape)
            .overlay(alignment: .bottomTrailing) {
                mediaTimeCapsule
                    .padding(.trailing, 8 + (isMine ? ChatBubbleShape.tailWidth : 0))
                    .padding(.bottom, 6)
            }
    }

    private var mediaWithCaptionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            mediaImage(showGIFBadge: message.kind == .gif)
            VStack(alignment: .leading, spacing: 4) {
                headerChrome
                textWithTrailingMeta(message.body)
            }
            .padding(bodyPadding)
            .frame(
                width: mediaSize.width + ChatBubbleShape.tailWidth,
                alignment: .leading
            )
        }
    }

    private func locationBody(_ location: DMLocation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasHeaderChrome {
                VStack(alignment: .leading, spacing: 4) {
                    headerChrome
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
            ChatLocationBubble(location: location, isMine: isMine) {
                metaRow(onMedia: false)
            }
        }
        .frame(
            width: ChatLocationBubbleMetrics.mapWidth + ChatBubbleShape.tailWidth,
            alignment: isMine ? .leading : .trailing
        )
        .clipShape(bubbleShape)
    }

    private func checklistBody(_ checklist: DMChecklist) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            headerChrome
            ChatChecklistBubble(
                message: message,
                checklist: checklist,
                isMine: isMine,
                currentUserID: currentUserID,
                isGroup: isGroup,
                memberName: memberName,
                memberAvatarURL: memberAvatarURL,
                onToggle: onToggleChecklistItem,
                onAppend: onAppendChecklistItem
            ) {
                metaRow(onMedia: false)
            }
        }
        .padding(bodyPadding)
        .frame(width: 280 + ChatBubbleShape.tailWidth, alignment: .leading)
    }

    private func pollBody(_ poll: DMPoll) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            headerChrome
            ChatPollBubble(
                message: message,
                poll: poll,
                isMine: isMine,
                currentUserID: currentUserID,
                memberName: memberName,
                memberAvatarURL: memberAvatarURL,
                onVote: onVotePoll,
                onAppend: onAppendPollOption
            ) {
                metaRow(onMedia: false)
            }
        }
        .padding(bodyPadding)
        .frame(width: 280 + ChatBubbleShape.tailWidth, alignment: .leading)
    }

    private var hasHeaderChrome: Bool {
        if let name = message.forwardedFromUsername, !name.isEmpty { return true }
        return replyPreview != nil
    }

    private var standardBody: some View {
        BubbleWidth(maxWidth: 280 + ChatBubbleShape.tailWidth) {
            VStack(alignment: .leading, spacing: 4) {
                headerChrome
                textWithTrailingMeta(message.body)
            }
            .padding(bodyPadding)
        }
    }

    private var postShareCardBody: some View {
        let showTailOnCard = ChatPostShareCard.showsTail(
            postType: message.postType,
            card: postCard,
            post: sharedPost,
            showTail: showTail
        )
        let shape = ChatBubbleShape(
            isMine: isMine,
            showTail: showTailOnCard,
            groupedWithPrevious: groupedWithPrevious
        )
        let isShot = sharedDisplay.isShot
        let showMediaMeta = isShot && !hasCaption && !hasHeaderChrome
        return VStack(alignment: .leading, spacing: 0) {
            if hasHeaderChrome {
                VStack(alignment: .leading, spacing: 4) {
                    headerChrome
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            ChatPostShareCard(
                display: sharedDisplay,
                post: sharedPost,
                isMine: isMine,
                mediaMeta: showMediaMeta
                    ? { AnyView(mediaTimeCapsule) }
                    : nil,
                actions: sharedPostActions
            )
            if hasCaption {
                VStack(alignment: .leading, spacing: 4) {
                    textWithTrailingMeta(message.body)
                }
                .padding(bodyPadding)
            } else if !isShot {
                VStack(alignment: .leading, spacing: 4) {
                    metaRow(onMedia: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(bodyPadding)
            }
        }
        .background(postShareSurface)
        .clipShape(shape)
        .overlay {
            shape.stroke(postShareBorder, lineWidth: 1)
        }
    }

    /// Post-share cards use a neutral surface, so chrome must not assume accent fill.
    private var chromeOnTintedBubble: Bool {
        isMine && !isPostShare
    }

    @ViewBuilder
    private var headerChrome: some View {
        if let name = message.forwardedFromUsername, !name.isEmpty {
            Label("Forwarded from @\(name)", systemImage: "arrowshape.turn.up.right")
                .font(.caption2)
                .foregroundStyle(chromeOnTintedBubble ? Color.white.opacity(0.75) : .secondary)
        }
        if let reply = replyPreview {
            replyQuote(reply)
        }
    }

    /// Text hugs its content. Time and the read mark sit on the bubble's trailing edge.
    private func textWithTrailingMeta(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Self.softWrapped(body))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
            metaRow(onMedia: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Lets long URLs wrap inside the bubble instead of running off the edge.
    private static func softWrapped(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false).map { token in
            guard token.count > 28 else { return String(token) }
            var parts: [String] = []
            var index = token.startIndex
            while index < token.endIndex {
                let end = token.index(index, offsetBy: 24, limitedBy: token.endIndex) ?? token.endIndex
                parts.append(String(token[index..<end]))
                index = end
            }
            return parts.joined(separator: "\u{200B}")
        }.joined(separator: " ")
    }

    private func metaRow(onMedia: Bool) -> some View {
        HStack(spacing: 3) {
            if message.editedAt != nil {
                Text("edited")
                    .font(.caption2)
            }
            Text(timeLabel)
                .font(.caption2)
            if isMine {
                statusIcon(onMedia: onMedia)
            }
        }
        .foregroundStyle(onMedia ? Color.white : metaForeground)
    }

    private var mediaTimeCapsule: some View {
        metaRow(onMedia: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    @ViewBuilder
    private func statusIcon(onMedia: Bool) -> some View {
        if message.isFailed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        } else if message.isPending {
            Image(systemName: "clock")
                .font(.caption2)
        } else if isReadByPeer {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
        } else {
            Image(systemName: "checkmark")
                .font(.caption2)
        }
    }

    private var timeLabel: String {
        ChatDateCache.time(message.createdAt)
    }

    private var stickerBody: some View {
        ZStack(alignment: .bottomTrailing) {
            LazyImage(url: message.mediaThumbURL ?? message.mediaURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 160, height: 160)
            mediaTimeCapsule
                .padding(6)
        }
        .accessibilityLabel("Sticker")
    }

    @ViewBuilder
    private func mediaImage(showGIFBadge: Bool) -> some View {
        let size = mediaSize
        ZStack(alignment: .topLeading) {
            Group {
                if let data = message.localImageData,
                   let ui = ChatLocalImageCache.image(clientMsgID: message.clientMsgID, data: data)
                {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else if message.kind == .gif, let url = message.mediaURL {
                    ZStack {
                        if let thumb = message.mediaThumbURL, thumb != url {
                            ChatProgressiveImage(thumbnailURL: thumb, imageURL: nil)
                        } else {
                            mediaPlaceholder
                        }
                        AnimatedRemoteImage(
                            url: url,
                            contentMode: .scaleAspectFill,
                            maxPixelSize: 480
                        )
                    }
                } else if message.mediaThumbURL != nil || message.mediaURL != nil {
                    ChatProgressiveImage(
                        thumbnailURL: message.mediaThumbURL,
                        imageURL: message.mediaURL
                    )
                } else {
                    mediaPlaceholder
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            if showGIFBadge {
                Text("GIF")
                    .font(.caption2.bold())
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Shows the small thumb immediately, then the full image on top once it arrives.
private struct ChatProgressiveImage: View {
    var thumbnailURL: URL?
    var imageURL: URL?
    @State private var hasFull = false

    private var thumb: URL? {
        guard let thumbnailURL, thumbnailURL != imageURL else { return nil }
        return thumbnailURL
    }

    var body: some View {
        ZStack {
            if !hasFull, let thumb {
                remote(thumb, width: 480)
            } else if !hasFull {
                Color.black.opacity(0.08)
            }
            if let imageURL {
                LazyImage(url: imageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .scaledToFill()
                            .onAppear { hasFull = true }
                    }
                }
                .processors([.resize(width: 960)])
            }
        }
        .onChange(of: imageURL) { _, _ in
            hasFull = false
        }
    }

    private func remote(_ url: URL, width: CGFloat) -> some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            }
        }
        .processors([.resize(width: width)])
    }
}

private extension ChatBubbleContent {
    private var mediaPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.08)
            if message.isMediaProcessing {
                ProgressView()
            }
        }
    }

    private func replyQuote(_ reply: DMMessage) -> some View {
        let title = replyPreviewTitle(reply)
        let body = replyPreviewBody(reply)
        let canJump = !interactionLocked && reply.deletedAt == nil
        return Button {
            onTapReply()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(chromeOnTintedBubble ? Color.white.opacity(0.85) : Color.accentColor)
                    .frame(width: 3, height: title == body ? 16 : 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(chromeOnTintedBubble ? Color.white.opacity(0.9) : Color.accentColor)
                        .lineLimit(1)
                    if body != title {
                        Text(body)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(chromeOnTintedBubble ? Color.white.opacity(0.7) : .secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 8)
            .padding(.leading, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(chromeOnTintedBubble ? Color.white.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canJump)
        .accessibilityHint(canJump ? "Jump to original message" : "")
    }

    private func replyPreviewTitle(_ reply: DMMessage) -> String {
        switch reply.kind {
        case .postShare: return "Post"
        case .image: return "Photo"
        case .gif: return "GIF"
        case .location: return "Location"
        case .checklist: return "Checklist"
        case .poll: return "Poll"
        case .sticker: return "Sticker"
        default: return "Reply"
        }
    }

    private func replyPreviewBody(_ reply: DMMessage) -> String {
        if reply.deletedAt != nil { return "Message deleted" }
        switch reply.kind {
        case .image: return "Photo"
        case .gif: return "GIF"
        case .postShare: return "Shared a post"
        case .location: return reply.location?.name ?? "Location"
        case .checklist: return reply.checklist?.title.isEmpty == false ? (reply.checklist?.title ?? "Checklist") : "Checklist"
        case .poll: return reply.poll?.question.isEmpty == false ? (reply.poll?.question ?? "Poll") : "Poll"
        case .sticker: return "Sticker"
        default: return reply.body
        }
    }

    private var mediaSize: CGSize {
        let maxW: CGFloat = 260
        let w = CGFloat(message.mediaWidth ?? 240)
        let h = CGFloat(message.mediaHeight ?? 240)
        let scale = min(1, maxW / max(w, 1))
        return CGSize(width: max(120, w * scale), height: max(120, h * scale))
    }
}

/// iMessage/Telegram-style bubble: body inset by `tailWidth` on the sender side,
/// continuous system corners, and an in-bounds drop tail that never leaves `rect`.
struct ChatBubbleShape: Shape {
    var isMine: Bool
    var groupedWithPrevious: Bool
    /// 0 = joined bottom corner, 1 = full drop tail. Animatable.
    var tailProgress: CGFloat

    static let tailWidth: CGFloat = 9
    static let outerRadius: CGFloat = 18
    static let joinedRadius: CGFloat = 5

    var animatableData: CGFloat {
        get { tailProgress }
        set { tailProgress = newValue }
    }

    init(isMine: Bool, showTail: Bool, groupedWithPrevious: Bool) {
        self.isMine = isMine
        self.groupedWithPrevious = groupedWithPrevious
        self.tailProgress = showTail ? 1 : 0
    }

    init(isMine: Bool, groupedWithPrevious: Bool, tailProgress: CGFloat) {
        self.isMine = isMine
        self.groupedWithPrevious = groupedWithPrevious
        self.tailProgress = min(max(tailProgress, 0), 1)
    }

    func path(in rect: CGRect) -> Path {
        let tw = Self.tailWidth
        let body = CGRect(
            x: isMine ? rect.minX : rect.minX + tw,
            y: rect.minY,
            width: rect.width - tw,
            height: rect.height
        )
        let outer = Self.outerRadius
        let joined = Self.joinedRadius
        let p = min(max(tailProgress, 0), 1)
        let topSender = groupedWithPrevious ? joined : outer
        let bottomSenderRadius = joined * (1 - p)

        let tl: CGFloat
        let tr: CGFloat
        let bl: CGFloat
        let br: CGFloat
        if isMine {
            tl = outer
            tr = topSender
            bl = outer
            br = bottomSenderRadius
        } else {
            tl = topSender
            tr = outer
            bl = bottomSenderRadius
            br = outer
        }

        let clamp: (CGFloat) -> CGFloat = { v in
            min(max(v, 0), body.height / 2, body.width / 2)
        }
        let bodyPath = UnevenRoundedRectangle(
            topLeadingRadius: clamp(tl),
            bottomLeadingRadius: clamp(bl),
            bottomTrailingRadius: clamp(br),
            topTrailingRadius: clamp(tr),
            style: .continuous
        ).path(in: body)

        guard p > 0.001 else { return bodyPath }

        let tailPath = isMine
            ? Self.mineTailPath(body: body, rect: rect, progress: p)
            : Self.peerTailPath(body: body, rect: rect, progress: p)
        return bodyPath.union(tailPath)
    }

    /// Drop tail on the trailing (mine) side. Fully in-bounds of `rect`.
    private static func mineTailPath(body: CGRect, rect: CGRect, progress: CGFloat) -> Path {
        let maxX = body.maxX
        let maxY = body.maxY
        let tipX = maxX + (rect.maxX - maxX) * progress
        let inset: CGFloat = 10
        var path = Path()
        path.move(to: CGPoint(x: maxX - inset, y: maxY - 16))
        path.addLine(to: CGPoint(x: maxX, y: maxY - 16))
        path.addCurve(
            to: CGPoint(x: tipX, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - 2),
            control2: CGPoint(x: maxX + (tipX - maxX) * 0.55, y: maxY)
        )
        path.addCurve(
            to: CGPoint(x: maxX - inset, y: maxY),
            control1: CGPoint(x: tipX - (tipX - maxX) * 0.35, y: maxY + 0.5 * progress),
            control2: CGPoint(x: maxX - 4 * progress, y: maxY)
        )
        path.closeSubpath()
        return path
    }

    /// Drop tail on the leading (peer) side. Mirror of the mine tail.
    private static func peerTailPath(body: CGRect, rect: CGRect, progress: CGFloat) -> Path {
        let minX = body.minX
        let maxY = body.maxY
        let tipX = minX - (minX - rect.minX) * progress
        let inset: CGFloat = 10
        var path = Path()
        path.move(to: CGPoint(x: minX + inset, y: maxY - 16))
        path.addLine(to: CGPoint(x: minX, y: maxY - 16))
        path.addCurve(
            to: CGPoint(x: tipX, y: maxY),
            control1: CGPoint(x: minX, y: maxY - 2),
            control2: CGPoint(x: tipX + (minX - tipX) * 0.55, y: maxY)
        )
        path.addCurve(
            to: CGPoint(x: minX + inset, y: maxY),
            control1: CGPoint(x: tipX + (minX - tipX) * 0.35, y: maxY + 0.5 * progress),
            control2: CGPoint(x: minX + 4 * progress, y: maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// Width of the text, capped. Short messages stay short; long ones wrap.
struct BubbleWidth: Layout {
    var maxWidth: CGFloat = 280

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let limit = min(proposal.width ?? maxWidth, maxWidth)
        let natural = child.sizeThatFits(.unspecified)
        if natural.width <= limit {
            return natural
        }
        return child.sizeThatFits(ProposedViewSize(width: limit, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

struct ChatComposerBar: View {
    var draftText: String
    var draftRevision: Int
    var hasText: Bool
    var replyTo: DMMessage?
    var editingMessage: DMMessage? = nil
    var pendingPasteImages: [UIImage] = []
    var focusToken: Int = 0
    var fieldFrameBox: FrameBox? = nil
    var onCancelReply: () -> Void
    var onCancelEdit: () -> Void = {}
    var onAttach: () -> Void
    var onExpressions: () -> Void = {}
    var onSend: () -> Void
    var onTextChange: (String) -> Void
    var onDraftChange: () -> Void
    var onPasteImages: ([UIImage]) -> Void
    var onConfirmPasteImages: ([UIImage]) -> Void
    var onCancelPasteImages: () -> Void

    @Namespace private var glassNS
    @State private var showSend = false
    @State private var isLaunching = false
    @State private var hideSendTask: Task<Void, Never>?
    @State private var pressScale: CGFloat = 1
    @State private var arrowNudge = CGSize.zero
    /// Snapshot kept on screen while the preview collapses.
    @State private var shownPasteImages: [UIImage] = []
    /// 0…1 height of the preview. Drives the layout so the composer rises instead of jumping.
    @State private var pasteReveal: CGFloat = 0
    @State private var pasteRevealTask: Task<Void, Never>?

    private var isEditing: Bool { editingMessage != nil }

    private var showsExpressions: Bool {
        !isEditing && pendingPasteImages.isEmpty
    }

    private var canSend: Bool {
        hasText || !pendingPasteImages.isEmpty
    }

    var body: some View {
        DirectGlassContainer(spacing: 8) {
            VStack(spacing: 8) {
                if !shownPasteImages.isEmpty {
                    PasteGrowMotion(progress: pasteReveal) {
                        pastePreview
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if let editingMessage {
                    HStack {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(editingMessage.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(action: onCancelEdit) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .directGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .directGlassID("edit", in: glassNS)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let replyTo {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reply")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(replySummary(replyTo))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(action: onCancelReply) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .directGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .directGlassID("reply", in: glassNS)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(alignment: .bottom, spacing: 8) {
                    if !isEditing, pendingPasteImages.isEmpty {
                        Button(action: onAttach) {
                            Image(systemName: "paperclip")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                                .directGlass(Circle(), interactive: true)
                                .directGlassID("attach", in: glassNS)
                                .directGlassTransition()
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.92, anchor: .bottom))
                    }

                    ChatComposerTextView(
                        text: draftText,
                        textRevision: draftRevision,
                        placeholder: pendingPasteImages.isEmpty
                            ? (isEditing ? "Edit message…" : "Message")
                            : "Add a caption…",
                        focusToken: focusToken,
                        onTextChange: onTextChange,
                        onDraftChange: onDraftChange,
                        onPasteImages: onPasteImages
                    )
                    .padding(.trailing, showsExpressions ? 40 : 0)
                    .overlay(alignment: .trailing) {
                        if showsExpressions {
                            Button(action: onExpressions) {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundStyle(Color.primary.opacity(0.72))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                            .accessibilityLabel("Stickers, GIFs, and emoji")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .directGlass(
                        RoundedRectangle(cornerRadius: 20, style: .continuous),
                        tint: Color(.systemBackground).opacity(0.55)
                    )
                    .directGlassID("field", in: glassNS)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        guard let box = fieldFrameBox, frame.width > 1, frame.height > 1 else { return }
                        let previous = box.frame
                        guard frame != previous else { return }
                        guard abs(previous.minX - frame.minX) > 0.5
                            || abs(previous.minY - frame.minY) > 0.5
                            || abs(previous.width - frame.width) > 0.5
                            || abs(previous.height - frame.height) > 0.5
                        else { return }
                        box.frame = frame
                    }

                    if showSend {
                        sendButton
                            .fixedSize()
                            .layoutPriority(1)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.2), value: replyTo?.id)
        .animation(.easeInOut(duration: 0.2), value: editingMessage?.id)
        .onAppear {
            showSend = canSend
            if !pendingPasteImages.isEmpty {
                shownPasteImages = pendingPasteImages
                pasteReveal = 1
            }
        }
        .onChange(of: pendingPasteImages.isEmpty) { _, empty in
            if empty {
                collapsePastePreview()
            } else {
                revealPastePreview()
            }
        }
        .onChange(of: pendingPasteImages.count) { _, count in
            guard count > 0 else { return }
            shownPasteImages = pendingPasteImages
        }
        .onChange(of: canSend) { _, ready in
            if ready { ShotHaptics.prepareSend() }
            updateShowSend(ready: ready)
        }
        .onDisappear {
            hideSendTask?.cancel()
            pasteRevealTask?.cancel()
        }
        .defersSystemGestures(on: .bottom)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: showSend) { _, new in new }
    }

    private var sendButton: some View {
        Button(action: sendTapped) {
            Image(systemName: isEditing ? "checkmark" : "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .offset(x: arrowNudge.width, y: arrowNudge.height)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .background(Circle().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .scaleEffect(pressScale)
    }

    private func revealPastePreview() {
        shownPasteImages = pendingPasteImages
        guard !AccessibilitySettings.reduceMotion else {
            pasteReveal = 1
            return
        }
        // Let the zero-height frame land, then grow it. A new view cannot interpolate from a state it never had.
        pasteReveal = 0
        pasteRevealTask?.cancel()
        pasteRevealTask = Task { @MainActor in
            guard !pendingPasteImages.isEmpty else { return }
            withAnimation(ChatSendMotion.paste) {
                pasteReveal = 1
            }
        }
    }

    private func collapsePastePreview() {
        guard !AccessibilitySettings.reduceMotion else {
            pasteReveal = 0
            shownPasteImages = []
            return
        }
        withAnimation(ChatSendMotion.paste, completionCriteria: .logicallyComplete) {
            pasteReveal = 0
        } completion: {
            if pendingPasteImages.isEmpty {
                shownPasteImages = []
            }
        }
    }

    private var pastePreview: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if shownPasteImages.count == 1, let image = shownPasteImages.first {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(shownPasteImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
            .blur(radius: 10 * (1 - pasteReveal))
            .frame(maxWidth: .infinity)
            .padding(8)

            Button(action: onCancelPasteImages) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .directGlass(Circle(), interactive: true)
                    .directGlassID("paste-close", in: glassNS)
                    .directGlassTransition()
            }
            .buttonStyle(.plain)
            .padding(12)
            .scaleEffect(0.72 + 0.28 * pasteReveal)
            .accessibilityLabel("Cancel")
        }
        .directGlass(
            RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: Color(.systemBackground).opacity(0.55)
        )
        .directGlassID("paste", in: glassNS)
        .directGlassTransition()
    }

    private func updateShowSend(ready: Bool) {
        hideSendTask?.cancel()
        if ready {
            withAnimation(.snappy(duration: 0.32, extraBounce: 0.16)) {
                showSend = true
            }
            return
        }
        if isLaunching {
            hideSendTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                    showSend = false
                    isLaunching = false
                }
            }
        } else {
            withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                showSend = false
            }
        }
    }

    private func handleSendPress(_ pressed: Bool) {
        if pressed {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                pressScale = 0.88
            }
            return
        }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            pressScale = 1
        }
        guard !isEditing else { return }
        ShotHaptics.send()
        withAnimation(.easeOut(duration: 0.09)) {
            arrowNudge = CGSize(width: 6, height: -6)
        }
        withAnimation(.easeIn(duration: 0.09).delay(0.09)) {
            arrowNudge = .zero
        }
    }

    private func sendTapped() {
        isLaunching = true
        if !shownPasteImages.isEmpty {
            onConfirmPasteImages(shownPasteImages)
            return
        }
        onSend()
    }

    private func replySummary(_ m: DMMessage) -> String {
        switch m.kind {
        case .image: return "Photo"
        case .gif: return "GIF"
        case .postShare: return "Shared a post"
        case .location: return "Location"
        case .checklist: return m.checklist?.title.isEmpty == false ? (m.checklist?.title ?? "Checklist") : "Checklist"
        case .poll: return m.poll?.question.isEmpty == false ? (m.poll?.question ?? "Poll") : "Poll"
        case .sticker: return "Sticker"
        default: return m.body
        }
    }
}

/// Grows a composer surface up from the field. Opacity is omitted: on glass it paints a black disc.
struct PastePreviewMotion: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 0.98 + 0.02 * progress, y: 0.94 + 0.06 * progress, anchor: .bottom)
            .offset(y: 12 * (1 - progress))
    }
}

/// Reveals a view from its bottom edge so the bar above it glides up.
struct PasteGrowMotion: Layout, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(proposal)
        let amount = min(max(progress, 0), 1)
        let width = natural.width.isFinite ? natural.width : (proposal.width ?? 0)
        let height = min(natural.height.isFinite ? natural.height : 0, 480) * amount
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let natural = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(width: bounds.width, height: natural.height)
        )
    }
}

private struct MessageSendPressStyle: ButtonStyle {
    var onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                onPress(pressed)
            }
    }
}
