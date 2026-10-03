import SwiftUI

struct MainTabView: View {
    let container: DependencyContainer
    let session: AuthSession
    let onLogout: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var takesViewModel: TakesFeedViewModel?
    @State private var shotsViewModel: ShotFeedViewModel?
    @State private var activityViewModel: ActivityViewModel?
    @State private var createPostViewModel: CreatePostViewModel?
    @State private var selectedTab: AppTab = .takes
    @State private var previousTab: AppTab = .takes
    @State private var showCreateOptions = false
    @State private var suppressCreateTabTap = false
    @State private var takeComposer: TakeComposerPresentation?
    @State private var shotCreation: ShotCreationPresentation?
    @State private var deepLinkProfile: DeepLinkProfilePresentation?
    @State private var deepLinkPost: DeepLinkPostPresentation?
    @State private var deepLinkError: String?
    @State private var showSearch = false
    @State private var showAgeGenderModal = false
    @State private var showInterestsModal = false
    /// Prompt once per MainTab session; skip/dismiss must not reopen immediately.
    @State private var didPromptAgeGender = false
    @State private var didPromptInterests = false

    private var createTabIndex: Int { 2 }

    private var liveSession: AuthSession {
        container.sessionStore.session ?? session
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Takes", systemImage: "text.bubble.fill", value: AppTab.takes) {
                NavigationStack {
                    if let takesViewModel {
                        TakesFeedView(
                            viewModel: takesViewModel,
                            session: session,
                            container: container,
                            onCompose: { openTakeComposer() },
                            onSearch: { showSearch = true }
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            Tab("Shots", systemImage: "play.rectangle.fill", value: AppTab.shots) {
                NavigationStack {
                    if let shotsViewModel {
                        ShotFeedView(
                            viewModel: shotsViewModel,
                            session: session,
                            container: container,
                            isFeedVisible: selectedTab == .shots && shotCreation == nil && takeComposer == nil
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    }
                }
            }

            Tab("Create", systemImage: "plus.circle.fill", value: AppTab.create) {
                Color.clear
            }

            Tab("Activity", systemImage: "bell.fill", value: AppTab.activity) {
                NavigationStack {
                    if let activityViewModel {
                        ActivityView(
                            viewModel: activityViewModel,
                            session: session,
                            container: container
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .badge(activityViewModel?.unreadCount ?? 0)

            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView(
                    session: session,
                    container: container,
                    onLogout: onLogout,
                    onOpenDraft: { draftID in
                        openTakeComposer(draftID: draftID)
                    },
                    onOpenShotDraft: { draftID in
                        openShotCamera(draftID: draftID)
                    }
                )
            }
        }
        .tint(.primary)
        .onChange(of: selectedTab) { _, newTab in
            ensureViewModel(for: newTab)
            if newTab == .activity, let activityViewModel, activityViewModel.shouldAutoRefresh {
                Task { await activityViewModel.refresh() }
            }
            guard newTab == .create else {
                previousTab = newTab
                return
            }
            selectedTab = previousTab
            guard !suppressCreateTabTap else {
                suppressCreateTabTap = false
                return
            }
            openTakeComposer()
        }
        .onTabBarItemLongPress(tabIndex: createTabIndex) {
            suppressCreateTabTap = true
            showCreateOptions = true
        }
        .confirmationDialog("Create", isPresented: $showCreateOptions, titleVisibility: .visible) {
            Button("Take") {
                openTakeComposer()
            }
            Button("Shot") {
                openShotCamera()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            ensureViewModel(for: selectedTab)
            syncContentPreferences()
            Task {
                await requestNotificationsIfNeeded()
                await activityViewModel?.refreshUnreadCount()
                await presentOnboardingIfNeeded()
            }
        }
        .sheet(isPresented: $showAgeGenderModal, onDismiss: {
            // Chain to interests only after a successful save (fields filled).
            if !liveSession.user.needsAgeGender {
                Task { await presentOnboardingIfNeeded() }
            }
        }) {
            AgeGenderModal(
                userUseCase: container.userUseCase,
                initialDateOfBirth: liveSession.user.dateOfBirth,
                initialGender: liveSession.user.gender,
                onSaved: { profile in
                    container.sessionStore.updateCurrentUser(from: profile)
                    showAgeGenderModal = false
                },
                onSkip: { showAgeGenderModal = false }
            )
        }
        .sheet(isPresented: $showInterestsModal) {
            InterestsOnboardingModal(
                userUseCase: container.userUseCase,
                onSaved: { interests in
                    if var user = container.sessionStore.session?.user {
                        user.interests = interests
                        // Rebuild via profile-shaped update when possible.
                        Task {
                            if let profile = try? await container.userUseCase.loadCurrentProfile() {
                                container.sessionStore.updateCurrentUser(from: profile)
                            }
                        }
                    }
                    showInterestsModal = false
                },
                onSkip: { showInterestsModal = false }
            )
        }
        .onChange(of: container.sessionStore.session?.user.showSensitiveContent) { _, _ in
            syncContentPreferences()
        }
        .onChange(of: container.sessionStore.session?.user.isAdult) { _, _ in
            syncContentPreferences()
        }
        .sheet(isPresented: $showSearch) {
            SearchView(container: container, session: session)
        }
        .onChange(of: container.sessionStore.pendingDeepLink) { _, link in
            guard let link else { return }
            Task { await handleDeepLink(link) }
        }
        .sheet(item: $deepLinkProfile) { presentation in
            NavigationStack {
                UserProfileView(
                    userID: presentation.userID,
                    session: session,
                    container: container
                )
            }
        }
        .fullScreenCover(item: $deepLinkPost) { presentation in
            NavigationStack {
                TakePostDetailView(
                    item: presentation.item,
                    currentUser: session.user,
                    container: container,
                    session: session,
                    userUseCase: container.userUseCase,
                    engagementController: presentation.engagementController,
                    commentsViewModelFactory: { post in
                        presentation.makeCommentsViewModel(post)
                    },
                    analyticsUseCase: container.analyticsUseCase,
                    postUseCase: container.postUseCase,
                    onDeleted: {
                        deepLinkPost = nil
                    }
                )
            }
        }
        .fullScreenCover(item: $takeComposer, onDismiss: {
            createPostViewModel?.resetComposer()
        }) { presentation in
            CreatePostView(
                viewModel: presentation.viewModel,
                session: session,
                searchUseCase: container.searchUseCase,
                presentation: .fullScreen,
                onPublished: {},
                onShotPublished: {
                    Task { await shotsViewModel?.loadInitial() }
                }
            )
        }
        .fullScreenCover(item: $shotCreation, onDismiss: {
            createPostViewModel?.resetComposer()
        }) { presentation in
            CameraView(
                viewModel: presentation.cameraViewModel,
                session: session,
                onPublishStarted: {
                    shotCreation = nil
                }
            )
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
        .overlay(alignment: .top) {
            if let banner = container.appState.uploadBanner {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        if banner.progress == nil, !banner.canResume {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(banner.message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if banner.canResume {
                            Button("Resume") { resumePausedShotUploads(automatic: false) }
                                .font(.subheadline.weight(.semibold))
                            Button("Cancel") { cancelShotUpload() }
                                .font(.subheadline.weight(.semibold))
                        } else if banner.progress != nil {
                            Button("Cancel") { cancelShotUpload() }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if let progress = banner.progress {
                        ProgressView(value: min(max(progress, 0), 1))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture {
                    if banner.progress == nil, !banner.canResume {
                        container.appState.clearUploadBanner()
                    }
                }
            } else if let toast = container.appState.toastMessage {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { container.appState.clearToast() }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: container.appState.uploadBanner)
        .animation(.easeInOut(duration: 0.25), value: container.appState.toastMessage)
        .task { await recoverShotUploads() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await recoverShotUploads() }
            } else {
                container.postUseCase.stopAcceptedShotWatch()
            }
        }
        .onChange(of: container.appState.takePublishGeneration) { _, _ in
            Task { await takesViewModel?.refresh() }
        }
        .onChange(of: container.appState.shotPublishGeneration) { _, _ in
            Task { await shotsViewModel?.loadInitial() }
        }
        .alert(
            "Couldn't open post",
            isPresented: Binding(
                get: { deepLinkError != nil },
                set: { if !$0 { deepLinkError = nil } }
            )
        ) {
            Button("OK") { deepLinkError = nil }
        } message: {
            Text(deepLinkError ?? "")
        }
    }

    private func recoverShotUploads() async {
        container.postUseCase.watchAcceptedShotUploads(resendIncomplete: true)
        resumePausedShotUploads()
    }

    private func resumePausedShotUploads(automatic: Bool = true) {
        guard !container.appState.hasActiveShotUpload else { return }
        let urls = container.postUseCase.pendingShotFileURLs().filter { url in
            FileManager.default.fileExists(atPath: url.path)
        }
        let pending = urls.filter { url in
            !automatic
                || (container.appState.allowsAutomaticResume(url)
                    && !container.postUseCase.shotRequiresExplicitResume(fileURL: url))
        }
        if pending.isEmpty {
            if automatic, !urls.isEmpty {
                container.appState.showUploadBanner("Upload paused.", canResume: true)
            }
            return
        }

        pending.forEach { container.appState.beginShotUpload($0) }
        container.appState.showUploadBanner("Uploading shot…", progress: 0)
        let useCase = container.postUseCase
        let state = container.appState
        let explicit = !automatic
        let task = Task { @MainActor in
            var keptUnstarted = false
            for url in pending {
                if Task.isCancelled {
                    ShotResumeBatch.keepUnstartedFile(url: url, postUseCase: useCase, appState: state)
                    keptUnstarted = true
                    continue
                }
                if explicit {
                    useCase.allowAutomaticShotResume(fileURL: url)
                }
                await CameraViewModel.performBackgroundPublish(
                    url: url,
                    caption: nil,
                    lat: nil,
                    lon: nil,
                    geoSource: nil,
                    aiGeneratedLabel: nil,
                    postUseCase: useCase,
                    appState: state
                )
            }
            let waitingForResume = useCase.pendingShotFileURLs().contains { url in
                FileManager.default.fileExists(atPath: url.path)
                    && useCase.shotRequiresExplicitResume(fileURL: url)
            }
            if (keptUnstarted || waitingForResume), !state.hasActiveShotUpload {
                state.showUploadBanner("Upload paused.", canResume: true)
            }
        }
        pending.forEach { container.appState.trackShotUpload($0, task) }
    }

    private func cancelShotUpload() {
        let uploadStillRunning = container.appState.hasActiveShotUpload
        container.appState.cancelTrackedShotUpload()
        if !uploadStillRunning {
            for url in container.postUseCase.pendingShotFileURLs() {
                container.postUseCase.discardPendingShotUpload(fileURL: url)
            }
        }
        container.appState.clearUploadBanner()
    }

    private func ensureViewModel(for tab: AppTab) {
        switch tab {
        case .takes:
            if takesViewModel == nil {
                takesViewModel = container.makeTakesFeedViewModel()
                takesViewModel?.showSensitiveContent = liveSession.user.showSensitiveContent
                takesViewModel?.viewerIsAdult = liveSession.user.isAdult
            }
        case .shots:
            if shotsViewModel == nil {
                shotsViewModel = container.makeShotFeedViewModel()
                shotsViewModel?.showSensitiveContent = liveSession.user.showSensitiveContent
                shotsViewModel?.viewerIsAdult = liveSession.user.isAdult
            }
        case .activity:
            if activityViewModel == nil {
                activityViewModel = container.makeActivityViewModel()
            }
        case .create, .profile:
            break
        }
    }

    private func syncContentPreferences() {
        let show = liveSession.user.showSensitiveContent
        let adult = liveSession.user.isAdult
        AgeGateConfirmationStore.shared.setViewerIsAdult(adult)
        takesViewModel?.showSensitiveContent = show
        takesViewModel?.viewerIsAdult = adult
        if let shotsViewModel {
            shotsViewModel.applyContentPreferences(showSensitive: show, viewerIsAdult: adult)
        }
    }

    private func presentOnboardingIfNeeded() async {
        // Refresh profile so birth/gender/interests reflect server state.
        if let profile = try? await container.userUseCase.loadCurrentProfile() {
            container.sessionStore.updateCurrentUser(from: profile)
        }
        let user = liveSession.user
        if user.needsAgeGender {
            guard !didPromptAgeGender else { return }
            didPromptAgeGender = true
            showAgeGenderModal = true
            return
        }
        if user.needsInterests {
            guard !didPromptInterests else { return }
            didPromptInterests = true
            showInterestsModal = true
        }
    }

    private func requestNotificationsIfNeeded() async {
        let key = "hasRequestedNotifications"
        guard !UserDefaults.standard.bool(forKey: key) else {
            await DevicePermissions.registerForRemoteNotificationsIfAuthorized()
            return
        }
        let granted = await DevicePermissions.requestNotificationAccess()
        UserDefaults.standard.set(true, forKey: key)
        if granted {
            await DevicePermissions.registerForRemoteNotificationsIfAuthorized()
        }
    }

    private func openTakeComposer(draftID: UUID? = nil) {
        let viewModel = createPostViewModel ?? container.makeCreatePostViewModel()
        createPostViewModel = viewModel
        if let draftID {
            viewModel.beginDraft(id: draftID)
        } else {
            viewModel.resetComposer()
        }
        takeComposer = TakeComposerPresentation(viewModel: viewModel)
    }

    private func openShotCamera(draftID: UUID? = nil) {
        let postVM = createPostViewModel ?? container.makeCreatePostViewModel()
        createPostViewModel = postVM
        let camera = postVM.makeCameraViewModel()
        if let draftID {
            Task {
                await camera.beginShotDraft(id: draftID)
            }
        }
        ShotFeedPlaybackCache.shared.clearAll()
        shotCreation = ShotCreationPresentation(cameraViewModel: camera)
    }

    private func handleDeepLink(_ link: DeepLink) async {
        container.sessionStore.clearPendingDeepLink()
        switch link {
        case .user(let userID):
            deepLinkProfile = DeepLinkProfilePresentation(userID: userID)
        case .post(let postID):
            ensureViewModel(for: .takes)
            selectedTab = .takes
            guard let takesViewModel else {
                deepLinkError = "This post couldn't be opened. Please try again."
                return
            }
            do {
                let post = try await container.postUseCase.fetchPost(id: postID)
                if let blocked = ViewerContentFilterPolicy.blockedOpenMessage(
                    for: post,
                    viewerIsAdult: liveSession.user.isAdult,
                    showSensitiveContent: liveSession.user.showSensitiveContent
                ) {
                    deepLinkError = blocked
                    return
                }
                let item = FeedItem(
                    post: post,
                    finalScore: 0,
                    userScore: 0,
                    creatorScore: 0,
                    brandScore: 0
                )
                deepLinkPost = DeepLinkPostPresentation(
                    item: item,
                    engagementController: takesViewModel.engagementController,
                    makeCommentsViewModel: { [takesViewModel] post in
                        takesViewModel.makeCommentsViewModel(for: post, userID: session.user.id)
                    }
                )
            } catch {
                deepLinkError = "This post couldn't be opened. It may have been deleted."
            }
        }
    }
}

private enum AppTab: Hashable {
    case takes
    case shots
    case create
    case activity
    case profile
}

private struct TakeComposerPresentation: Identifiable {
    let id = UUID()
    let viewModel: CreatePostViewModel
}

private struct ShotCreationPresentation: Identifiable {
    let id = UUID()
    let cameraViewModel: CameraViewModel
}

private struct DeepLinkProfilePresentation: Identifiable {
    var id: String { userID }
    let userID: String
}

private struct DeepLinkPostPresentation: Identifiable {
    var id: String { item.post.id }
    let item: FeedItem
    let engagementController: PostEngagementController
    let makeCommentsViewModel: (Post) -> CommentsViewModel
}
