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
    let earningsRepository: EarningsRepository
    let adRepository: AdRepository
    let sessionStore: AppSessionStore
    let appState: AppState
    let draftStore: DraftStore

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
    }

    func configureAuth() async {
        await apiClient.setSessionInvalidationHandler { @MainActor [weak sessionStore] in
            sessionStore?.invalidateSession()
        }
        await apiClient.setTokensRefreshedHandler { @MainActor [weak sessionStore] _ in
            await sessionStore?.syncSessionFromStorage()
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

    func makeActivityViewModel() -> ActivityViewModel {
        ActivityViewModel(
            notificationUseCase: notificationUseCase,
            userUseCase: userUseCase
        )
    }
}
