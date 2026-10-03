import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class PasskeyAuthProvider: NSObject {
    private let ssoClient: SSOClient
    private let tokenStore: TokenStoreProtocol
    private var continuation: CheckedContinuation<AuthSession, Error>?
    private var challengeID: String = ""

    init(ssoClient: SSOClient, tokenStore: TokenStoreProtocol) {
        self.ssoClient = ssoClient
        self.tokenStore = tokenStore
    }

    func signIn(username: String) async throws -> AuthSession {
        guard continuation == nil else {
            throw APIError.validation("Passkey sign-in already in progress.")
        }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.validation("Username is required for passkey sign-in.")
        }

        let body = PasskeyLoginStartRequestDTO(username: trimmed)
        let challenge: PasskeyLoginChallengeDTO = try await ssoClient.request(.passkeyLoginStart, body: body)
        challengeID = challenge.challengeID

        guard let challengeData = Data(base64URLEncoded: challenge.challenge) else {
            throw APIError.decodingFailed
        }

        let rpID = challenge.rpID ?? AppEnvironment.current.webAuthnRelyingPartyID
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let request = provider.createCredentialAssertionRequest(challenge: challengeData)

        if let allowCredentials = challenge.allowCredentials {
            request.allowedCredentials = allowCredentials.compactMap { credential in
                guard let id = Data(base64URLEncoded: credential.id) else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func complete(with result: Result<AuthSession, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }
}

extension PasskeyAuthProvider: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            do {
                guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
                    throw APIError.unauthorized
                }

                let body = PasskeyLoginFinishRequestDTO(
                    challengeID: challengeID,
                    credential: PasskeyCredentialDTO(
                        id: credential.credentialID.base64URLEncodedString(),
                        rawID: credential.credentialID.base64URLEncodedString(),
                        type: "public-key",
                        response: PasskeyCredentialResponseDTO(
                            authenticatorData: credential.rawAuthenticatorData.base64URLEncodedString(),
                            clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                            signature: credential.signature.base64URLEncodedString(),
                            userHandle: credential.userID.isEmpty
                                ? nil
                                : credential.userID.base64URLEncodedString()
                        )
                    )
                )

                let response: AuthResponseDTO = try await ssoClient.request(.passkeyLoginFinish, body: body)
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
                complete(with: .failure(APIError.validation("Passkey sign in cancelled.")))
            } else {
                complete(with: .failure(error))
            }
        }
    }
}

extension PasskeyAuthProvider: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            return windowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
