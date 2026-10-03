import Foundation
import Observation

enum DeepLink: Equatable, Sendable {
    case post(String)
    case user(String)
}

@MainActor
@Observable
final class AppSessionStore {
    var session: AuthSession? {
        didSet {
            let userID = session?.user.id
            CrashReporting.setUser(id: userID)
            AnalyticsReporting.setUser(id: userID)

            // Skip cold-start restore noise; only track interactive auth transitions.
            guard !isRestoringSession else { return }
            if oldValue == nil, session != nil {
                AnalyticsReporting.logLogin(method: "auth")
            } else if oldValue != nil, session == nil {
                AnalyticsReporting.logLogout()
            }
        }
    }
    var pendingDeepLink: DeepLink?
    var magicLinkErrorMessage: String?
    /// True while cold-start session restoration is in progress.
    /// Prevents a flash of the login screen before refresh completes.
    private(set) var isRestoringSession = true
    private let authUseCase: AuthUseCase
    private let tokenStore: TokenStoreProtocol

    init(authUseCase: AuthUseCase, tokenStore: TokenStoreProtocol, hasStoredCredentials: Bool) {
        self.authUseCase = authUseCase
        self.tokenStore = tokenStore
        self.isRestoringSession = hasStoredCredentials
    }

    func restoreSession() async {
        defer { isRestoringSession = false }

        let previousUser = session?.user
        do {
            session = try await authUseCase.restoreSession(preserving: previousUser)
            if let user = session?.user {
                AgeGateConfirmationStore.shared.setViewerIsAdult(user.isAdult)
            }
        } catch {
            if NetworkErrorClassifier.isAuthFailure(error) {
                try? await authUseCase.logout()
                session = nil
            } else {
                session = await authUseCase.currentSession(preserving: previousUser)
            }
        }
    }

    func invalidateSession() {
        session = nil
        AgeGateConfirmationStore.shared.reset()
        SensitiveRevealSessionStore.shared.reset()
    }

    /// Updates the in-memory user and persists username on stored tokens after profile edits.
    func updateCurrentUser(from profile: UserProfile) {
        guard let current = session, current.user.id == profile.id else { return }
        let tokens = AuthTokens(
            accessToken: current.tokens.accessToken,
            refreshToken: current.tokens.refreshToken,
            expiresIn: current.tokens.expiresIn,
            userID: current.tokens.userID,
            username: profile.username,
            issuedAt: current.tokens.issuedAt
        )
        try? tokenStore.save(tokens)
        session = AuthSession(user: profile.asUser(), tokens: tokens)
        AgeGateConfirmationStore.shared.setViewerIsAdult(profile.isAdult)
    }

    /// Refreshes tokens when the app returns to foreground or after a silent refresh.
    func refreshIfNeeded() async {
        guard let current = session else { return }

        do {
            if let updated = try await authUseCase.refreshIfNeeded(preserving: current.user) {
                session = updated
            }
        } catch {
            if NetworkErrorClassifier.isAuthFailure(error) {
                try? await authUseCase.logout()
                session = nil
            }
        }
    }

    func syncSessionFromStorage() async {
        guard let current = session else { return }
        session = await authUseCase.currentSession(preserving: current.user)
    }

    func clearPendingDeepLink() {
        pendingDeepLink = nil
    }

    func handleUniversalLink(_ url: URL) async {
        guard url.scheme == "https",
              AppEnvironment.current.magicLinkUniversalHosts.contains(url.host ?? "") else {
            return
        }

        let path = url.path
        guard path.contains("magic-link") || path.contains("auth/verify") else { return }

        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value,
            !token.isEmpty else {
            return
        }

        guard let expectedState = MagicLinkStateStore.load(),
              let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "state" })?
                .value,
              state == expectedState else {
            magicLinkErrorMessage = "Magic link verification failed. Request a new sign-in link."
            return
        }

        do {
            session = try await authUseCase.verifyMagicLink(token: token)
            MagicLinkStateStore.clear()
            magicLinkErrorMessage = nil
        } catch {
            magicLinkErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Magic link verification failed. Request a new sign-in link."
        }
    }

    func handleIncomingURL(_ url: URL) async {
        if url.scheme == "https" {
            await handleUniversalLink(url)
            return
        }

        guard url.scheme == AppEnvironment.current.appURLScheme else { return }

        switch url.host {
        case "auth":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let token = components?
                .queryItems?
                .first(where: { $0.name == "token" })?
                .value,
                !token.isEmpty else {
                return
            }
            guard let expectedState = MagicLinkStateStore.load(),
                  let state = components?
                    .queryItems?
                    .first(where: { $0.name == "state" })?
                    .value,
                  state == expectedState else {
                magicLinkErrorMessage = "Magic link verification failed. Request a new sign-in link."
                return
            }
            do {
                session = try await authUseCase.verifyMagicLink(token: token)
                MagicLinkStateStore.clear()
                magicLinkErrorMessage = nil
            } catch {
                magicLinkErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Magic link verification failed. Request a new sign-in link."
            }
        case "post":
            let postID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if Self.isValidResourceID(postID) {
                pendingDeepLink = .post(postID)
            }
        case "user":
            let userID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if Self.isValidResourceID(userID) {
                pendingDeepLink = .user(userID)
            }
        default:
            break
        }
    }

    private static func isValidResourceID(_ value: String) -> Bool {
        (try? APIEndpoint.validateResourceID(value)) != nil
    }
}
