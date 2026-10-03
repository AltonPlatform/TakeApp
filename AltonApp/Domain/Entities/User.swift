import Foundation

struct User: Equatable, Identifiable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let bio: String?
    let avatarURL: URL?
    let suiWallet: String?
    let createdAt: Date?
    /// Calendar day of birth (date components only).
    let dateOfBirth: Date?
    let gender: Gender?
    var showSensitiveContent: Bool
    /// Server-derived: age ≥ 18 from `dateOfBirth` (false when DOB missing).
    var isAdult: Bool
    var interests: [Interest]

    init(
        id: String,
        username: String,
        displayName: String,
        bio: String?,
        avatarURL: URL?,
        suiWallet: String?,
        createdAt: Date?,
        dateOfBirth: Date? = nil,
        gender: Gender? = nil,
        showSensitiveContent: Bool = false,
        isAdult: Bool? = nil,
        interests: [Interest] = []
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.avatarURL = avatarURL
        self.suiWallet = suiWallet
        self.createdAt = createdAt
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.showSensitiveContent = showSensitiveContent
        self.isAdult = isAdult ?? Self.computeIsAdult(from: dateOfBirth)
        self.interests = interests
    }

    var needsAgeGender: Bool {
        dateOfBirth == nil || gender == nil
    }

    var needsInterests: Bool {
        interests.isEmpty
    }

    static func computeIsAdult(from dateOfBirth: Date?, now: Date = Date()) -> Bool {
        guard let dateOfBirth else { return false }
        let years = Calendar.current.dateComponents([.year], from: dateOfBirth, to: now).year ?? 0
        return years >= 18
    }
}

struct AuthSession: Equatable, Sendable {
    let user: User
    let tokens: AuthTokens
}
