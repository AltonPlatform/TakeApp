import Foundation

struct AuthTokens: Equatable, Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let userID: String
    let username: String
    let issuedAt: Date

    init(
        accessToken: String,
        refreshToken: String,
        expiresIn: TimeInterval,
        userID: String,
        username: String,
        issuedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.userID = userID
        self.username = username
        self.issuedAt = issuedAt
    }

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresIn
        case userID
        case username
        case issuedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expiresIn = try container.decode(TimeInterval.self, forKey: .expiresIn)
        userID = try container.decode(String.self, forKey: .userID)
        username = try container.decode(String.self, forKey: .username)
        // Legacy keychain entries without issuedAt should refresh on next request.
        issuedAt = try container.decodeIfPresent(Date.self, forKey: .issuedAt) ?? .distantPast
    }

    var expirationDate: Date {
        issuedAt.addingTimeInterval(expiresIn)
    }

    /// Refresh one minute before expiry to avoid mid-request 401s.
    var isExpired: Bool {
        Date() >= expirationDate.addingTimeInterval(-60)
    }
}
