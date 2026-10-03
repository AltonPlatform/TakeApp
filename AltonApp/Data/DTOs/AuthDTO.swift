import Foundation

struct AuthResponseDTO: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: UInt64
    let userID: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case userID = "user_id"
        case username
    }

    func toDomain(displayName: String? = nil, suiWallet: String? = nil) -> AuthSession {
        let tokens = AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: TimeInterval(expiresIn),
            userID: userID,
            username: username
        )
        let user = User(
            id: userID,
            username: username,
            displayName: displayName ?? username,
            bio: nil,
            avatarURL: nil,
            suiWallet: suiWallet,
            createdAt: nil
        )
        return AuthSession(user: user, tokens: tokens)
    }
}

struct RefreshRequestDTO: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

enum AuthProvider: String, CaseIterable, Identifiable {
    case apple
    case google
    case passkey
    case magicLink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Sign in with Apple"
        case .google: return "Continue with Google"
        case .passkey: return "Sign in with Passkey"
        case .magicLink: return "Email Magic Link"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "g.circle.fill"
        case .passkey: return "person.badge.key.fill"
        case .magicLink: return "envelope.fill"
        }
    }
}

struct AppleCallbackRequestDTO: Encodable {
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

struct GoogleIdTokenRequestDTO: Encodable {
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

struct MagicLinkSendRequestDTO: Encodable {
    let email: String
    let state: String
}

struct MagicLinkVerifyRequestDTO: Encodable {
    let token: String
}

struct MagicLinkSendResponseDTO: Decodable {
    let sent: Bool
}

struct PasskeyLoginStartRequestDTO: Encodable {
    let username: String
}

struct PasskeyLoginFinishRequestDTO: Encodable {
    let challengeID: String
    let credential: PasskeyCredentialDTO

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case credential
    }
}

struct PasskeyCredentialDTO: Encodable {
    let id: String
    let rawID: String
    let type: String
    let response: PasskeyCredentialResponseDTO

    enum CodingKeys: String, CodingKey {
        case id
        case rawID = "rawId"
        case type
        case response
    }
}

struct PasskeyCredentialResponseDTO: Encodable {
    let authenticatorData: String
    let clientDataJSON: String
    let signature: String
    let userHandle: String?

    enum CodingKeys: String, CodingKey {
        case authenticatorData
        case clientDataJSON
        case signature
        case userHandle
    }
}

struct PasskeyLoginChallengeDTO: Decodable {
    let challengeID: String
    let challenge: String
    let rpID: String?
    let timeout: Int?
    let allowCredentials: [PasskeyAllowCredentialDTO]?

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case challenge
        case rpID = "rpId"
        case timeout
        case allowCredentials
        case publicKey
    }

    init(from decoder: Decoder) throws {
        if let nested = try? decoder.container(keyedBy: CodingKeys.self),
           nested.contains(.publicKey) {
            let publicKey = try nested.nestedContainer(keyedBy: CodingKeys.self, forKey: .publicKey)
            challengeID = try nested.decode(String.self, forKey: .challengeID)
            challenge = try publicKey.decode(String.self, forKey: .challenge)
            rpID = try publicKey.decodeIfPresent(String.self, forKey: .rpID)
            timeout = try publicKey.decodeIfPresent(Int.self, forKey: .timeout)
            allowCredentials = try publicKey.decodeIfPresent([PasskeyAllowCredentialDTO].self, forKey: .allowCredentials)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        challengeID = try container.decode(String.self, forKey: .challengeID)
        challenge = try container.decode(String.self, forKey: .challenge)
        rpID = try container.decodeIfPresent(String.self, forKey: .rpID)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
        allowCredentials = try container.decodeIfPresent([PasskeyAllowCredentialDTO].self, forKey: .allowCredentials)
    }
}

struct PasskeyAllowCredentialDTO: Decodable {
    let id: String
    let type: String?
}
