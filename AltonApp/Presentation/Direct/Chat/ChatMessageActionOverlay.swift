import SwiftUI
import UIKit

struct ChatActionTarget: Identifiable, Equatable {
    let message: DMMessage
    let bubbleFrame: CGRect
    let isMine: Bool
    let isReadByPeer: Bool
    let replyPreview: DMMessage?
    let postCard: DMPostCard?
    var sharedPost: Post? = nil
    let infoLine: String
    let myEmoji: String?
    let currentUserID: String
    /// Scale of the bubble at the moment the press activated (Telegram press shrink).
    let startScale: CGFloat
    let showTail: Bool
    let groupedWithPrevious: Bool

    var id: String { message.id }
}

enum ChatMessageAction: Equatable {
    case reply
    case copy
    case copyMedia
    case edit
    case forward
    case delete
    case retry
    case retractVote
    case stopPoll
}

struct ChatMessageActionOverlay: View {
    let target: ChatActionTarget
    let safeArea: CGRect
    /// Window-space finger while the opening long-press is still down.
    var fingerPoint: CGPoint? = nil
    /// Increments when that finger lifts.
    var fingerRelease: Int = 0
    /// Called with emoji, global source frame, and whether this was a charged big-commit.
    var onReact: (String, CGRect, Bool) -> Void
    var onAction: (ChatMessageAction) -> Void
    var onDismiss: () -> Void

    private enum Phase: Equatable {
        case incoming
        case visible
        case returning
    }

    @State private var phase: Phase = .incoming
    @State private var showGrid = false
    @State private var pickingEmoji: String?
    @State private var highlightedEmoji: String?
    /// When highlight began; charge shake uses elapsed from this date.
    @State private var highlightStartedAt: Date?
    @State private var chargeTask: Task<Void, Never>?
    @State private var chargeHaptics = ChatReactionChargeHaptics()
    @State private var emojiFrames: [String: CGRect] = [:]
    @State private var menuHeight: CGFloat = 0
    @State private var barWidth: CGFloat = 0
    @State private var blurActive = false
    @State private var isDismissing = false
    @State private var barChrome = ReactionBarChrome()
    @Namespace private var glassNS

    private var isVisible: Bool { phase == .visible }

    private var usable: CGRect {
        safeArea.insetBy(
            dx: ChatActionOverlayLayout.horizontalInset,
            dy: ChatActionOverlayLayout.spacing
        )
    }

    private var resolvedMenuHeight: CGFloat {
        if menuHeight > 1 { return menuHeight }
        return Self.estimatedMenuHeight(
            message: target.message,
            isMine: target.isMine,
            currentUserID: target.currentUserID
        )
    }

    private var resolvedBarWidth: CGFloat {
        let natural = min(CGFloat(DMReactionCatalog.quick.count + 1) * 38 + 16, usable.width)
        if barWidth > 1 { return min(barWidth, usable.width) }
        return natural
    }

    private var placement: ChatActionOverlayLayout.Placement {
        let fittedBar = resolvedBarWidth
        return ChatActionOverlayLayout.resolve(
            bubbleFrame: target.bubbleFrame,
            safeArea: safeArea,
            menuHeight: resolvedMenuHeight,
            barWidth: fittedBar,
            menuWidth: min(ChatActionOverlayLayout.menuEstimatedWidth, usable.width),
            isMine: target.isMine
        )
    }

    private var menuAboveBubble: Bool {
        placement.menuFrame.midY < placement.bubbleFrame.midY
    }

    private var menuScaleAnchor: UnitPoint {
        if menuAboveBubble {
            return target.isMine ? .bottomTrailing : .bottomLeading
        }
        return target.isMine ? .topTrailing : .topLeading
    }

    private var barScaleAnchor: UnitPoint {
        target.isMine ? .bottomTrailing : .bottomLeading
    }

    private var menuPresentationScale: CGFloat {
        switch phase {
        case .incoming: return 0.01
        case .visible: return showGrid ? 0.9 : 1
        case .returning: return 1
        }
    }

    private var bubbleScale: CGFloat {
        phase == .incoming ? target.startScale : 1
    }

    var body: some View {
        GeometryReader { geo in
            let place = placement
            let origin = geo.frame(in: .global)
            let bubble = isVisible ? place.bubbleFrame : target.bubbleFrame
            let travel = bubble.minY - place.bubbleFrame.minY
            let bar = place.barFrame.offsetBy(dx: 0, dy: travel)
            let menu = place.menuFrame.offsetBy(dx: 0, dy: travel)
            ZStack {
                ContextBlurView(isActive: blurActive)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                Color.black.opacity(isVisible ? ChatContextMotion.backdropDimOpacity : 0)
                    .ignoresSafeArea()
                    .animation(
                        .easeInOut(duration: ChatContextMotion.blurDuration),
                        value: phase
                    )
                    .onTapGesture { dismissOverlay() }

                ChatBubbleContent(
                    message: target.message,
                    isMine: target.isMine,
                    showTail: target.showTail,
                    groupedWithPrevious: target.groupedWithPrevious,
                    isReadByPeer: target.isReadByPeer,
                    replyPreview: target.replyPreview,
                    postCard: target.postCard,
                    sharedPost: target.sharedPost,
                    sharedPostActions: .noop
                )
                .environment(\.chatBubbleInteractionLocked, true)
                .frame(width: bubble.width, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(isVisible ? 0.16 : 0), radius: 14, y: 4)
                .scaleEffect(bubbleScale)
                .position(localPoint(bubble.center, origin: origin))
                .animation(
                    phase == .returning
                        ? ChatContextMotion.dismissReturn()
                        : ChatContextMotion.presentSpring(),
                    value: phase
                )
                .allowsHitTesting(false)

                let panel = showGrid ? gridFrame.offsetBy(dx: 0, dy: travel) : bar
                let metrics = ReactionBarMetrics(maxWidth: place.barFrame.width)
                ZStack(alignment: target.isMine ? .bottomTrailing : .bottomLeading) {
                    // Glass-only layer under content so emoji stay visible above the glass.
                    DirectGlassContainer(spacing: 0) {
                        if !showGrid {
                            ReactionBarGlass(
                                metrics: metrics,
                                chrome: barChrome,
                                isMine: target.isMine
                            )
                            .directGlassID("reaction-panel", in: glassNS)
                            .opacity(isVisible ? 1 : 0)
                        } else {
                            reactionGridGlassBackground
                        }
                    }
                    .frame(
                        width: panel.width,
                        height: panel.height,
                        alignment: target.isMine ? .bottomTrailing : .bottomLeading
                    )
                    .allowsHitTesting(false)

                    ReactionBar(
                        metrics: metrics,
                        chrome: barChrome,
                        selectedEmoji: pickingEmoji ?? target.myEmoji,
                        pickingEmoji: pickingEmoji,
                        isMine: target.isMine,
                        highlightedEmoji: highlightedEmoji,
                        highlightStartedAt: highlightStartedAt,
                        onEmojiFrame: { emoji, frame in
                            emojiFrames[emoji] = frame
                        },
                        onPointer: { point, isDown in
                            handleBarPointer(point: point, isDown: isDown)
                        },
                        onExpand: {
                            withAnimation(ChatContextMotion.gridSpring()) { showGrid = true }
                        },
                        onWidthChange: { width in
                            let fitted = min(width, usable.width)
                            if abs(fitted - barWidth) > 0.5 {
                                barWidth = fitted
                            }
                        }
                    )
                    .frame(width: bar.width, height: bar.height, alignment: target.isMine ? .trailing : .leading)
                    .opacity(isVisible && !showGrid ? 1 : 0)
                    .animation(
                        phase == .returning
                            ? ChatContextMotion.dismissReturn()
                            : ChatContextMotion.presentSpring(),
                        value: phase
                    )
                    .allowsHitTesting(!showGrid)

                    ReactionGridPanel(
                        selectedEmoji: pickingEmoji ?? target.myEmoji,
                        pickingEmoji: pickingEmoji,
                        isShown: showGrid,
                        isMine: target.isMine,
                        onSelect: { emoji, frame in
                            selectReaction(emoji, source: frame, isLarge: false)
                        },
                        onCollapse: {
                            withAnimation(ChatContextMotion.gridSpring()) { showGrid = false }
                        }
                    )
                    .opacity(showGrid ? 1 : 0)
                    .scaleEffect(showGrid ? 1 : 0.15, anchor: barScaleAnchor)
                    .allowsHitTesting(showGrid)
                }
                .frame(width: panel.width, height: panel.height, alignment: target.isMine ? .bottomTrailing : .bottomLeading)
                .position(localPoint(panel.center, origin: origin))
                .animation(ChatContextMotion.gridSpring(), value: showGrid)

                MessageActionMenu(
                    message: target.message,
                    isMine: target.isMine,
                    infoLine: target.infoLine,
                    isReadByPeer: target.isReadByPeer,
                    currentUserID: target.currentUserID,
                    onAction: { action in
                        ChatReactionHaptics.actionSelected()
                        onAction(action)
                        dismissOverlay()
                    },
                    onHeightChange: { height in
                        if abs(height - menuHeight) > 0.5 {
                            menuHeight = height
                        }
                    }
                )
                .frame(width: menu.width)
                .scaleEffect(menuPresentationScale, anchor: menuScaleAnchor)
                .opacity((isVisible && !showGrid) ? 1 : 0)
                .position(localPoint(menu.center, origin: origin))
                .animation(
                    phase == .returning
                        ? ChatContextMotion.dismissReturn()
                        : ChatContextMotion.presentSpring(),
                    value: phase
                )
                .animation(ChatContextMotion.gridSpring(), value: showGrid)
                .allowsHitTesting(isVisible && !showGrid)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(ChatContextMotion.gridSpring(), value: showGrid)
        }
        .ignoresSafeArea()
        .onAppear {
            blurActive = true
            withAnimation(ChatContextMotion.presentSpring()) {
                phase = .visible
            }
            runBarAppearSequence()
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .visible:
                runBarAppearSequence()
            case .returning, .incoming:
                withAnimation(.easeInOut(duration: ChatContextMotion.dismissDuration)) {
                    barChrome = ReactionBarChrome()
                }
            }
        }
        .onChange(of: fingerPoint) { _, point in
            guard let point, isVisible, pickingEmoji == nil else { return }
            scrub(at: point)
        }
        .onChange(of: fingerRelease) { _, token in
            guard token > 0, isVisible else { return }
            commitHighlighted(isLarge: false)
        }
        .onDisappear {
            chargeTask?.cancel()
            chargeHaptics.stop()
        }
    }

    /// Expanded emoji grid, clamped inside the content safe area.
    private var gridFrame: CGRect {
        let width = min(usable.width, 340)
        let height = min(300, max(160, usable.height * 0.42))
        let gap = ChatActionOverlayLayout.barGap
        let preferredY = placement.bubbleFrame.minY - gap - height
        let y = min(max(usable.minY, preferredY), max(usable.minY, usable.maxY - height))
        let preferredX = target.isMine ? placement.bubbleFrame.maxX - width : placement.bubbleFrame.minX
        let x = ChatActionOverlayLayout.clampedX(preferred: preferredX, width: width, usable: usable)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Glass morph target for the expanded grid (iOS 26); material fallback otherwise.
    @ViewBuilder
    private var reactionGridGlassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 26, *) {
            shape
                .fill(.clear)
                .directGlass(shape)
                .directGlassID("reaction-panel", in: glassNS)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        }
    }

    private func runBarAppearSequence() {
        withAnimation(
            .easeInOut(duration: 0.2)
                .delay(ChatContextMotion.capsuleScaleDelay)
        ) {
            barChrome.capsuleScaled = true
        }
        withAnimation(
            ChatContextMotion.bounce(duration: ChatContextMotion.capsuleSpringDuration)
                .delay(ChatContextMotion.capsuleExpandDelay)
        ) {
            barChrome.capsuleExpanded = true
        }
        barChrome.itemsVisible = true
    }

    private func localPoint(_ global: CGPoint, origin: CGRect) -> CGPoint {
        CGPoint(x: global.x - origin.minX, y: global.y - origin.minY)
    }

    private static func estimatedMenuHeight(
        message: DMMessage,
        isMine: Bool,
        currentUserID: String
    ) -> CGFloat {
        var buttons = 1 // Reply
        if Self.canCopyText(message) { buttons += 1 }
        if Self.canCopyMedia(message) { buttons += 1 }
        if isMine, DMEditRules.canEdit(message, currentUserID: currentUserID) { buttons += 1 }
        if !message.isPending, message.deletedAt == nil, message.kind != .checklist, message.kind != .poll { buttons += 1 }
        if Self.canRetractVote(message, currentUserID: currentUserID) { buttons += 1 }
        if Self.canStopPoll(message, currentUserID: currentUserID) { buttons += 1 }
        if isMine, message.deletedAt == nil { buttons += 1 } // Delete
        if message.isFailed { buttons += 1 }
        return 40 + CGFloat(buttons) * 45
    }

    static func canCopyText(_ message: DMMessage) -> Bool {
        !message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (message.kind == .text || message.kind == .image || message.kind == .gif)
    }

    static func canRetractVote(_ message: DMMessage, currentUserID: String) -> Bool {
        guard message.kind == .poll, let poll = message.poll, !message.isPending else { return false }
        return ChatPollState.canRetract(
            poll,
            hasVoted: ChatPollState.hasVoted(message.pollVotes, userID: currentUserID)
        )
    }

    static func canStopPoll(_ message: DMMessage, currentUserID: String) -> Bool {
        guard message.kind == .poll, let poll = message.poll, !message.isPending else { return false }
        let isAuthor = message.senderID == currentUserID
        return ChatPollState.canClose(poll, isAuthor: isAuthor)
    }

    static func canCopyMedia(_ message: DMMessage) -> Bool {
        (message.kind == .image || message.kind == .gif)
            && (message.mediaURL != nil || message.localImageData != nil)
    }

    private func selectReaction(_ emoji: String, source: CGRect, isLarge: Bool) {
        guard pickingEmoji == nil else { return }
        stopCharge()
        if isLarge {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        } else {
            ChatReactionHaptics.reactionSelected()
        }
        pickingEmoji = emoji
        highlightedEmoji = emoji
        onReact(emoji, source, isLarge)
        dismissOverlay()
    }

    private func handleBarPointer(point: CGPoint?, isDown: Bool) {
        if let point {
            scrub(at: point)
        }
        if !isDown {
            commitHighlighted(isLarge: false)
        }
    }

    /// Finger sliding across the reaction strip highlights one emoji and may charge.
    private func scrub(at point: CGPoint) {
        guard pickingEmoji == nil, !showGrid else { return }
        let match = emojiFrames.min { lhs, rhs in
            abs(lhs.value.midX - point.x) < abs(rhs.value.midX - point.x)
        }
        guard let match else {
            clearHighlight()
            return
        }
        let verticallyNear = abs(match.value.midY - point.y) < 52
        let emoji: String? = verticallyNear ? match.key : nil
        guard emoji != highlightedEmoji else { return }
        if let emoji {
            beginHighlight(emoji)
        } else {
            clearHighlight()
        }
    }

    private func beginHighlight(_ emoji: String) {
        highlightedEmoji = emoji
        highlightStartedAt = Date()
        ChatReactionHaptics.selectionChanged()
        chargeTask?.cancel()
        chargeHaptics.stop()
        let frame = emojiFrames[emoji] ?? .zero
        chargeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ChatContextMotion.chargeDelay * 1_000_000_000))
            guard !Task.isCancelled, highlightedEmoji == emoji, pickingEmoji == nil else { return }
            chargeHaptics.start()
            try? await Task.sleep(nanoseconds: UInt64(ChatContextMotion.chargeDuration * 1_000_000_000))
            guard !Task.isCancelled, highlightedEmoji == emoji, pickingEmoji == nil else { return }
            let source = emojiFrames[emoji] ?? frame
            selectReaction(emoji, source: source, isLarge: true)
        }
    }

    private func clearHighlight() {
        stopCharge()
        highlightedEmoji = nil
        highlightStartedAt = nil
    }

    private func stopCharge() {
        chargeTask?.cancel()
        chargeTask = nil
        chargeHaptics.stop()
    }

    private func commitHighlighted(isLarge: Bool) {
        guard pickingEmoji == nil, let emoji = highlightedEmoji else {
            stopCharge()
            return
        }
        let elapsed = highlightStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let charged = isLarge || ChatReactionCharge.progress(elapsed: elapsed) >= 0.98
        let frame = emojiFrames[emoji] ?? .zero
        selectReaction(emoji, source: frame, isLarge: charged)
    }

    private func dismissOverlay() {
        guard !isDismissing else { return }
        isDismissing = true
        blurActive = false
        stopCharge()
        withAnimation(ChatContextMotion.dismissReturn()) {
            phase = .returning
            showGrid = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ChatContextMotion.dismissReturnDuration) {
            onDismiss()
        }
    }
}

// MARK: - Animated blur (Telegram UIVisualEffectView path)

private struct ContextBlurView: UIViewRepresentable {
    var isActive: Bool

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        let target: UIVisualEffect? = isActive
            ? UIBlurEffect(style: .systemUltraThinMaterial)
            : nil
        let currentIsActive = uiView.effect != nil
        guard currentIsActive != isActive else { return }
        UIView.animate(
            withDuration: ChatContextMotion.blurDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            uiView.effect = target
        }
    }
}

// MARK: - Reaction bar

private struct ReactionBarChrome: Equatable {
    var capsuleExpanded = false
    var capsuleScaled = false
    var itemsVisible = false
}

private struct ReactionBarMetrics {
    let maxWidth: CGFloat

    /// Seven quick reactions plus the chevron, sized so the bar never exceeds `maxWidth`.
    var slot: CGFloat {
        let inner = max(0, maxWidth - 16)
        return min(38, max(26, floor(inner / 8)))
    }

    var capsuleHeight: CGFloat { slot + 12 }

    var fullWidth: CGFloat {
        let natural = CGFloat(DMReactionCatalog.quick.count + 1) * slot + 16
        return min(natural, maxWidth)
    }

    var collapsedWidth: CGFloat { capsuleHeight }

    func displayedWidth(expanded: Bool) -> CGFloat {
        expanded ? fullWidth : collapsedWidth
    }
}

/// Glass capsule + droplet tail only — kept under emoji content.
private struct ReactionBarGlass: View {
    let metrics: ReactionBarMetrics
    let chrome: ReactionBarChrome
    let isMine: Bool

    var body: some View {
        Color.clear
            .frame(
                width: metrics.displayedWidth(expanded: chrome.capsuleExpanded),
                height: metrics.capsuleHeight
            )
            .directGlass(Capsule())
            .shadow(color: .black.opacity(Self.capsuleShadowOpacity), radius: 10, y: 3)
            .scaleEffect(chrome.capsuleScaled ? 1 : 0.001)
            .overlay(alignment: isMine ? .bottomTrailing : .bottomLeading) {
                ReactionBarTail(isMine: isMine)
                    .offset(y: 5)
                    .opacity(chrome.capsuleExpanded ? 1 : 0)
            }
            .frame(
                width: metrics.maxWidth,
                height: metrics.capsuleHeight,
                alignment: isMine ? .trailing : .leading
            )
    }

    private static var capsuleShadowOpacity: Double {
        if #available(iOS 26, *) { return 0 }
        return 0.12
    }
}

/// Emoji + chevron content drawn above the glass layer.
private struct ReactionBar: View {
    let metrics: ReactionBarMetrics
    let chrome: ReactionBarChrome
    let selectedEmoji: String?
    let pickingEmoji: String?
    let isMine: Bool
    var highlightedEmoji: String? = nil
    var highlightStartedAt: Date? = nil
    var onEmojiFrame: (String, CGRect) -> Void = { _, _ in }
    /// Pointer over the bar: location (or nil) and whether the finger is still down.
    var onPointer: (CGPoint?, Bool) -> Void = { _, _ in }
    var onExpand: () -> Void
    var onWidthChange: (CGFloat) -> Void

    private var displayedWidth: CGFloat {
        metrics.displayedWidth(expanded: chrome.capsuleExpanded)
    }

    private var anchorX: CGFloat {
        isMine ? displayedWidth - metrics.slot / 2 - 8 : metrics.slot / 2 + 8
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(DMReactionCatalog.quick.enumerated()), id: \.element) { index, emoji in
                let centerX = 8 + metrics.slot * (CGFloat(index) + 0.5)
                let delay = ChatContextMotion.itemDelay(
                    itemCenterX: centerX,
                    anchorX: anchorX,
                    width: metrics.fullWidth
                )
                ReactionEmojiButton(
                    emoji: emoji,
                    slot: metrics.slot,
                    isSelected: selectedEmoji == emoji,
                    isPicking: pickingEmoji == emoji,
                    isHighlighted: highlightedEmoji == emoji,
                    highlightStartedAt: highlightedEmoji == emoji ? highlightStartedAt : nil,
                    appearScale: chrome.itemsVisible ? 1 : 0.01,
                    appearDelay: delay,
                    onFrame: { frame in onEmojiFrame(emoji, frame) }
                )
                .zIndex(highlightedEmoji == emoji ? 1 : 0)
            }
            let chevronIndex = DMReactionCatalog.quick.count
            let chevronCenterX = 8 + metrics.slot * (CGFloat(chevronIndex) + 0.5)
            let chevronDelay = ChatContextMotion.itemDelay(
                itemCenterX: chevronCenterX,
                anchorX: anchorX,
                width: metrics.fullWidth
            )
            Button(action: onExpand) {
                Image(systemName: "chevron.down")
                    .font(.system(size: max(12, metrics.slot * 0.42), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.slot, height: metrics.slot)
                    .background(Circle().fill(Self.chevronFill))
            }
            .buttonStyle(.plain)
            .scaleEffect(chrome.itemsVisible ? 1 : 0.01)
            .animation(
                ChatContextMotion.bounce(damping: 88, duration: ChatContextMotion.emojiAppearDuration)
                    .delay(chevronDelay),
                value: chrome.itemsVisible
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: metrics.fullWidth, alignment: isMine ? .trailing : .leading)
        .mask {
            // Capsule width for expand animation; extra height so charge pop can grow upward.
            let overflow = metrics.slot * (ChatReactionCharge.maxScale - 1)
            RoundedRectangle(cornerRadius: metrics.capsuleHeight / 2, style: .continuous)
                .frame(width: displayedWidth, height: metrics.capsuleHeight + overflow)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isMine ? .bottomTrailing : .bottomLeading)
                .padding(.top, -overflow)
        }
        .frame(
            width: metrics.maxWidth,
            height: metrics.capsuleHeight,
            alignment: isMine ? .trailing : .leading
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    onPointer(value.location, true)
                }
                .onEnded { value in
                    onPointer(value.location, false)
                }
        )
        .background(
            GeometryReader { _ in
                Color.clear
                    .onAppear { onWidthChange(metrics.fullWidth) }
                    .onChange(of: metrics.fullWidth) { _, w in onWidthChange(w) }
            }
        )
    }

    private static var chevronFill: Color {
        if #available(iOS 26, *) {
            return Color.primary.opacity(0.08)
        }
        return Color(.systemGray5).opacity(0.9)
    }
}

private struct ReactionBarTail: View {
    let isMine: Bool

    var body: some View {
        HStack(spacing: 3) {
            if isMine { Spacer(minLength: 0) }
            Color.clear
                .frame(width: 10, height: 10)
                .directGlass(Circle())
            Color.clear
                .frame(width: 6, height: 6)
                .directGlass(Circle())
            if !isMine { Spacer(minLength: 0) }
        }
        .frame(width: 28)
        .allowsHitTesting(false)
    }
}

private struct ReactionEmojiButton: View {
    let emoji: String
    let slot: CGFloat
    let isSelected: Bool
    let isPicking: Bool
    var isHighlighted: Bool = false
    var highlightStartedAt: Date? = nil
    var appearScale: CGFloat = 1
    var appearDelay: TimeInterval = 0
    var onFrame: (CGRect) -> Void = { _ in }

    var body: some View {
        SwiftUI.TimelineView(
            AnimationTimelineSchedule(
                minimumInterval: 1.0 / 60.0,
                paused: highlightStartedAt == nil
            )
        ) { context in
            let elapsed = highlightStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let charge = ChatReactionCharge.progress(elapsed: elapsed)
            let scale: CGFloat = {
                if isPicking { return 1.42 }
                if isHighlighted {
                    return charge > 0
                        ? ChatReactionCharge.scale(progress: charge)
                        : ChatReactionCharge.highlightScale
                }
                return appearScale
            }()
            let rotation = isHighlighted
                ? ChatReactionCharge.rotationDegrees(progress: charge, elapsed: elapsed)
                : 0
            let offsetX = isHighlighted
                ? ChatReactionCharge.offsetX(progress: charge, elapsed: elapsed)
                : 0

            Text(emoji)
                .font(.system(size: max(16, slot * 0.62)))
                .frame(width: slot, height: slot)
                .background {
                    // Selected ring only when idle; highlight pops without a circle (Telegram).
                    if isSelected && !isHighlighted {
                        Circle().fill(Color.accentColor.opacity(0.22))
                    }
                }
                .scaleEffect(scale, anchor: .bottom)
                .rotationEffect(.degrees(rotation))
                .offset(x: offsetX)
                .opacity(isPicking ? 0 : 1)
                .animation(
                    ChatContextMotion.bounce(damping: 88, duration: ChatContextMotion.emojiAppearDuration)
                        .delay(appearDelay),
                    value: appearScale
                )
                .animation(
                    charge > 0 ? nil : ChatContextMotion.bounce(damping: 72, duration: 0.22),
                    value: isHighlighted
                )
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            onFrame(frame)
        }
    }
}

// MARK: - Reaction grid

private struct ReactionGridPanel: View {
    let selectedEmoji: String?
    let pickingEmoji: String?
    let isShown: Bool
    let isMine: Bool
    var onSelect: (String, CGRect) -> Void
    var onCollapse: () -> Void

    private let columnCount = 8
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Reactions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.systemGray5).opacity(0.9)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(DMReactionCatalog.all.enumerated()), id: \.element) { index, emoji in
                        GridEmojiCell(
                            emoji: emoji,
                            isSelected: selectedEmoji == emoji,
                            isPicking: pickingEmoji == emoji,
                            isShown: isShown,
                            appearDelay: appearDelay(index: index),
                            onSelect: { frame in onSelect(emoji, frame) }
                        )
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(12)
    }

    /// Wave from the chevron corner, matching Telegram `itemDelay`.
    private func appearDelay(index: Int) -> TimeInterval {
        let count = DMReactionCatalog.all.count
        let rows = max(1, Int(ceil(Double(count) / Double(columnCount))))
        let row = index / columnCount
        let col = index % columnCount
        let anchorCol = isMine ? columnCount - 1 : 0
        let anchorRow = rows - 1
        let dx = CGFloat(col - anchorCol)
        let dy = CGFloat(row - anchorRow)
        let distance = hypot(dx, dy)
        let maxDistance = max(hypot(CGFloat(columnCount - 1), CGFloat(rows - 1)), 1)
        return 0.01 + Double(distance / maxDistance) * 0.22
    }
}

private struct GridEmojiCell: View {
    let emoji: String
    let isSelected: Bool
    let isPicking: Bool
    let isShown: Bool
    var appearDelay: TimeInterval = 0
    var onSelect: (CGRect) -> Void

    @State private var globalFrame: CGRect = .zero

    var body: some View {
        Button {
            onSelect(globalFrame)
        } label: {
            Text(emoji)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor.opacity(0.22))
                    }
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPicking ? 1.42 : (isShown ? 1 : 0.35))
        .opacity(isPicking ? 0 : (isShown ? 1 : 0))
        .animation(
            isShown
                ? ChatContextMotion.bounce(damping: 88, duration: ChatContextMotion.emojiAppearDuration)
                    .delay(appearDelay)
                : .easeInOut(duration: 0.12),
            value: isShown
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            globalFrame = frame
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - Action menu

private struct MessageActionMenu: View {
    let message: DMMessage
    let isMine: Bool
    let infoLine: String
    let isReadByPeer: Bool
    var currentUserID: String
    var onAction: (ChatMessageAction) -> Void
    var onHeightChange: (CGFloat) -> Void

    private var canEdit: Bool {
        isMine && DMEditRules.canEdit(message, currentUserID: currentUserID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if isMine {
                    Image(systemName: isReadByPeer ? "checkmark.circle.fill" : "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(infoLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.5)

            menuButton("Reply", systemImage: "arrowshape.turn.up.left", action: .reply)

            if ChatMessageActionOverlay.canCopyText(message) {
                menuButton("Copy", systemImage: "doc.on.doc", action: .copy)
            }

            if ChatMessageActionOverlay.canCopyMedia(message) {
                menuButton(
                    message.kind == .gif ? "Copy GIF" : "Copy Photo",
                    systemImage: "photo.on.rectangle",
                    action: .copyMedia
                )
            }

            if canEdit {
                menuButton("Edit", systemImage: "pencil", action: .edit)
            }

            if !message.isPending, message.deletedAt == nil, message.kind != .checklist, message.kind != .poll {
                menuButton("Forward", systemImage: "arrowshape.turn.up.forward", action: .forward)
            }

            if ChatMessageActionOverlay.canRetractVote(message, currentUserID: currentUserID) {
                menuButton("Retract Vote", systemImage: "arrow.uturn.backward", action: .retractVote)
            }

            if ChatMessageActionOverlay.canStopPoll(message, currentUserID: currentUserID) {
                menuButton("Stop Poll", systemImage: "stop.circle", action: .stopPoll)
            }

            if isMine, message.deletedAt == nil {
                menuButton("Delete", systemImage: "trash", action: .delete, destructive: true)
            }

            if message.isFailed {
                menuButton("Retry", systemImage: "arrow.clockwise", action: .retry)
            }
        }
        .directGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(Self.menuShadowOpacity), radius: 14, y: 6)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onHeightChange(geo.size.height) }
                    .onChange(of: geo.size.height) { _, h in onHeightChange(h) }
            }
        )
    }

    private static var menuShadowOpacity: Double {
        if #available(iOS 26, *) { return 0 }
        return 0.18
    }

    private func menuButton(
        _ title: String,
        systemImage: String,
        action: ChatMessageAction,
        destructive: Bool = false
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                Spacer()
                Image(systemName: systemImage)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
            }
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
