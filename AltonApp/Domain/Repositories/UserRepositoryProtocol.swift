import Foundation

protocol UserRepositoryProtocol: Sendable {
    func fetchCurrentProfile() async throws -> UserProfile
    func fetchProfile(userID: String) async throws -> UserProfile
    func fetchProfileByUsername(_ username: String) async throws -> UserProfile
    func updateProfile(
        displayName: String?,
        bio: String?,
        avatarR2Key: String?,
        dateOfBirth: Date?,
        gender: Gender?,
        showSensitiveContent: Bool?,
        clearDateOfBirth: Bool,
        clearGender: Bool
    ) async throws -> UserProfile
    func updateUsername(_ username: String) async throws -> UserProfile
    func fetchInterests() async throws -> [Interest]
    func updateInterests(_ interests: [Interest]) async throws
    func checkUsernameAvailable(_ username: String) async throws -> Bool
    func avatarUploadURL(contentType: String) async throws -> (uploadURL: URL, objectKey: String)
    func completeAvatarUpload(objectKey: String) async throws
    func fetchTakePosts(userID: String, cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?)
    func fetchShotPosts(userID: String, cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?)
    func follow(userID: String) async throws -> Bool
    func unfollow(userID: String) async throws -> Bool
    func listFollowers(userID: String, cursor: String?, limit: Int) async throws -> (users: [FollowUser], nextCursor: String?)
    func listFollowing(userID: String, cursor: String?, limit: Int) async throws -> (users: [FollowUser], nextCursor: String?)
    func searchUsers(query: String, cursor: String?, limit: Int) async throws -> (users: [FollowUser], nextCursor: String?)
    func searchPosts(query: String, cursor: String?, limit: Int, postType: String?) async throws -> (posts: [Post], nextCursor: String?)
    func reportPost(postID: String, reason: String) async throws
    func reportComment(commentID: String, reason: String) async throws
    func fetchReportReasons() async throws -> [ReportReasonItem]
    func blockUser(userID: String) async throws
    func unblockUser(userID: String) async throws
    func listBlockedUsers() async throws -> [BlockedUser]
    func recordProfileView(userID: String) async throws
}

struct FollowUser: Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    let isFollowing: Bool
}

struct ReportReasonItem: Identifiable, Equatable, Sendable {
    let code: String
    let title: String
    let description: String?

    var id: String { code }
}

protocol BookmarksRepositoryProtocol: Sendable {
    func fetchBookmarks(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?)
}
