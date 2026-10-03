import Foundation

final class AuthRepository: AuthRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient
    private let appleProvider: AppleAuthProvider
    private let googleProvider: GoogleAuthProvider
    private let passkeyProvider: PasskeyAuthProvider
    private let magicLinkProvider: MagicLinkAuthProvider

    init(
        apiClient: APIClient,
        appleProvider: AppleAuthProvider,
        googleProvider: GoogleAuthProvider,
        passkeyProvider: PasskeyAuthProvider,
        magicLinkProvider: MagicLinkAuthProvider
    ) {
        self.apiClient = apiClient
        self.appleProvider = appleProvider
        self.googleProvider = googleProvider
        self.passkeyProvider = passkeyProvider
        self.magicLinkProvider = magicLinkProvider
    }

    @MainActor
    func signInWithApple() async throws -> AuthSession {
        try await appleProvider.signIn()
    }

    @MainActor
    func signInWithGoogle() async throws -> AuthSession {
        try await googleProvider.signIn()
    }

    @MainActor
    func signInWithPasskey(username: String) async throws -> AuthSession {
        try await passkeyProvider.signIn(username: username)
    }

    @MainActor
    func sendMagicLink(to email: String) async throws {
        try await magicLinkProvider.sendLink(to: email)
    }

    @MainActor
    func verifyMagicLink(token: String) async throws -> AuthSession {
        try await magicLinkProvider.verify(token: token)
    }

    func refreshTokens() async throws -> AuthSession {
        let tokens = try await apiClient.refreshTokens()
        return AuthSession(
            user: User(
                id: tokens.userID,
                username: tokens.username,
                displayName: tokens.username,
                bio: nil,
                avatarURL: nil,
                suiWallet: nil,
                createdAt: nil
            ),
            tokens: tokens
        )
    }

    func logout() async throws {
        try await apiClient.logout()
    }

    func currentSession() async -> AuthSession? {
        guard let tokens = try? await apiClient.loadTokens() else {
            return nil
        }
        return AuthSession(
            user: User(
                id: tokens.userID,
                username: tokens.username,
                displayName: tokens.username,
                bio: nil,
                avatarURL: nil,
                suiWallet: nil,
                createdAt: nil
            ),
            tokens: tokens
        )
    }
}
