import Foundation
import Observation

enum DeepLink: Equatable, Sendable {
    case post(String)
    case user(String)
    case invite(String)
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

            if session != nil, let username = pendingProfileUsername {
                pendingProfileUsername = nil
                Task { await resolveProfileShareLink(username: username) }
            }
        }
    }
    var pendingDeepLink: DeepLink?
    var magicLinkErrorMessage: String?
    /// True while cold-start session restoration is in progress.
    /// Prevents a flash of the login screen before refresh completes.
    private(set) var isRestoringSession = true
    /// Profile share link received before session restore completes.
    private(set) var pendingProfileUsername: String?
    private let authUseCase: AuthUseCase
    private let userUseCase: UserUseCase
    private let tokenStore: TokenStoreProtocol

    init(
        authUseCase: AuthUseCase,
        userUseCase: UserUseCase,
        tokenStore: TokenStoreProtocol,
        hasStoredCredentials: Bool
    ) {
        self.authUseCase = authUseCase
        self.userUseCase = userUseCase
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
        guard url.scheme == "https", let host = url.host?.lowercased() else { return }

        // Content share links: https://{shareDomain}/p/{id}
        if AppEnvironment.current.shareUniversalHosts.contains(host),
           let postID = ShareDeepLinkParser.postID(fromPath: url.path) {
            pendingDeepLink = .post(postID)
            return
        }

        if AppEnvironment.current.shareUniversalHosts.contains(host),
           let username = ShareDeepLinkParser.profileUsername(fromPath: url.path) {
            await resolveProfileShareLink(username: username)
            return
        }

        if AppEnvironment.current.shareUniversalHosts.contains(host),
           let inviteCode = ShareDeepLinkParser.inviteCode(fromPath: url.path) {
            storePendingInvite(code: inviteCode)
            pendingDeepLink = .invite(inviteCode)
            return
        }

        // SSO magic links (existing behaviour).
        guard AppEnvironment.current.magicLinkUniversalHosts.contains(host) else {
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
        case "invite", "i":
            let code = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if ShareDeepLinkParser.isValidInviteCode(code) {
                storePendingInvite(code: code)
                pendingDeepLink = .invite(code)
            }
        default:
            break
        }
    }

    private func storePendingInvite(code: String) {
        try? PendingInviteStore.save(code)
    }

    private static func isValidResourceID(_ value: String) -> Bool {
        (try? APIEndpoint.validateResourceID(value)) != nil
    }

    private func resolveProfileShareLink(username: String) async {
        guard session != nil else {
            pendingProfileUsername = username
            return
        }
        do {
            let profile = try await userUseCase.loadProfileByUsername(username)
            pendingDeepLink = .user(profile.id)
        } catch {
            // Unknown or blocked profile — ignore silently (matches web 404).
        }
    }
}

enum ShareDeepLinkParser {
    /// Parses `/p/{ulid}` (optional trailing slash / extra path ignored).
    static func postID(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "p" else { return nil }
        let postID = parts[1]
        guard (try? APIEndpoint.validateResourceID(postID)) != nil else { return nil }
        return postID
    }

    /// Parses `/u/{username}` (optional trailing slash / extra path ignored).
    static func profileUsername(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "u" else { return nil }
        let username = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard username.count >= 3, username.count <= 20 else { return nil }
        guard username.allSatisfy({ ch in
            ch.isASCII && (ch.isNumber || (ch.isLetter && ch.isLowercase) || ch == "_")
        }) else { return nil }
        return username
    }

    static func inviteCode(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "i" else { return nil }
        let code = parts[1]
        return isValidInviteCode(code) ? code : nil
    }

    static func isValidInviteCode(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 32 else { return false }
        let segments = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 2 else { return false }
        let nonce = segments[0]
        let sig = segments[1]
        guard (6...12).contains(nonce.count) else { return false }
        guard sig.count == 16 else { return false }
        let nonceOK = nonce.allSatisfy { $0.isLetter || $0.isNumber }
        let sigOK = sig.allSatisfy { $0.isHexDigit }
        return nonceOK && sigOK
    }
}

enum ProfileShareLink {
    static func url(forUsername username: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = AppEnvironment.current.shareDomain
        components.path = "/u/\(username)"
        return components.url!
    }
}
