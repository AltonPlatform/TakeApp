import Foundation

@MainActor
final class DependencyContainer {
    let apiClient: APIClient
    let ssoClient: SSOClient
    let tokenStore: KeychainTokenStore

    let appleProvider: AppleAuthProvider
    let googleProvider: GoogleAuthProvider
    let passkeyProvider: PasskeyAuthProvider
    let magicLinkProvider: MagicLinkAuthProvider

    let authRepository: AuthRepository
    let feedRepository: FeedRepository
    let postRepository: PostRepository
    let engagementRepository: EngagementRepository
    let commentRepository: CommentRepository
    let stickerRepository: StickerRepository
    let analyticsRepository: AnalyticsRepository
    let activityRepository: PostActivityRepository
    let userRepository: UserRepository
    let bookmarksRepository: BookmarksRepository
    let directRepository: DirectRepository
    let realtimeClient: RealtimeClient
    let presenceStore: PresenceStore

    let authUseCase: AuthUseCase
    let feedUseCase: FeedUseCase
    let postUseCase: PostUseCase
    let engagementUseCase: EngagementUseCase
    let commentsUseCase: CommentsUseCase
    let stickersUseCase: StickersUseCase
    let analyticsUseCase: PostAnalyticsUseCase
    let notificationUseCase: NotificationUseCase
    let activityUseCase: PostActivityUseCase
    let userUseCase: UserUseCase
    let bookmarksUseCase: BookmarksUseCase
    let searchUseCase: SearchUseCase
    let directUseCase: DirectUseCase
    let earningsRepository: EarningsRepository
    let adRepository: AdRepository
    let sessionStore: AppSessionStore
    let appState: AppState
    let draftStore: DraftStore
    let messageCacheStore: MessageCacheStore

    init() {
        let tokenStore = KeychainTokenStore()
        let apiClient = APIClient(tokenStore: tokenStore)
        let ssoClient = SSOClient()

        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.ssoClient = ssoClient

        self.appleProvider = AppleAuthProvider(ssoClient: ssoClient, tokenStore: tokenStore)
        self.googleProvider = GoogleAuthProvider(ssoClient: ssoClient, tokenStore: tokenStore)
        self.passkeyProvider = PasskeyAuthProvider(ssoClient: ssoClient, tokenStore: tokenStore)
        self.magicLinkProvider = MagicLinkAuthProvider(ssoClient: ssoClient, tokenStore: tokenStore)

        self.authRepository = AuthRepository(
            apiClient: apiClient,
            appleProvider: appleProvider,
            googleProvider: googleProvider,
            passkeyProvider: passkeyProvider,
            magicLinkProvider: magicLinkProvider
        )
        self.feedRepository = FeedRepository(apiClient: apiClient)
        self.postRepository = PostRepository(apiClient: apiClient)
        self.engagementRepository = EngagementRepository(apiClient: apiClient)
        self.commentRepository = CommentRepository(apiClient: apiClient)
        self.stickerRepository = StickerRepository(apiClient: apiClient)
        self.analyticsRepository = AnalyticsRepository(apiClient: apiClient)
        self.activityRepository = PostActivityRepository(apiClient: apiClient)
        let notificationRepository = NotificationRepository(apiClient: apiClient)
        self.userRepository = UserRepository(apiClient: apiClient)
        self.bookmarksRepository = BookmarksRepository(apiClient: apiClient)
        self.earningsRepository = EarningsRepository(apiClient: apiClient)
        self.adRepository = AdRepository(apiClient: apiClient)
        let messageCacheStore = MessageCacheStore.makePersistent()
        self.messageCacheStore = messageCacheStore
        self.directRepository = DirectRepository(apiClient: apiClient, cache: messageCacheStore)
        self.realtimeClient = RealtimeClient(tokenStore: tokenStore)
        self.presenceStore = PresenceStore(apiClient: apiClient)

        self.userUseCase = UserUseCase(repository: userRepository)
        self.bookmarksUseCase = BookmarksUseCase(repository: bookmarksRepository)
        self.searchUseCase = SearchUseCase(repository: userRepository)
        self.authUseCase = AuthUseCase(repository: authRepository, userUseCase: userUseCase)
        self.feedUseCase = FeedUseCase(repository: feedRepository)
        self.postUseCase = PostUseCase(repository: postRepository)
        self.engagementUseCase = EngagementUseCase(repository: engagementRepository)
        self.commentsUseCase = CommentsUseCase(repository: commentRepository)
        self.stickersUseCase = StickersUseCase(repository: stickerRepository)
        self.analyticsUseCase = PostAnalyticsUseCase(repository: analyticsRepository)
        self.activityUseCase = PostActivityUseCase(repository: activityRepository)
        self.notificationUseCase = NotificationUseCase(repository: notificationRepository)
        self.directUseCase = DirectUseCase(repository: directRepository)
        let hasStoredCredentials = (try? tokenStore.load()) != nil
        self.sessionStore = AppSessionStore(
            authUseCase: authUseCase,
            userUseCase: userUseCase,
            tokenStore: tokenStore,
            hasStoredCredentials: hasStoredCredentials
        )
        self.appState = AppState()
        self.draftStore = DraftStore.makePersistent()

        ATTConsentManager.shared.configure(apiClient: apiClient)
        AppSessionTracker.shared.configure(apiClient: apiClient)

        // Cold-start auth failure keeps session nil, so ContentView.onChange never fires —
        // wire wipe/disconnect from the session store itself.
        sessionStore.onLocalSessionCleared = { [weak self] in
            await self?.clearUserSessionState()
        }
        sessionStore.onUserChanged = { [weak self] previousUserID, newUserID in
            self?.applyLocalUserChange(from: previousUserID, to: newUserID)
        }
    }

    func configureAuth() async {
        await apiClient.setSessionInvalidationHandler { @MainActor [weak self] in
            guard let self else { return }
            await self.clearUserSessionState()
            self.sessionStore.invalidateSession()
        }
        await apiClient.setTokensRefreshedHandler { @MainActor [weak sessionStore] _ in
            await sessionStore?.syncSessionFromStorage()
        }
    }

    /// Disconnect realtime and wipe local DM cache. Call on logout / session invalidation.
    func clearUserSessionState() async {
        wipeChatDrafts(for: sessionStore.session?.user.id ?? (try? tokenStore.load())?.userID)
        sessionStore.clearCurrentUserID()
        await PushRegistrationCenter.unregisterOnLogout()
        await realtimeClient.disconnect(discardPending: true)
        messageCacheStore.wipeAll()
        AppIconBadge.clear()
    }

    /// Queues socket teardown. Callers that subscribe must `switchGate.wait()` first.
    private func tearDownRealtime() {
        let client = realtimeClient
        client.switchGate.arm(Task { await client.disconnect(discardPending: true) })
    }

    private func wipeChatDrafts(for userID: String?) {
        guard let userID else { return }
        ChatDraftStore(userID: userID).clearAll()
    }

    /// Drops the previous account's DM cache before the next screen renders.
    func applyLocalUserChange(from previousUserID: String?, to newUserID: String?) {
        if let previousUserID, let newUserID, previousUserID != newUserID {
            wipeChatDrafts(for: previousUserID)
            messageCacheStore.wipeAll()
            messageCacheStore.beginSession(userID: newUserID)
            tearDownRealtime()
            AppIconBadge.clear()
        } else if let previousUserID, newUserID == nil {
            wipeChatDrafts(for: previousUserID)
            messageCacheStore.wipeAll()
            tearDownRealtime()
            AppIconBadge.clear()
        } else if let newUserID {
            messageCacheStore.beginSession(userID: newUserID)
        }
    }

    func makeAuthViewModel(onAuthenticated: @escaping (AuthSession) -> Void) -> AuthViewModel {
        AuthViewModel(
            authUseCase: authUseCase,
            onAuthenticated: onAuthenticated
        )
    }

    func makeTakesFeedViewModel() -> TakesFeedViewModel {
        TakesFeedViewModel(
            feedUseCase: feedUseCase,
            engagementUseCase: engagementUseCase,
            commentsUseCase: commentsUseCase,
            activityUseCase: activityUseCase,
            userUseCase: userUseCase
        )
    }

    func makeShotFeedViewModel() -> ShotFeedViewModel {
        ShotFeedViewModel(
            feedUseCase: feedUseCase,
            engagementUseCase: engagementUseCase,
            commentsUseCase: commentsUseCase,
            activityUseCase: activityUseCase,
            userUseCase: userUseCase
        )
    }

    func makeCreatePostViewModel() -> CreatePostViewModel {
        CreatePostViewModel(
            postUseCase: postUseCase,
            appState: appState,
            draftStore: draftStore
        )
    }

    func makeEngagementController() -> PostEngagementController {
        PostEngagementController(
            engagementUseCase: engagementUseCase,
            commentsUseCase: commentsUseCase
        )
    }

    func makeCommentsViewModel(postID: String, currentUserID: String, onCommentAdded: (() -> Void)? = nil) -> CommentsViewModel {
        CommentsViewModel(
            postID: postID,
            currentUserID: currentUserID,
            commentsUseCase: commentsUseCase,
            activityUseCase: activityUseCase,
            onCommentAdded: onCommentAdded
        )
    }

    func makeActivityViewModel(category: NotificationCategory? = nil) -> ActivityViewModel {
        ActivityViewModel(
            notificationUseCase: notificationUseCase,
            userUseCase: userUseCase,
            category: category
        )
    }

    func makeInboxViewModel() -> InboxViewModel {
        InboxViewModel(useCase: directUseCase, realtime: realtimeClient, repository: directRepository)
    }

    func makeInboxHomeViewModel() -> InboxHomeViewModel {
        InboxHomeViewModel(
            inbox: makeInboxViewModel(),
            notificationUseCase: notificationUseCase,
            directUseCase: directUseCase
        )
    }

    func makeNewMessageViewModel(currentUserID: String) -> NewMessageViewModel {
        NewMessageViewModel(
            currentUserID: currentUserID,
            userUseCase: userUseCase,
            searchUseCase: searchUseCase,
            directUseCase: directUseCase
        )
    }

    func makeDirectShareDependencies(currentUserID: String) -> DirectShareDependencies {
        DirectShareDependencies(
            directUseCase: directUseCase,
            userUseCase: userUseCase,
            searchUseCase: searchUseCase,
            currentUserID: currentUserID
        )
    }
}
