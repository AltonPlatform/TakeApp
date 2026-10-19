import Foundation

final class UserRepository: UserRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchCurrentProfile() async throws -> UserProfile {
        let dto: UserProfileDTO = try await apiClient.authorizedRequest(.currentUserProfile)
        var profile = dto.toDomain()
        profile.isOwnProfile = true
        return profile
    }

    func fetchProfile(userID: String) async throws -> UserProfile {
        let dto: UserProfileDTO = try await apiClient.authorizedRequest(.userProfile(id: userID))
        return dto.toDomain()
    }

    func fetchProfileByUsername(_ username: String) async throws -> UserProfile {
        let dto: UserProfileDTO = try await apiClient.authorizedRequest(.userByUsername(username))
        return dto.toDomain()
    }

    func updateProfile(
        displayName: String?,
        bio: String?,
        avatarR2Key: String?,
        dateOfBirth: Date? = nil,
        gender: Gender? = nil,
        showSensitiveContent: Bool? = nil,
        clearDateOfBirth: Bool = false,
        clearGender: Bool = false
    ) async throws -> UserProfile {
        struct Body: Encodable {
            let displayName: String?
            let bio: String?
            let avatarR2Key: String?
            let dateOfBirth: String?
            let gender: String?
            let showSensitiveContent: Bool?
            let clearDateOfBirth: Bool?
            let clearGender: Bool?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case bio
                case avatarR2Key = "avatar_r2_key"
                case dateOfBirth = "date_of_birth"
                case gender
                case showSensitiveContent = "show_sensitive_content"
                case clearDateOfBirth = "clear_date_of_birth"
                case clearGender = "clear_gender"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(displayName, forKey: .displayName)
                try container.encodeIfPresent(bio, forKey: .bio)
                try container.encodeIfPresent(avatarR2Key, forKey: .avatarR2Key)
                try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
                try container.encodeIfPresent(gender, forKey: .gender)
                try container.encodeIfPresent(showSensitiveContent, forKey: .showSensitiveContent)
                if clearDateOfBirth == true {
                    try container.encode(true, forKey: .clearDateOfBirth)
                }
                if clearGender == true {
                    try container.encode(true, forKey: .clearGender)
                }
            }
        }
        let dto: UserProfileDTO = try await apiClient.authorizedRequest(
            .updateProfile,
            body: Body(
                displayName: displayName,
                bio: bio,
                avatarR2Key: avatarR2Key,
                dateOfBirth: clearDateOfBirth ? nil : dateOfBirth.map(APIDateParser.formatDay),
                gender: clearGender ? nil : gender?.rawValue,
                showSensitiveContent: showSensitiveContent,
                clearDateOfBirth: clearDateOfBirth ? true : nil,
                clearGender: clearGender ? true : nil
            )
        )
        var profile = dto.toDomain()
        profile.isOwnProfile = true
        return profile
    }

    func updateUsername(_ username: String) async throws -> UserProfile {
        struct Body: Encodable {
            let username: String
        }
        let dto: UserProfileDTO = try await apiClient.authorizedRequest(
            .updateUsername,
            body: Body(username: username)
        )
        var profile = dto.toDomain()
        profile.isOwnProfile = true
        return profile
    }

    func fetchInterests() async throws -> [Interest] {
        let dto: InterestsResponseDTO = try await apiClient.authorizedRequest(.userInterests)
        return dto.interests.map { $0.toDomain() }
    }

    func updateInterests(_ interests: [Interest]) async throws {
        struct Body: Encodable {
            let interests: [InterestDTO]
        }
        let _: UpdateInterestsSuccessDTO = try await apiClient.authorizedRequest(
            .updateInterests,
            body: Body(interests: interests.map(InterestDTO.init(from:)))
        )
    }

    func checkUsernameAvailable(_ username: String) async throws -> Bool {
        let dto: UsernameAvailableDTO = try await apiClient.authorizedRequest(
            .usernameAvailable(username: username)
        )
        return dto.available
    }

    func avatarUploadURL(contentType: String) async throws -> (uploadURL: URL, objectKey: String) {
        struct Body: Encodable {
            let contentType: String
            enum CodingKeys: String, CodingKey { case contentType = "content_type" }
        }
        let dto: AvatarUploadDTO = try await apiClient.authorizedRequest(
            .avatarUploadURL,
            body: Body(contentType: contentType)
        )
        return (dto.uploadURL, dto.objectKey)
    }

    func completeAvatarUpload(objectKey: String) async throws {
        struct Body: Encodable {
            let objectKey: String
            enum CodingKeys: String, CodingKey { case objectKey = "object_key" }
        }
        struct Resp: Decodable {
            let accepted: Bool?
        }
        let _: Resp = try await apiClient.authorizedRequest(
            .avatarUploadComplete,
            body: Body(objectKey: objectKey)
        )
    }

    func fetchTakePosts(userID: String, cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        let response: UserPostsPageDTO = try await fetchCreatorPosts(
            id: userID,
            cursor: cursor,
            limit: limit,
            endpoint: { .userTakePosts(id: $0, cursor: $1, limit: $2, legacy: $3) }
        )
        return (response.items.map { $0.toDomain() }, response.nextCursor)
    }

    func fetchShotPosts(userID: String, cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        let response: UserPostsPageDTO = try await fetchCreatorPosts(
            id: userID,
            cursor: cursor,
            limit: limit,
            endpoint: { .userShotPosts(id: $0, cursor: $1, limit: $2, legacy: $3) }
        )
        return (response.items.map { $0.toDomain() }, response.nextCursor)
    }

    private func fetchCreatorPosts(
        id: String,
        cursor: String?,
        limit: Int,
        endpoint: (String, String?, Int, Bool) -> APIEndpoint
    ) async throws -> UserPostsPageDTO {
        do {
            return try await apiClient.authorizedRequest(endpoint(id, cursor, limit, false))
        } catch let error as APIError {
            if case .notFound = error {
                return try await apiClient.authorizedRequest(endpoint(id, cursor, limit, true))
            }
            throw error
        }
    }

    func follow(userID: String) async throws -> Bool {
        let response: FollowResponseDTO = try await apiClient.authorizedRequest(.followUser(id: userID))
        return response.following
    }

    func unfollow(userID: String) async throws -> Bool {
        let response: FollowResponseDTO = try await apiClient.authorizedRequest(.unfollowUser(id: userID))
        return response.following
    }

    func listFollowers(userID: String, cursor: String?, limit: Int) async throws -> (users: [FollowUser], nextCursor: String?) {
        let response: FollowUsersPageDTO = try await apiClient.authorizedRequest(
            .userFollowers(id: userID, cursor: cursor, limit: limit)
        )
        return (response.users.map { $0.toDomain() }, response.nextCursor)
    }

    func listFollowing(userID: String, cursor: String?, limit: Int) async throws -> (users: [FollowUser], nextCursor: String?) {
        let response: FollowUsersPageDTO = try await apiClient.authorizedRequest(
            .userFollowing(id: userID, cursor: cursor, limit: limit)
        )
        return (response.users.map { $0.toDomain() }, response.nextCursor)
    }

    func searchUsers(query: String, cursor: String?, limit: Int) async throws -> (users: [FollowUser], nextCursor: String?) {
        let response: FollowUsersPageDTO = try await apiClient.authorizedRequest(
            .searchUsers(query: query, cursor: cursor, limit: limit)
        )
        return (response.users.map { $0.toDomain() }, response.nextCursor)
    }

    func searchPosts(query: String, cursor: String?, limit: Int, postType: String? = nil) async throws -> (posts: [Post], nextCursor: String?) {
        let response: SearchPostsPageDTO = try await apiClient.authorizedRequest(
            .searchPosts(query: query, cursor: cursor, limit: limit, postType: postType)
        )
        return (response.items.map { $0.toDomain() }, response.nextCursor)
    }

    func reportPost(postID: String, reason: String) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
            .reportPost(id: postID),
            body: ReportPostBodyDTO(reason: reason)
        )
    }

    func reportComment(commentID: String, reason: String) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
            .reportComment(commentID: commentID),
            body: ReportPostBodyDTO(reason: reason)
        )
    }

    func fetchReportReasons() async throws -> [ReportReasonItem] {
        let response: ReportReasonsResponseDTO = try await apiClient.authorizedRequest(.reportReasons)
        return response.all.map {
            ReportReasonItem(code: $0.code, title: $0.label, description: $0.description)
        }
    }

    func blockUser(userID: String) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(.blockUser(id: userID))
    }

    func unblockUser(userID: String) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(.unblockUser(id: userID))
    }

    func listBlockedUsers() async throws -> [BlockedUser] {
        let response: BlockedUsersResponseDTO = try await apiClient.authorizedRequest(.listBlocked)
        return response.items.map { $0.toDomain() }
    }

    func recordProfileView(userID: String) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(.recordProfileView(id: userID))
    }
}

final class BookmarksRepository: BookmarksRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchBookmarks(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        let response: BookmarksPageDTO = try await apiClient.authorizedRequest(
            .bookmarks(cursor: cursor, limit: limit)
        )
        return (response.items.map { $0.toDomain() }, response.nextCursor)
    }
}
