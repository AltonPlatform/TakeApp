import Foundation

@MainActor
final class AuthUseCase {
    private let repository: AuthRepositoryProtocol
    private let userUseCase: UserUseCase?

    init(repository: AuthRepositoryProtocol, userUseCase: UserUseCase? = nil) {
        self.repository = repository
        self.userUseCase = userUseCase
    }

    /// Loads the full profile into the session. On network failure, keeps `fallback`
    /// profile fields (DOB / isAdult / interests) instead of wiping them to a token stub.
    private func enrich(_ session: AuthSession, preserving fallback: User? = nil) async -> AuthSession {
        guard let userUseCase else {
            return Self.mergePreservingProfile(session, fallback: fallback)
        }
        guard let profile = try? await userUseCase.loadCurrentProfile() else {
            return Self.mergePreservingProfile(session, fallback: fallback)
        }
        let enriched = AuthSession(user: profile.asUser(), tokens: session.tokens)
        AgeGateConfirmationStore.shared.setViewerIsAdult(enriched.user.isAdult)
        return enriched
    }

    private static func mergePreservingProfile(_ session: AuthSession, fallback: User?) -> AuthSession {
        guard let fallback, fallback.id == session.user.id else {
            AgeGateConfirmationStore.shared.setViewerIsAdult(session.user.isAdult)
            return session
        }
        let merged = User(
            id: session.user.id,
            username: session.user.username,
            displayName: fallback.displayName,
            bio: fallback.bio,
            avatarURL: fallback.avatarURL,
            suiWallet: fallback.suiWallet,
            createdAt: fallback.createdAt,
            dateOfBirth: fallback.dateOfBirth,
            gender: fallback.gender,
            showSensitiveContent: fallback.showSensitiveContent,
            isAdult: fallback.isAdult,
            interests: fallback.interests
        )
        AgeGateConfirmationStore.shared.setViewerIsAdult(merged.isAdult)
        return AuthSession(user: merged, tokens: session.tokens)
    }

    func signInWithApple() async throws -> AuthSession {
        await enrich(try await repository.signInWithApple())
    }

    func signInWithGoogle() async throws -> AuthSession {
        await enrich(try await repository.signInWithGoogle())
    }

    func signInWithPasskey(username: String) async throws -> AuthSession {
        await enrich(try await repository.signInWithPasskey(username: username))
    }

    func sendMagicLink(to email: String) async throws {
        try await repository.sendMagicLink(to: email)
    }

    func verifyMagicLink(token: String) async throws -> AuthSession {
        await enrich(try await repository.verifyMagicLink(token: token))
    }

    /// Silently restores a stored session on cold start.
    /// Refreshes only when the access token is locally expired; keeps cached
    /// credentials on transient network failures.
    func restoreSession(preserving fallback: User? = nil) async throws -> AuthSession? {
        try await refreshIfNeeded(preserving: fallback)
    }

    func refreshIfNeeded(preserving fallback: User? = nil) async throws -> AuthSession? {
        guard let session = await repository.currentSession() else {
            return nil
        }

        guard session.tokens.isExpired else {
            return await enrich(session, preserving: fallback)
        }

        return await enrich(try await repository.refreshTokens(), preserving: fallback)
    }

    func currentSession(preserving fallback: User? = nil) async -> AuthSession? {
        guard let session = await repository.currentSession() else { return nil }
        return await enrich(session, preserving: fallback)
    }

    func logout() async throws {
        try await repository.logout()
        AgeGateConfirmationStore.shared.reset()
        SensitiveRevealSessionStore.shared.reset()
    }
}
