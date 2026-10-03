import Foundation

protocol AuthRepositoryProtocol: Sendable {
    func signInWithApple() async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signInWithPasskey(username: String) async throws -> AuthSession
    func sendMagicLink(to email: String) async throws
    func verifyMagicLink(token: String) async throws -> AuthSession
    func refreshTokens() async throws -> AuthSession
    func logout() async throws
    func currentSession() async -> AuthSession?
}
