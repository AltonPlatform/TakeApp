import MessageUI
import SwiftUI
import UIKit
import os

private let shareSheetLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AltonApp", category: "ShareSheet")

extension View {
    /// Edge-to-edge share panel. System sheets on iOS 26+ keep side margins.
    /// Prefer `preferSheet: true` when already inside a `fullScreenCover` (e.g. image lightbox)
    /// to avoid nested covers that can hide the parent dismiss chrome.
    func postShareSheet(
        isPresented: Binding<Bool>,
        payload: PostSharePayload?,
        directShare: DirectShareDependencies? = nil,
        preferSheet: Bool = false,
        onComplete: @escaping (_ completed: Bool, _ channel: String?) -> Void
    ) -> some View {
        modifier(
            PostShareSheetModifier(
                isPresented: isPresented,
                payload: payload,
                directShare: directShare,
                preferSheet: preferSheet,
                onComplete: onComplete
            )
        )
    }
}

private struct PostShareSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let payload: PostSharePayload?
    var directShare: DirectShareDependencies?
    var preferSheet: Bool = false
    let onComplete: (_ completed: Bool, _ channel: String?) -> Void

    @State private var coverVisible = false

    func body(content: Content) -> some View {
        Group {
            if preferSheet {
                content
                    .sheet(isPresented: $isPresented) {
                        Group {
                            if let payload {
                                PostShareSheet(
                                    payload: payload,
                                    directShare: directShare,
                                    onComplete: { completed, channel in
                                        isPresented = false
                                        onComplete(completed, channel)
                                    },
                                    requestClose: { isPresented = false }
                                )
                            } else {
                                Color.clear
                                    .onAppear { isPresented = false }
                            }
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
            } else {
                content
                    .onAppear {
                        if isPresented { coverVisible = true }
                    }
                    .onChange(of: isPresented) { _, show in
                        if show { coverVisible = true }
                    }
                    .background {
                        Color.clear
                            .fullScreenCover(isPresented: $coverVisible) {
                                EdgeToEdgeShareSheet(
                                    isPresented: $isPresented,
                                    coverVisible: $coverVisible,
                                    payload: payload,
                                    directShare: directShare,
                                    onComplete: onComplete
                                )
                                .presentationBackground(.clear)
                            }
                            // The cover itself must not slide: that motion is the dark rectangle.
                            .transaction { $0.disablesAnimations = true }
                    }
            }
        }
    }
}

private struct EdgeToEdgeShareSheet: View {
    @Binding var isPresented: Bool
    @Binding var coverVisible: Bool
    let payload: PostSharePayload?
    var directShare: DirectShareDependencies?
    let onComplete: (_ completed: Bool, _ channel: String?) -> Void

    @State private var shown = false
    @State private var dragOffset: CGFloat = 0
    @State private var closing = false

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = min(620, proxy.size.height * 0.72)
            let hiddenOffset = panelHeight + proxy.safeAreaInsets.bottom + 32
            ZStack(alignment: .bottom) {
                Color.black
                    .opacity(scrimOpacity(panelHeight: panelHeight))
                    .ignoresSafeArea()
                    .onTapGesture { onComplete(false, nil) }
                    .allowsHitTesting(shown)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(dismissDrag)

                    if let payload {
                        PostShareSheet(
                            payload: payload,
                            directShare: directShare,
                            onComplete: onComplete,
                            requestClose: { isPresented = false },
                            onScrollPull: { translation in
                                setDragOffset(translation)
                            },
                            onScrollPullEnded: { translation, velocity in
                                finishScrollPull(translation: translation, velocity: velocity)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: panelHeight, alignment: .top)
                .background(Color.white)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 22,
                        style: .continuous
                    )
                )
                .offset(y: (shown ? 0 : hiddenOffset) + max(0, dragOffset))
                .ignoresSafeArea(edges: .bottom)
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.92), value: shown)
        }
        .background(Color.clear)
        .onAppear {
            shown = true
        }
        .onChange(of: isPresented) { _, show in
            if !show { beginClose() }
        }
    }

    private func scrimOpacity(panelHeight: CGFloat) -> Double {
        guard shown else { return 0 }
        let progress = min(max(dragOffset, 0) / max(panelHeight, 1), 1)
        return 0.4 * (1 - progress * 0.85)
    }

    private func setDragOffset(_ value: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = max(0, value)
        }
    }

    private func finishScrollPull(translation: CGFloat, velocity: CGFloat) {
        if translation > 110 || velocity > 900 {
            onComplete(false, nil)
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                dragOffset = 0
            }
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragOffset = max(0, value.translation.height)
                }
            }
            .onEnded { value in
                if value.translation.height > 110 {
                    onComplete(false, nil)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func beginClose() {
        guard !closing else { return }
        closing = true
        withAnimation(.easeIn(duration: 0.2)) {
            shown = false
            dragOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            coverVisible = false
            isPresented = false
        }
    }
}

/// TikTok-style custom share sheet: Copy / Messages / Telegram / Instagram Stories / More…
struct PostShareSheet: View {
    let payload: PostSharePayload
    var directShare: DirectShareDependencies? = nil
    let onComplete: (_ completed: Bool, _ channel: String?) -> Void
    var requestClose: () -> Void = {}
    var onScrollPull: (CGFloat) -> Void = { _ in }
    var onScrollPullEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void = { _, _ in }

    @State private var showSystemShare = false
    @State private var showMessagesComposer = false
    @State private var messagesUnavailableAlert = false
    @State private var copiedBanner = false
    /// Stories must run *after* the SwiftUI sheet tears down — concurrent sheet Metal + pasteboard crashes AGX.
    @State private var runStoriesAfterDismiss = false

    private let palette = ComposerPalette.monochrome

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let postID = payload.postID, let directShare {
                        DirectShareInlineSection(postID: postID, deps: directShare) {
                            onComplete(true, "dm")
                            requestClose()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }

                    channelGrid
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)

                    if copiedBanner {
                        Text("Link copied")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primary)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    }
                }
                .background {
                    ShareSheetScrollDismiss(
                        onPull: onScrollPull,
                        onEnd: onScrollPullEnded
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onComplete(false, nil)
                        requestClose()
                    }
                    .foregroundStyle(palette.primary)
                }
            }
        }
        .preferredColorScheme(.light)
        .onDisappear {
            guard runStoriesAfterDismiss else { return }
            runStoriesAfterDismiss = false
            shareSheetLog.info("stories: sheet disappeared — starting share")
            Self.performInstagramStoriesShare(payload: payload, onComplete: onComplete)
        }
        .sheet(isPresented: $showSystemShare) {
            ActivityShareSheet(payload: payload) { completed, channel in
                showSystemShare = false
                onComplete(completed, channel)
                if completed {
                    requestClose()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMessagesComposer) {
            MessageComposeView(
                messageBody: "\(payload.shareMessage)\n\(payload.url.absoluteString)"
            ) { sent in
                showMessagesComposer = false
                if sent {
                    onComplete(true, "messages")
                    requestClose()
                }
            }
        }
        .alert("Messages unavailable", isPresented: $messagesUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can’t send Messages.")
        }
    }

    private var channelGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
        return LazyVGrid(columns: columns, spacing: 20) {
            channelButton(
                title: "Copy link",
                systemImage: "link",
                action: copyLink
            )
            channelButton(
                title: "Messages",
                systemImage: "message.fill",
                action: shareMessages
            )
            if PostShareChannelAvailability.telegram {
                channelButton(
                    title: "Telegram",
                    systemImage: "paperplane.fill",
                    action: shareTelegram
                )
            }
            if PostShareChannelAvailability.instagramStories {
                channelButton(
                    title: "Stories",
                    systemImage: "camera.circle.fill",
                    action: shareInstagramStories
                )
            }
            channelButton(
                title: "More…",
                systemImage: "ellipsis",
                action: { showSystemShare = true }
            )
        }
    }

    private func channelButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .frame(width: 56, height: 56)
                    .background(palette.activeFill, in: Circle())
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func copyLink() {
        UIPasteboard.general.string = payload.url.absoluteString
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) {
            copiedBanner = true
        }
        onComplete(true, "copy")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            requestClose()
        }
    }

    private func shareMessages() {
        guard MFMessageComposeViewController.canSendText() else {
            messagesUnavailableAlert = true
            return
        }
        showMessagesComposer = true
    }

    private func shareTelegram() {
        guard let url = PostShareChannelAvailability.telegramURL(
            shareURL: payload.url,
            text: payload.shareMessage
        ) else {
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                onComplete(true, "telegram")
                requestClose()
            }
        }
    }

    private func shareInstagramStories() {
        shareSheetLog.info("stories: tap — dismiss sheet first")
        runStoriesAfterDismiss = true
        // Close share UI before any bitmap/pasteboard work (avoids RenderBox+AGX race).
        requestClose()
    }

    /// Runs after `PostShareSheet` has disappeared from the hierarchy.
    private static func performInstagramStoriesShare(
        payload: PostSharePayload,
        onComplete: @escaping (_ completed: Bool, _ channel: String?) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            shareSheetLog.info("stories: encoding jpeg on background")
            // Local file first; otherwise HTTPS thumbnail from CDN (TikTok-style
            // full-bleed). EXIF is baked by ImageIO in both paths.
            let poster: CGImage? = await Self.resolvePoster(from: payload.posterURL)
            shareSheetLog.info("stories: poster=\(poster != nil, privacy: .public)")
            let jpeg = PostShareCardRenderer.makeJPEG(payload: payload, poster: poster)
                ?? PostShareCardRenderer.solidBackgroundJPEG()
            shareSheetLog.info("stories: jpeg bytes=\(jpeg?.count ?? 0, privacy: .public)")
            let videoURL = payload.localVideoURL
            await MainActor.run {
                // Let the presenting VC finish dismissal animation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    shareSheetLog.info("stories: calling InstagramStoriesShare.share")
                    let ok = InstagramStoriesShare.share(
                        backgroundImageData: jpeg,
                        stickerImageData: nil,
                        backgroundVideoURL: videoURL,
                        contentURL: payload.url
                    )
                    shareSheetLog.info("stories: share returned ok=\(ok, privacy: .public)")
                    if ok {
                        onComplete(true, "instagram")
                    } else {
                        onComplete(false, nil)
                    }
                }
            }
        }
    }

    private static func resolvePoster(from posterURL: URL?) async -> CGImage? {
        guard let posterURL else { return nil }
        if posterURL.isFileURL {
            return PostShareCardRenderer.loadOrientedPoster(from: posterURL)
        }
        return await PostShareCardRenderer.loadRemotePoster(from: posterURL)
    }
}

/// Pulls the share sheet down when its scroll view is already at the top, same as comments.
private struct ShareSheetScrollDismiss: UIViewRepresentable {
    var onPull: (CGFloat) -> Void
    var onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPull: onPull, onEnd: onEnd)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPull = onPull
        context.coordinator.onEnd = onEnd
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onPull: (CGFloat) -> Void
        var onEnd: (CGFloat, CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var trackingDismiss = false

        init(onPull: @escaping (CGFloat) -> Void, onEnd: @escaping (CGFloat, CGFloat) -> Void) {
            self.onPull = onPull
            self.onEnd = onEnd
        }

        func attachIfNeeded(from view: UIView) {
            guard scrollView == nil else { return }
            var current: UIView? = view
            while let next = current {
                if let scroll = next as? UIScrollView {
                    scroll.alwaysBounceVertical = true
                    scroll.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
                    scrollView = scroll
                    return
                }
                current = next.superview
            }
        }

        func detach() {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            scrollView = nil
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scroll = scrollView, gesture.view === scroll else { return }
            let translation = gesture.translation(in: scroll).y
            let velocity = gesture.velocity(in: scroll).y
            let topOffset = -scroll.adjustedContentInset.top
            let distanceFromTop = scroll.contentOffset.y - topOffset

            switch gesture.state {
            case .began:
                trackingDismiss = false
            case .changed:
                if !trackingDismiss {
                    guard distanceFromTop <= 1, translation > 8, velocity >= 0 else { return }
                    trackingDismiss = true
                }
                scroll.contentOffset.y = topOffset
                onPull(max(0, translation))
            case .ended, .cancelled:
                if trackingDismiss {
                    onEnd(max(0, translation), velocity)
                }
                trackingDismiss = false
            default:
                break
            }
        }
    }
}

enum PostShareChannelAvailability {
    static var telegram: Bool {
        guard let url = URL(string: "tg://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static var instagramStories: Bool {
        InstagramStoriesShare.isAvailable
    }

    static func telegramURL(shareURL: URL, text: String) -> URL? {
        var components = URLComponents(string: "tg://msg_url")
        components?.queryItems = [
            URLQueryItem(name: "url", value: shareURL.absoluteString),
            URLQueryItem(name: "text", value: text),
        ]
        return components?.url
    }
}

// MARK: - Messages composer

private struct MessageComposeView: UIViewControllerRepresentable {
    let messageBody: String
    let onFinish: (_ sent: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = messageBody
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (_ sent: Bool) -> Void

        init(onFinish: @escaping (_ sent: Bool) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish(result == .sent)
        }
    }
}
