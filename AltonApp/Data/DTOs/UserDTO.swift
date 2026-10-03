import Foundation

struct InterestDTO: Codable, Equatable, Sendable {
    let category: String
    let subcategory: String
    let weight: Double

    func toDomain() -> Interest {
        Interest(category: category, subcategory: subcategory, weight: weight)
    }

    init(from interest: Interest) {
        category = interest.category
        subcategory = interest.subcategory
        weight = interest.weight
    }

    init(category: String, subcategory: String, weight: Double) {
        self.category = category
        self.subcategory = subcategory
        self.weight = weight
    }
}

struct InterestsResponseDTO: Decodable {
    let interests: [InterestDTO]
}

struct UpdateInterestsSuccessDTO: Decodable {
    let success: Bool
}

struct UserProfileDTO: Decodable {
    let id: String
    let username: String
    let displayName: String
    let bio: String?
    let avatarURL: URL?
    let suiWallet: String?
    let createdAt: String?
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool
    let takeCount: Int
    let shotCount: Int
    let dateOfBirth: String?
    let gender: String?
    let showSensitiveContent: Bool
    let isAdult: Bool
    let interests: [InterestDTO]

    enum CodingKeys: String, CodingKey {
        case id, username, bio, gender, interests
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case suiWallet = "sui_wallet"
        case createdAt = "created_at"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
        case takeCount = "take_count"
        case shotCount = "shot_count"
        case threadCount = "thread_count"
        case videoCount = "video_count"
        case dateOfBirth = "date_of_birth"
        case showSensitiveContent = "show_sensitive_content"
        case isAdult = "is_adult"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        suiWallet = try container.decodeIfPresent(String.self, forKey: .suiWallet)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        followerCount = try container.decode(Int.self, forKey: .followerCount)
        followingCount = try container.decode(Int.self, forKey: .followingCount)
        isFollowing = try container.decode(Bool.self, forKey: .isFollowing)
        takeCount = try container.decodeIfPresent(Int.self, forKey: .takeCount)
            ?? container.decodeIfPresent(Int.self, forKey: .threadCount)
            ?? 0
        shotCount = try container.decodeIfPresent(Int.self, forKey: .shotCount)
            ?? container.decodeIfPresent(Int.self, forKey: .videoCount)
            ?? 0
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        showSensitiveContent = try container.decodeIfPresent(Bool.self, forKey: .showSensitiveContent) ?? false
        let parsedDOB = APIDateParser.parseDay(dateOfBirth)
        isAdult = try container.decodeIfPresent(Bool.self, forKey: .isAdult)
            ?? User.computeIsAdult(from: parsedDOB)
        interests = try container.decodeIfPresent([InterestDTO].self, forKey: .interests) ?? []
    }

    func toDomain() -> UserProfile {
        UserProfile(
            id: id,
            username: username,
            displayName: displayName,
            bio: bio,
            avatarURL: avatarURL,
            suiWallet: suiWallet,
            createdAt: APIDateParser.parse(createdAt),
            followerCount: followerCount,
            followingCount: followingCount,
            isFollowing: isFollowing,
            takeCount: takeCount,
            shotCount: shotCount,
            dateOfBirth: APIDateParser.parseDay(dateOfBirth),
            gender: gender.flatMap(Gender.init(rawValue:)),
            showSensitiveContent: showSensitiveContent,
            isAdult: isAdult,
            interests: interests.map { $0.toDomain() }
        )
    }
}

struct UserPostsPageDTO: Decodable {
    let items: [PostDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

struct FollowUsersPageDTO: Decodable {
    let users: [FollowUserDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case users
        case nextCursor = "next_cursor"
    }
}

struct FollowUserDTO: Decodable {
    let userID: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    let isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case username
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case isFollowing = "is_following"
    }

    func toDomain() -> FollowUser {
        FollowUser(
            id: userID,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL,
            isFollowing: isFollowing
        )
    }
}

struct AvatarUploadDTO: Decodable {
    let uploadURL: URL
    let objectKey: String
    let expiresIn: UInt64

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case objectKey = "object_key"
        case expiresIn = "expires_in"
    }
}

struct FollowResponseDTO: Decodable {
    let success: Bool
    let following: Bool
}

struct UsernameAvailableDTO: Decodable {
    let available: Bool
}

struct SearchPostsPageDTO: Decodable {
    let items: [PostDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

struct BookmarksPageDTO: Decodable {
    let items: [PostDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}
