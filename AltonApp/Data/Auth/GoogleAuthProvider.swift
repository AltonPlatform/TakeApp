import GoogleSignIn
import UIKit

@MainActor
final class GoogleAuthProvider {
    private let ssoClient: SSOClient
    private let tokenStore: TokenStoreProtocol

    init(ssoClient: SSOClient, tokenStore: TokenStoreProtocol) {
        self.ssoClient = ssoClient
        self.tokenStore = tokenStore
    }

    func signIn() async throws -> AuthSession {
        guard GoogleAuthConfig.isConfigured else {
            throw APIError.validation(
                "Add GoogleService-Info.plist to the app target (see GoogleService-Info.example.plist)."
            )
        }

        guard let presenter = Self.rootViewController() else {
            throw APIError.network("Could not present Google Sign-In.")
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            let user = result.user
            if user.idToken == nil {
                _ = try await user.refreshTokensIfNeeded()
            }
            guard let idToken = user.idToken?.tokenString else {
                throw APIError.validation("Google did not return an ID token.")
            }

            let response: AuthResponseDTO = try await ssoClient.request(
                .googleNativeSignIn,
                body: GoogleIdTokenRequestDTO(idToken: idToken)
            )
            let session = response.toDomain()
            try tokenStore.save(session.tokens)
            return session
        } catch let error as GIDSignInError where error.code == .canceled {
            throw APIError.validation("Google sign in cancelled.")
        }
    }

    private static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return windowScene?.windows.first(where: \.isKeyWindow)?.rootViewController
    }
}
