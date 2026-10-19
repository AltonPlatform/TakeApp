import Foundation

struct UserUseCase: Sendable {
    private let repository: UserRepositoryProtocol

    init(repository: UserRepositoryProtocol) {
        self.repository = repository
    }

    func loadCurrentProfile() async throws -> UserProfile {
        try await repository.fetchCurrentProfile()
    }

    func loadProfile(userID: String) async throws -> UserProfile {
        try await repository.fetchProfile(userID: userID)
    }

    func loadProfileByUsername(_ username: String) async throws -> UserProfile {
        try await repository.fetchProfileByUsername(username)
    }

    func updateProfile(
        displayName: String? = nil,
        bio: String? = nil,
        avatarR2Key: String? = nil,
        dateOfBirth: Date? = nil,
        gender: Gender? = nil,
        showSensitiveContent: Bool? = nil,
        clearDateOfBirth: Bool = false,
        clearGender: Bool = false
    ) async throws -> UserProfile {
        try await repository.updateProfile(
            displayName: displayName,
            bio: bio,
            avatarR2Key: avatarR2Key,
            dateOfBirth: dateOfBirth,
            gender: gender,
            showSensitiveContent: showSensitiveContent,
            clearDateOfBirth: clearDateOfBirth,
            clearGender: clearGender
        )
    }

    func updateUsername(_ username: String) async throws -> UserProfile {
        try await repository.updateUsername(username)
    }

    func loadInterests() async throws -> [Interest] {
        try await repository.fetchInterests()
    }

    func saveInterests(_ interests: [Interest]) async throws {
        try await repository.updateInterests(interests)
    }

    func checkUsernameAvailable(_ username: String) async throws -> Bool {
        try await repository.checkUsernameAvailable(username)
    }

    func prepareAvatarUpload(contentType: String) async throws -> (uploadURL: URL, objectKey: String) {
        try await repository.avatarUploadURL(contentType: contentType)
    }

    func completeAvatarUpload(objectKey: String) async throws {
        try await repository.completeAvatarUpload(objectKey: objectKey)
    }

    func loadTakePosts(userID: String, cursor: String?, limit: Int = 20) async throws -> (posts: [Post], nextCursor: String?) {
        try await repository.fetchTakePosts(userID: userID, cursor: cursor, limit: limit)
    }

    func loadShotPosts(userID: String, cursor: String?, limit: Int = 20) async throws -> (posts: [Post], nextCursor: String?) {
        try await repository.fetchShotPosts(userID: userID, cursor: cursor, limit: limit)
    }

    func follow(userID: String) async throws -> Bool {
        try await repository.follow(userID: userID)
    }

    func unfollow(userID: String) async throws -> Bool {
        try await repository.unfollow(userID: userID)
    }

    func listFollowers(userID: String, cursor: String? = nil, limit: Int = 20) async throws -> (users: [FollowUser], nextCursor: String?) {
        try await repository.listFollowers(userID: userID, cursor: cursor, limit: limit)
    }

    func listFollowing(userID: String, cursor: String? = nil, limit: Int = 20) async throws -> (users: [FollowUser], nextCursor: String?) {
        try await repository.listFollowing(userID: userID, cursor: cursor, limit: limit)
    }

    func reportPost(postID: String, reason: String) async throws {
        try await repository.reportPost(postID: postID, reason: reason)
    }

    func reportComment(commentID: String, reason: String) async throws {
        try await repository.reportComment(commentID: commentID, reason: reason)
    }

    func fetchReportReasons() async throws -> [ReportReasonItem] {
        try await repository.fetchReportReasons()
    }

    func blockUser(userID: String) async throws {
        try await repository.blockUser(userID: userID)
    }

    func unblockUser(userID: String) async throws {
        try await repository.unblockUser(userID: userID)
    }

    func listBlockedUsers() async throws -> [BlockedUser] {
        try await repository.listBlockedUsers()
    }

    func recordProfileView(userID: String) async throws {
        try await repository.recordProfileView(userID: userID)
    }
}

struct BookmarksUseCase: Sendable {
    private let repository: BookmarksRepositoryProtocol

    init(repository: BookmarksRepositoryProtocol) {
        self.repository = repository
    }

    func loadBookmarks(cursor: String?, limit: Int = 20) async throws -> (posts: [Post], nextCursor: String?) {
        try await repository.fetchBookmarks(cursor: cursor, limit: limit)
    }
}

struct SearchUseCase: Sendable {
    private let repository: UserRepositoryProtocol

    init(repository: UserRepositoryProtocol) {
        self.repository = repository
    }

    func searchUsers(query: String, cursor: String?, limit: Int = 20) async throws -> (users: [FollowUser], nextCursor: String?) {
        try await repository.searchUsers(query: query, cursor: cursor, limit: limit)
    }

    func searchPosts(query: String, cursor: String?, limit: Int = 20, postType: String? = nil) async throws -> (posts: [Post], nextCursor: String?) {
        try await repository.searchPosts(query: query, cursor: cursor, limit: limit, postType: postType)
    }

    func resolveUserID(username: String) async -> String? {
        let query = username
            .trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        do {
            return try await repository.fetchProfileByUsername(query).id
        } catch {
            return nil
        }
    }
}
