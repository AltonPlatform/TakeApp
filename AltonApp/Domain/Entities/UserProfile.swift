import Foundation

struct UserProfile: Equatable, Identifiable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let bio: String?
    let avatarURL: URL?
    let suiWallet: String?
    let createdAt: Date?
    var followerCount: Int
    let followingCount: Int
    var isFollowing: Bool
    let takeCount: Int
    let shotCount: Int
    var isOwnProfile: Bool = false
    let dateOfBirth: Date?
    let gender: Gender?
    var showSensitiveContent: Bool
    let isAdult: Bool
    var interests: [Interest]

    init(
        id: String,
        username: String,
        displayName: String,
        bio: String?,
        avatarURL: URL?,
        suiWallet: String?,
        createdAt: Date?,
        followerCount: Int,
        followingCount: Int,
        isFollowing: Bool,
        takeCount: Int,
        shotCount: Int,
        isOwnProfile: Bool = false,
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
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.isFollowing = isFollowing
        self.takeCount = takeCount
        self.shotCount = shotCount
        self.isOwnProfile = isOwnProfile
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.showSensitiveContent = showSensitiveContent
        self.isAdult = isAdult ?? User.computeIsAdult(from: dateOfBirth)
        self.interests = interests
    }

    var needsAgeGender: Bool {
        dateOfBirth == nil || gender == nil
    }

    var needsInterests: Bool {
        interests.isEmpty
    }

    func asUser() -> User {
        User(
            id: id,
            username: username,
            displayName: displayName,
            bio: bio,
            avatarURL: avatarURL,
            suiWallet: suiWallet,
            createdAt: createdAt,
            dateOfBirth: dateOfBirth,
            gender: gender,
            showSensitiveContent: showSensitiveContent,
            isAdult: isAdult,
            interests: interests
        )
    }
}

enum ProfilePostTab: String, CaseIterable, Sendable {
    case takes
    case shots
}
