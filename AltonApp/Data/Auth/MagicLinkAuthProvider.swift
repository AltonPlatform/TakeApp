import Foundation

enum EmailValidator {
    private static let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#

    static func isValid(_ email: String) -> Bool {
        guard !email.isEmpty,
              email.rangeOfCharacter(from: .controlCharacters) == nil,
              email.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return false
        }

        if email.range(of: pattern, options: .regularExpression) != nil {
            return true
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }

        let range = NSRange(email.startIndex..<email.endIndex, in: email)
        let matches = detector.matches(in: email, options: [], range: range)
        guard matches.count == 1,
              let match = matches.first,
              match.resultType == .link,
              let matchedURL = match.url,
              matchedURL.scheme == "mailto",
              matchedURL.absoluteString == "mailto:\(email)" else {
            return false
        }
        return true
    }
}

@MainActor
final class MagicLinkAuthProvider {
    private let ssoClient: SSOClient
    private let tokenStore: TokenStoreProtocol

    init(ssoClient: SSOClient, tokenStore: TokenStoreProtocol) {
        self.ssoClient = ssoClient
        self.tokenStore = tokenStore
    }

    func sendLink(to email: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard EmailValidator.isValid(normalized) else {
            throw APIError.validation("Enter a valid email address.")
        }

        let state = UUID().uuidString
        try MagicLinkStateStore.save(state)

        let _: MagicLinkSendResponseDTO = try await ssoClient.request(
            .magicLinkSend,
            body: MagicLinkSendRequestDTO(email: normalized, state: state)
        )
    }

    func verify(token: String) async throws -> AuthSession {
        let response: AuthResponseDTO = try await ssoClient.request(
            .magicLinkVerify,
            body: MagicLinkVerifyRequestDTO(token: token)
        )
        let session = response.toDomain()
        try tokenStore.save(session.tokens)
        return session
    }
}
