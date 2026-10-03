import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

@MainActor
final class AppleAuthProvider: NSObject {
    private let ssoClient: SSOClient
    private let tokenStore: TokenStoreProtocol
    private var continuation: CheckedContinuation<AuthSession, Error>?

    init(ssoClient: SSOClient, tokenStore: TokenStoreProtocol) {
        self.ssoClient = ssoClient
        self.tokenStore = tokenStore
    }

    func signIn() async throws -> AuthSession {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func complete(with result: Result<AuthSession, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension AppleAuthProvider: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            do {
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    throw APIError.unauthorized
                }

                let response: AuthResponseDTO = try await ssoClient.request(
                    .appleCallback,
                    body: AppleCallbackRequestDTO(idToken: idToken)
                )
                let session = response.toDomain()
                try tokenStore.save(session.tokens)
                complete(with: .success(session))
            } catch {
                complete(with: .failure(error))
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                complete(with: .failure(APIError.validation("Sign in cancelled.")))
            } else {
                complete(with: .failure(error))
            }
        }
    }
}

extension AppleAuthProvider: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            let window = windowScene?.windows.first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor()
        }
    }
}
