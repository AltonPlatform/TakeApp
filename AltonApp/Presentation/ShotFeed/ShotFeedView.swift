import SwiftUI
import NukeUI

struct ShotFeedView: View {
    @Bindable var viewModel: ShotFeedViewModel
    let session: AuthSession
    let container: DependencyContainer
    var isFeedVisible: Bool = true

    @State private var profileUserID: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    LoadingView(message: "Loading shots...")
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    ErrorView(message: errorMessage) {
                        Task { await viewModel.loadInitial() }
                    }
                } else if viewModel.displayRows.isEmpty {
                    ContentUnavailableView("No shots yet", systemImage: "play.rectangle")
                } else {
                    ShotFeedPagerView(
                        rows: viewModel.displayRows,
                        currentIndex: Binding(
                            get: { viewModel.currentIndex },
                            set: { viewModel.setCurrentIndex($0) }
                        ),
                        currentUser: session.user,
                        session: session,
                        container: container,
                        engagementController: viewModel.engagementController,
                        commentsViewModelFactory: { viewModel.makeCommentsViewModel(for: $0, userID: session.user.id) },
                        viewSource: .feed,
                        edgeToEdge: false,
                        isFeedVisible: isFeedVisible,
                        onIndexChanged: { viewModel.setCurrentIndex($0) },
                        onPullToRefresh: {
                            await viewModel.refresh()
                        },
                        onOverscrollPastEnd: {
                            await viewModel.handleOverscrollPastEnd()
                        },
                        onOpenProfile: { userID in
                            profileUserID = userID
                        }
                    )
                }
            }
        }
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .navigationDestination(item: $profileUserID) { userID in
            UserProfileView(userID: userID, session: session, container: container, initialTab: .shots)
        }
        .task {
            async let adsReady: Void = CASManager.shared.waitUntilReady()
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            }
            await adsReady
            NativeAdPool.shared.warmUp(placementID: NativeAdPool.feedPlacementID)
        }
    }
}

struct ProfileShotsFeedView: View {
    let posts: [Post]
    let initialIndex: Int
    let session: AuthSession
    let container: DependencyContainer
    /// When true, sensitive/age-gated posts stay visible (owner viewing own profile).
    var isOwnProfile: Bool = false

    @State private var currentIndex: Int
    @State private var engagementController: PostEngagementController
    @State private var profileUserID: String?

    init(
        posts: [Post],
        initialIndex: Int,
        session: AuthSession,
        container: DependencyContainer,
        isOwnProfile: Bool = false
    ) {
        self.session = session
        self.container = container
        self.isOwnProfile = isOwnProfile
        let filtered = ViewerContentFilterPolicy.filterPosts(
            posts,
            viewerIsAdult: session.user.isAdult,
            showSensitiveContent: session.user.showSensitiveContent,
            isOwnProfile: isOwnProfile
        )
        self.posts = filtered
        let safeIndex: Int
        if posts.indices.contains(initialIndex) {
            let targetID = posts[initialIndex].id
            safeIndex = filtered.firstIndex(where: { $0.id == targetID }) ?? 0
        } else {
            safeIndex = min(initialIndex, max(0, filtered.count - 1))
        }
        self.initialIndex = safeIndex
        _currentIndex = State(initialValue: safeIndex)
        _engagementController = State(initialValue: container.makeEngagementController())
    }

    private var items: [FeedItem] {
        posts.map {
            FeedItem(post: $0, finalScore: 0, userScore: 0, creatorScore: 0, brandScore: 0)
        }
    }

    var body: some View {
        ShotFeedPagerView(
            rows: items.map { .shot($0) },
            currentIndex: $currentIndex,
            currentUser: session.user,
            session: session,
            container: container,
            engagementController: engagementController,
            commentsViewModelFactory: { post in
                container.makeCommentsViewModel(postID: post.id, currentUserID: session.user.id)
            },
            viewSource: .profile,
            edgeToEdge: false,
            onIndexChanged: { currentIndex = $0 },
            onOpenProfile: { userID in profileUserID = userID }
        )
        .navigationDestination(item: $profileUserID) { userID in
            UserProfileView(userID: userID, session: session, container: container, initialTab: .shots)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct ShotFeedPagerView: View {
    let rows: [ShotFeedDisplayRow]
    @Binding var currentIndex: Int
    let currentUser: User
    let session: AuthSession
    let container: DependencyContainer
    @Bindable var engagementController: PostEngagementController
    let commentsViewModelFactory: (Post) -> CommentsViewModel
    let viewSource: ViewSource
    var edgeToEdge: Bool = false
    var isFeedVisible: Bool = true
    var onIndexChanged: (Int) -> Void = { _ in }
    var onPullToRefresh: (() async -> Void)?
    var onOverscrollPastEnd: (() async -> Void)?
    var onOpenProfile: (String) -> Void = { _ in }

    @State private var commentsPresentation: ShotCommentsPresentation?

    var body: some View {
        ZStack {
            ShotFeedVerticalPager(
                rows: rows,
                currentIndex: $currentIndex,
                currentUser: currentUser,
                session: session,
                container: container,
                engagementController: engagementController,
                commentsViewModelFactory: commentsViewModelFactory,
                viewSource: viewSource,
                edgeToEdge: edgeToEdge,
                isFeedVisible: isFeedVisible,
                commentsOpenPostID: commentsPresentation?.postID,
                onOpenComments: openComments,
                onIndexChanged: onIndexChanged,
                onPullToRefresh: {
                    if let onPullToRefresh {
                        await onPullToRefresh()
                    }
                },
                onOverscrollPastEnd: {
                    if let onOverscrollPastEnd {
                        await onOverscrollPastEnd()
                    }
                },
                onOpenProfile: onOpenProfile
            )
            .modifier(ShotFeedSafeAreaModifier(edgeToEdge: edgeToEdge))

            if let commentsPresentation {
                ShotCommentsSheet(
                    viewModel: commentsPresentation.viewModel,
                    commentCount: commentsPresentation.commentCount,
                    currentUser: currentUser,
                    searchUseCase: container.searchUseCase,
                    session: session,
                    container: container,
                    onDismiss: { self.commentsPresentation = nil },
                    onCommentAdded: { _ in
                        self.commentsPresentation?.commentCount += 1
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
        }
    }

    private func openComments(for post: Post) {
        guard commentsPresentation == nil else { return }
        Task { @MainActor in
            guard commentsPresentation == nil else { return }
            commentsPresentation = ShotCommentsPresentation(
                postID: post.id,
                commentCount: post.commentCount,
                viewModel: commentsViewModelFactory(post)
            )
        }
    }
}

struct ShotCommentsPresentation {
    let postID: String
    var commentCount: Int
    let viewModel: CommentsViewModel
}

private struct ShotFeedSafeAreaModifier: ViewModifier {
    let edgeToEdge: Bool

    func body(content: Content) -> some View {
        if edgeToEdge {
            content
                .ignoresSafeArea()
                .ignoresSafeArea(.keyboard, edges: .all)
        } else {
            content
                .ignoresSafeArea(edges: .top)
                .ignoresSafeArea(.keyboard, edges: .all)
        }
    }
}

struct ShotFeedPageView: View {
    let item: FeedItem
    let currentUser: User
    let session: AuthSession
    let container: DependencyContainer
    let isActive: Bool
    var isPreloading: Bool = false
    @Bindable var engagementController: PostEngagementController
    let commentsViewModelFactory: (Post) -> CommentsViewModel
    let viewSource: ViewSource
    var isCommentsOpen: Bool = false
    var onOpenComments: (Post) -> Void = { _ in }
    var onOpenProfile: (String) -> Void = { _ in }

    @State private var post: Post
    @State private var showShareSheet = false
    @State private var viewStartTime = Date()
    @State private var hasRecordedInitialView = false
    @State private var playbackProgress: Double = 0
    @State private var isScrubbing = false
    @State private var seekToProgress: Double?
    @State private var playbackCurrentTime: TimeInterval = 0
    @State private var playbackDuration: TimeInterval = 0
    @State private var isPausedByUser = false
    @State private var playbackSpeedIndex = ShotPlaybackSpeed.defaultIndex
    @State private var lockedSpeedIndex: Int?
    @State private var isAdjustingSpeed = false
    @State private var activeSpeedZone: ShotSpeedZone?
    @State private var showOptionsMenu = false
    @State private var showReportSheet = false
    @State private var isCleanMode = false
    @State private var likeBursts: [ShotLikeBurstItem] = []
    @State private var sensitiveRevealed = false
    @AppStorage("shotSubtitlesEnabled") private var subtitlesEnabled = false
    @State private var subtitleCues: [WebVTTCue] = []

    private var scrubbingTime: TimeInterval {
        playbackDuration > 0 ? playbackDuration * playbackProgress : playbackCurrentTime
    }

    private var playbackRate: Float {
        ShotPlaybackSpeed.rates[ShotPlaybackSpeed.clamped(playbackSpeedIndex)]
    }

    private var overlaysVisible: Bool {
        !isScrubbing && !isCleanMode && !isAdjustingSpeed && !isCommentsOpen
    }

    private var isAgeLocked: Bool {
        ShotMediaLockPolicy.isAgeLocked(ageGated: post.ageGated)
    }

    private var isSensitiveLocked: Bool {
        ShotMediaLockPolicy.isSensitiveLocked(
            sensitiveBlur: post.sensitiveBlur,
            sensitiveRevealed: sensitiveRevealed
        )
    }

    private var isMediaLocked: Bool {
        ShotMediaLockPolicy.isMediaLocked(ageLocked: isAgeLocked, sensitiveLocked: isSensitiveLocked)
    }

    private var activeSubtitleText: String? {
        guard subtitlesEnabled, !subtitleCues.isEmpty else { return nil }
        return WebVTTParser.activeCue(at: playbackCurrentTime, in: subtitleCues)
    }

    init(
        item: FeedItem,
        currentUser: User,
        session: AuthSession,
        container: DependencyContainer,
        isActive: Bool,
        isPreloading: Bool = false,
        engagementController: PostEngagementController,
        commentsViewModelFactory: @escaping (Post) -> CommentsViewModel,
        viewSource: ViewSource = .feed,
        isCommentsOpen: Bool = false,
        onOpenComments: @escaping (Post) -> Void = { _ in },
        onOpenProfile: @escaping (String) -> Void = { _ in }
    ) {
        self.item = item
        self.currentUser = currentUser
        self.session = session
        self.container = container
        self.isActive = isActive
        self.isPreloading = isPreloading
        self.engagementController = engagementController
        self.commentsViewModelFactory = commentsViewModelFactory
        self.viewSource = viewSource
        self.isCommentsOpen = isCommentsOpen
        self.onOpenComments = onOpenComments
        self.onOpenProfile = onOpenProfile
        _post = State(initialValue: item.post)
        _sensitiveRevealed = State(initialValue: false)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SensitiveMediaOverlay(
                isSensitive: isSensitiveLocked,
                isAgeRestricted: isAgeLocked,
                managesRevealInternally: false,
                moderationReason: post.moderationReason,
                onReveal: {
                    // Age lock for non-adults cannot be cleared by tap.
                    if isSensitiveLocked {
                        sensitiveRevealed = true
                    }
                }
            ) {
                Group {
                    let loadClear = ShotMediaLockPolicy.allowsPlayer(
                        isMediaLocked: isMediaLocked,
                        isActive: isActive,
                        isPreloading: isPreloading
                    )
                    let loadBlurred = ShotMediaLockPolicy.shouldLoadForBlur(
                        isSensitiveLocked: isSensitiveLocked,
                        isAgeLocked: isAgeLocked
                    )
                    if loadClear || loadBlurred {
                        ShotPlayerView(
                            url: post.playbackURL,
                            isActive: isActive,
                            preloadOnly: isPreloading,
                            isMuted: loadBlurred,
                            progress: $playbackProgress,
                            isScrubbing: $isScrubbing,
                            seekToProgress: $seekToProgress,
                            currentTime: $playbackCurrentTime,
                            duration: $playbackDuration,
                            isPausedByUser: $isPausedByUser,
                            playbackRate: .constant(playbackRate),
                            subtitlesURL: loadBlurred ? nil : post.subtitlesURL,
                            subtitlesEnabled: loadBlurred ? false : subtitlesEnabled,
                            onSubtitleCuesLoaded: { cues in
                                if !loadBlurred {
                                    subtitleCues = cues
                                }
                            }
                        )
                        .background(Color.black)
                    } else {
                        videoPlaceholder
                    }
                }
            }

            if isActive {
                activeOverlays
            }

            if let activeSubtitleText, overlaysVisible, !isMediaLocked {
                Text(activeSubtitleText)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 96)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isScrubbing)
        .animation(.easeInOut(duration: 0.2), value: isPausedByUser)
        .animation(.easeInOut(duration: 0.2), value: isAdjustingSpeed)
        .animation(.easeInOut(duration: 0.2), value: isCleanMode)
        .animation(.easeInOut(duration: 0.2), value: playbackSpeedIndex)
        .animation(.easeInOut(duration: 0.2), value: playbackSpeedIndex)
        .onAppear {
            viewStartTime = Date()
            guard isActive, !hasRecordedInitialView else { return }
            hasRecordedInitialView = true
            Task { await engagementController.recordView(postID: post.id, source: viewSource) }
        }
        .onChange(of: isActive) { _, active in
            if active {
                viewStartTime = Date()
                playbackProgress = 0
                playbackCurrentTime = 0
                isPausedByUser = false
                playbackSpeedIndex = lockedSpeedIndex ?? ShotPlaybackSpeed.defaultIndex
                hasRecordedInitialView = false
                Task { await engagementController.recordView(postID: post.id, source: viewSource) }
                hasRecordedInitialView = true
            } else {
                sendWatchTime()
            }
        }
        .onChange(of: item.post) { _, newPost in
            post = newPost
            subtitleCues = []
        }
        .onChange(of: subtitlesEnabled) { _, enabled in
            if !enabled {
                subtitleCues = []
            }
        }
        .onDisappear { sendWatchTime() }
        .sheet(isPresented: $showShareSheet) {
            if let url = engagementController.shareURL {
                ActivityShareSheet(items: [url]) { completed in
                    showShareSheet = false
                    if completed {
                        Task {
                            post = await engagementController.completeShare(post: post)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showOptionsMenu) {
            ShotOptionsSheet(
                playbackSpeedIndex: $playbackSpeedIndex,
                lockedSpeedIndex: $lockedSpeedIndex,
                isCleanMode: $isCleanMode,
                subtitlesEnabled: $subtitlesEnabled,
                subtitlesAvailable: post.subtitlesURL != nil,
                canReport: post.canReport && post.creatorID != currentUser.id,
                onReport: { showReportSheet = true }
            )
        }
        .sheet(isPresented: $showReportSheet) {
            ReportPostSheet(postID: post.id, userUseCase: container.userUseCase)
        }
    }

    private func togglePause() {
        guard !isScrubbing, !isAdjustingSpeed else { return }
        isPausedByUser.toggle()
        if isPausedByUser {
            ShotHaptics.pause()
        } else {
            ShotHaptics.play()
        }
    }

    private func handleDoubleTap(at location: CGPoint) {
        guard !isScrubbing, !isAdjustingSpeed else { return }
        let burst = ShotLikeBurstItem(location: location)
        likeBursts.append(burst)
        ShotHaptics.like()
        if !post.isLiked {
            Task { post = await engagementController.toggleLike(for: post) }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            likeBursts.removeAll { $0.id == burst.id }
        }
    }

    private func cancelSpeedAdjustment() {
        activeSpeedZone = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isAdjustingSpeed = false
        }
    }

    private func beginZoneSpeed(_ zone: ShotSpeedZone) {
        guard !isScrubbing else { return }
        activeSpeedZone = zone
        withAnimation(.easeInOut(duration: 0.2)) {
            isAdjustingSpeed = true
        }
        switch zone {
        case .left:
            playbackSpeedIndex = ShotPlaybackSpeed.leftZoneStartIndex
        case .right:
            playbackSpeedIndex = ShotPlaybackSpeed.rightZoneStartIndex
        case .center:
            break
        }
        ShotHaptics.longPressBegan()
    }

    private func updateZoneSpeed(translationX: CGFloat, zone: ShotSpeedZone) {
        guard isAdjustingSpeed, activeSpeedZone == zone else { return }

        let stepSize = ShotPlaybackSpeed.zoneStepPoints
        let newIndex: Int
        switch zone {
        case .left:
            let steps = Int(max(0, translationX) / stepSize)
            newIndex = min(ShotPlaybackSpeed.leftZoneStartIndex + steps, ShotPlaybackSpeed.zoneEndIndex)
        case .right:
            let steps = Int(max(0, -translationX) / stepSize)
            newIndex = max(ShotPlaybackSpeed.rightZoneStartIndex - steps, ShotPlaybackSpeed.zoneEndIndex)
        case .center:
            return
        }

        guard newIndex != playbackSpeedIndex else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            playbackSpeedIndex = newIndex
        }
        ShotHaptics.speedStep()
    }

    private func endZoneSpeed() {
        activeSpeedZone = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isAdjustingSpeed = false
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            playbackSpeedIndex = lockedSpeedIndex ?? ShotPlaybackSpeed.defaultIndex
        }
        ShotHaptics.speedReverted()
    }

    private func openCenterMenu() {
        guard !isScrubbing, !isAdjustingSpeed else { return }
        ShotHaptics.menuOpened()
        showOptionsMenu = true
    }

    @ViewBuilder
    private func profileLink<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if post.creatorID != session.user.id {
            Button {
                onOpenProfile(post.creatorID)
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func sendWatchTime() {
        let elapsed = Int(Date().timeIntervalSince(viewStartTime) * 1000)
        guard elapsed > 500 else { return }
        Task {
            await engagementController.recordView(
                postID: post.id,
                source: viewSource,
                watchTimeMs: elapsed
            )
        }
    }

    @ViewBuilder
    private var activeOverlays: some View {
        ShotGestureOverlay(
            onSingleTap: togglePause,
            onDoubleTap: handleDoubleTap,
            onCenterLongPressEnded: openCenterMenu
        )
        .allowsHitTesting(!isCommentsOpen)

        GeometryReader { geometry in
            let zoneWidth = geometry.size.width * 0.25
            let buttonClearance: CGFloat = 300

            HStack(spacing: 0) {
                ShotSpeedZoneOverlay(
                    zone: .left,
                    onZoneSpeedBegan: beginZoneSpeed,
                    onZoneSpeedChanged: updateZoneSpeed,
                    onZoneSpeedEnded: endZoneSpeed,
                    onZoneSpeedCancelled: cancelSpeedAdjustment
                )
                .frame(width: zoneWidth)

                Spacer()
                    .allowsHitTesting(false)

                ShotSpeedZoneOverlay(
                    zone: .right,
                    onZoneSpeedBegan: beginZoneSpeed,
                    onZoneSpeedChanged: updateZoneSpeed,
                    onZoneSpeedEnded: endZoneSpeed,
                    onZoneSpeedCancelled: cancelSpeedAdjustment
                )
                .frame(width: zoneWidth)
                .padding(.bottom, buttonClearance)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(!isCommentsOpen && !isScrubbing)

        ShotLikeBurstOverlay(bursts: likeBursts)

        if isPausedByUser && !isScrubbing && !isAdjustingSpeed {
            Image(systemName: "play.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }

        if isAdjustingSpeed {
            Text(ShotPlaybackSpeed.label(for: playbackSpeedIndex))
                .font(.system(size: 48, weight: .bold))
                .contentTransition(.numericText())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        }

        LinearGradient(
            colors: [.clear, .black.opacity(0.75)],
            startPoint: .center,
            endPoint: .bottom
        )
        .opacity(overlaysVisible ? 1 : 0)
        .allowsHitTesting(false)

        if isScrubbing {
            Text("\(formatVideoTime(scrubbingTime)) / \(formatVideoTime(playbackDuration))")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .allowsHitTesting(false)
        }

        VStack(spacing: 0) {
            Spacer()
                .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    profileLink {
                        HStack(spacing: 10) {
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
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))

                            VStack(alignment: .leading, spacing: 2) {
                                UserHandleLabel(
                                    displayName: post.resolvedCreatorDisplayName(currentUser: currentUser),
                                    atUsername: post.resolvedAtUsername(currentUser: currentUser),
                                    font: .headline
                                )
                                .foregroundStyle(.white)
                                if let createdAt = post.createdAt {
                                    Text(PostRelativeTimestamp.string(from: createdAt))
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    if let content = post.content, !content.isEmpty {
                        Text(content)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(3)
                    }
                }
                .padding(.leading, 16)
                .padding(.bottom, 12)
                .allowsHitTesting(overlaysVisible)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                VStack(spacing: 20) {
                    PostContextMenuButton(
                        post: post,
                        iconColor: .white,
                        shotFeedStyle: true,
                        onBookmark: { Task { post = await engagementController.toggleBookmark(for: post) } },
                        onRepost: { Task { post = await engagementController.toggleRepost(for: post) } },
                        onReport: (post.canReport && post.creatorID != currentUser.id)
                            ? { showReportSheet = true }
                            : nil,
                        onCopy: {}
                    )

                    PostActionBar(
                        post: post,
                        layout: .vertical,
                        shotFeedStyle: true,
                        onLike: { Task { post = await engagementController.toggleLike(for: post) } },
                        onComment: { onOpenComments(post) },
                        onShare: {
                            Task {
                                if await engagementController.prepareShare(postID: post.id) {
                                    showShareSheet = true
                                }
                            }
                        }
                    )
                }
                .padding(.trailing, 10)
                .padding(.bottom, 28)
                .allowsHitTesting(overlaysVisible)
            }
            .opacity(overlaysVisible ? 1 : 0)

            ShotProgressBar(
                progress: $playbackProgress,
                isScrubbing: $isScrubbing
            ) { fraction in
                seekToProgress = fraction
            }
            .padding(.bottom, isScrubbing ? 4 : 8)
            .opacity((isCleanMode || isAdjustingSpeed) ? 0 : 1)
            .allowsHitTesting(!isCleanMode && !isAdjustingSpeed)
        }
    }

    @ViewBuilder
    private var videoPlaceholder: some View {
        ZStack {
            Color.black
            if let thumbnailURL = post.thumbnailURL {
                LazyImage(url: thumbnailURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    } else {
                        Color.black
                    }
                }
                .processors([.resize(width: 720)])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
