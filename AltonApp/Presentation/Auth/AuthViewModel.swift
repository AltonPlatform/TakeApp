import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    enum MagicLinkStep {
        case hidden
        case emailEntry
        case linkSent
    }

    enum PasskeyStep {
        case hidden
        case usernameEntry
    }

    var isLoading = false
    var loadingProvider: AuthProvider?
    var errorMessage: String?
    var infoMessage: String?
    var magicLinkStep: MagicLinkStep = .hidden
    var passkeyStep: PasskeyStep = .hidden
    var magicLinkEmail = ""
    var passkeyUsername = ""

    private let authUseCase: AuthUseCase
    private let onAuthenticated: (AuthSession) -> Void

    init(
        authUseCase: AuthUseCase,
        onAuthenticated: @escaping (AuthSession) -> Void
    ) {
        self.authUseCase = authUseCase
        self.onAuthenticated = onAuthenticated
    }

    func signIn(with provider: AuthProvider) async {
        switch provider {
        case .magicLink:
            magicLinkStep = .emailEntry
            return
        case .passkey:
            passkeyStep = .usernameEntry
            return
        default:
            break
        }

        await performSignIn(provider: provider) {
            switch provider {
            case .apple:
                try await authUseCase.signInWithApple()
            case .google:
                try await authUseCase.signInWithGoogle()
            case .passkey:
                try await authUseCase.signInWithPasskey(username: passkeyUsername)
            default:
                throw APIError.unknown
            }
        }
    }

    func sendMagicLink() async {
        guard !isLoading else { return }
        isLoading = true
        loadingProvider = .magicLink
        errorMessage = nil
        infoMessage = nil
        defer {
            isLoading = false
            loadingProvider = nil
        }

        do {
            try await authUseCase.sendMagicLink(to: magicLinkEmail)
            magicLinkStep = .linkSent
            infoMessage = "Check your inbox for a sign-in link."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func verifyMagicLink(token: String) async {
        await performSignIn(provider: .magicLink) {
            try await authUseCase.verifyMagicLink(token: token)
        }
    }

    func cancelPasskey() {
        passkeyStep = .hidden
        passkeyUsername = ""
        errorMessage = nil
    }

    func signInWithPasskey() async {
        await performSignIn(provider: .passkey) {
            try await authUseCase.signInWithPasskey(username: passkeyUsername)
        }
    }

    func cancelMagicLink() {
        magicLinkStep = .hidden
        magicLinkEmail = ""
        infoMessage = nil
        errorMessage = nil
    }

    private func performSignIn(
        provider: AuthProvider,
        action: () async throws -> AuthSession
    ) async {
        guard !isLoading else { return }
        isLoading = true
        loadingProvider = provider
        errorMessage = nil
        infoMessage = nil
        defer {
            isLoading = false
            loadingProvider = nil
        }

        do {
            let session = try await action()
            onAuthenticated(session)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
