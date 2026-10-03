import Foundation

enum APIEndpoint {
    case refresh
    case feed(cursor: String?, limit: Int, mode: String?)
    case createPost
    case post(id: String)
    case updatePost(id: String)
    case deletePost(id: String)
    case publishPost(id: String)
    case schedulePost(id: String)
    case drafts(cursor: String?, limit: Int)
    case scheduled(cursor: String?, limit: Int)
    case uploadURL(postID: String)
    case uploadComplete(postID: String)
    case toggleLike(postID: String)
    case toggleBookmark(postID: String)
    case toggleRepost(postID: String)
    case recordShare(postID: String)
    case shareURL(postID: String)
    case recordView(postID: String)
    case comments(postID: String, cursor: String?, limit: Int)
    case addComment(postID: String)
    case comment(id: String)
    case commentUploadURL(commentID: String)
    case commentUploadComplete(commentID: String)
    case commentLike(id: String)
    case appealComment(id: String)
    case deleteComment(commentID: String)
    case postActivity(postID: String)
    case postLikers(postID: String, cursor: String?, limit: Int)
    case postAnalytics(postID: String, from: String?, to: String?)
    case reportPost(id: String)
    case reportComment(commentID: String)
    case reportReasons
    case bookmarks(cursor: String?, limit: Int)
    case currentUserProfile
    case userProfile(id: String)
    case userByUsername(String)
    case updateProfile
    case updateUsername
    case userInterests
    case updateInterests
    case usernameAvailable(username: String)
    case avatarUploadURL
    case userTakePosts(id: String, cursor: String?, limit: Int, legacy: Bool = false)
    case userShotPosts(id: String, cursor: String?, limit: Int, legacy: Bool = false)
    case followUser(id: String)
    case unfollowUser(id: String)
    case userFollowers(id: String, cursor: String?, limit: Int)
    case userFollowing(id: String, cursor: String?, limit: Int)
    case blockUser(id: String)
    case unblockUser(id: String)
    case listBlocked
    case searchUsers(query: String, cursor: String?, limit: Int)
    case searchPosts(query: String, cursor: String?, limit: Int, postType: String? = nil)
    case searchHashtag(tag: String, cursor: String?, limit: Int)
    case registerDevice
    case unregisterDevice
    case notifications(cursor: String?, limit: Int, window: Int)
    case markAllNotificationsRead
    case markNotificationRead(id: String)
    case unreadNotificationCount
    case creatorOverview(from: String?, to: String?)
    case creatorBalance
    case requestPayout
    case listPayouts(cursor: String?, limit: Int)
    case adPlacements(placement: String?)
    case recordAdImpression
    case recordAdClick
    case recordAdRevenue
    case monetizationConfig
    case startSession
    case endSession
    case recordActivity
    case recordProfileView(id: String)
    case updateAttConsent
    case createPoll(postID: String)
    case votePoll(id: String)
    case getPoll(postID: String)
    case linkPreview(url: String)
    case stickerPacks
    case stickerPack(id: String)

    private static let resourceIDPattern = #"^[A-Za-z0-9_-]{1,64}$"#

    static func validateResourceID(_ id: String) throws {
        guard let range = id.range(of: resourceIDPattern, options: .regularExpression),
              range.lowerBound == id.startIndex,
              range.upperBound == id.endIndex else {
            throw APIError.validation("Invalid resource ID.")
        }
    }

    func url(baseURL: URL) throws -> URL {
        switch self {
        case .refresh:
            return baseURL.appending(path: "auth/refresh")
        case .feed(let cursor, let limit, let mode):
            var components = URLComponents(url: baseURL.appending(path: "feed"), resolvingAgainstBaseURL: false)
            var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
            if let cursor, !cursor.isEmpty {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            if let mode, !mode.isEmpty {
                queryItems.append(URLQueryItem(name: "mode", value: mode))
            }
            components?.queryItems = queryItems
            return try requireURL(components?.url)
        case .createPost:
            return baseURL.appending(path: "posts")
        case .post(let id), .updatePost(let id), .deletePost(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "posts/\(id)")
        case .publishPost(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "posts/\(id)/publish")
        case .schedulePost(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "posts/\(id)/schedule")
        case .drafts(let cursor, let limit):
            return try listURL(path: "posts/drafts", cursor: cursor, limit: limit, baseURL: baseURL)
        case .scheduled(let cursor, let limit):
            return try listURL(path: "posts/scheduled", cursor: cursor, limit: limit, baseURL: baseURL)
        case .uploadURL(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/upload-url")
        case .uploadComplete(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/upload-complete")
        case .toggleLike(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/like")
        case .toggleBookmark(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/bookmark")
        case .toggleRepost(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/repost")
        case .recordShare(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/share")
        case .shareURL(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/share-url")
        case .recordView(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/view")
        case .comments(let postID, let cursor, let limit):
            try Self.validateResourceID(postID)
            return try listURL(path: "posts/\(postID)/comments", cursor: cursor, limit: limit, baseURL: baseURL)
        case .addComment(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/comments")
        case .comment(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "comments/\(id)")
        case .commentUploadURL(let commentID):
            try Self.validateResourceID(commentID)
            return baseURL.appending(path: "comments/\(commentID)/upload-url")
        case .commentUploadComplete(let commentID):
            try Self.validateResourceID(commentID)
            return baseURL.appending(path: "comments/\(commentID)/upload-complete")
        case .commentLike(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "comments/\(id)/like")
        case .appealComment(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "comments/\(id)/appeal")
        case .deleteComment(let commentID):
            try Self.validateResourceID(commentID)
            return baseURL.appending(path: "comments/\(commentID)")
        case .postActivity(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/activity")
        case .postLikers(let postID, let cursor, let limit):
            try Self.validateResourceID(postID)
            return try listURL(path: "posts/\(postID)/likes", cursor: cursor, limit: limit, baseURL: baseURL)
        case .postAnalytics(let postID, let from, let to):
            try Self.validateResourceID(postID)
            var components = URLComponents(
                url: baseURL.appending(path: "posts/\(postID)/analytics"),
                resolvingAgainstBaseURL: false
            )
            var queryItems: [URLQueryItem] = []
            if let from, !from.isEmpty {
                queryItems.append(URLQueryItem(name: "from", value: from))
            }
            if let to, !to.isEmpty {
                queryItems.append(URLQueryItem(name: "to", value: to))
            }
            if !queryItems.isEmpty {
                components?.queryItems = queryItems
            }
            return try requireURL(components?.url)
        case .reportPost(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "posts/\(id)/report")
        case .reportComment(let commentID):
            try Self.validateResourceID(commentID)
            return baseURL.appending(path: "comments/\(commentID)/report")
        case .reportReasons:
            return baseURL.appending(path: "moderation/report-reasons")
        case .bookmarks(let cursor, let limit):
            return try listURL(path: "bookmarks", cursor: cursor, limit: limit, baseURL: baseURL)
        case .currentUserProfile:
            return baseURL.appending(path: "users/me")
        case .userProfile(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "users/\(id)")
        case .userByUsername(let username):
            let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
            return baseURL.appending(path: "users/by-username/\(encoded)")
        case .updateProfile:
            return baseURL.appending(path: "users/me")
        case .updateUsername:
            return baseURL.appending(path: "users/me/username")
        case .userInterests, .updateInterests:
            return baseURL.appending(path: "users/me/interests")
        case .usernameAvailable(let username):
            var components = URLComponents(
                url: baseURL.appending(path: "username/available"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "username", value: username)]
            return try requireURL(components?.url)
        case .avatarUploadURL:
            return baseURL.appending(path: "users/me/avatar")
        case .userTakePosts(let id, let cursor, let limit, let legacy):
            try Self.validateResourceID(id)
            let takePath = legacy ? "users/\(id)/posts/threads" : "users/\(id)/posts/takes"
            return try listURL(path: takePath, cursor: cursor, limit: limit, baseURL: baseURL)
        case .userShotPosts(let id, let cursor, let limit, let legacy):
            try Self.validateResourceID(id)
            let shotPath = legacy ? "users/\(id)/posts/videos" : "users/\(id)/posts/shots"
            return try listURL(path: shotPath, cursor: cursor, limit: limit, baseURL: baseURL)
        case .followUser(let id), .unfollowUser(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "users/\(id)/follow")
        case .userFollowers(let id, let cursor, let limit):
            try Self.validateResourceID(id)
            return try listURL(path: "users/\(id)/followers", cursor: cursor, limit: limit, baseURL: baseURL)
        case .userFollowing(let id, let cursor, let limit):
            try Self.validateResourceID(id)
            return try listURL(path: "users/\(id)/following", cursor: cursor, limit: limit, baseURL: baseURL)
        case .blockUser(let id), .unblockUser(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "users/\(id)/block")
        case .listBlocked:
            return baseURL.appending(path: "users/me/blocked")
        case .searchUsers(let query, let cursor, let limit):
            return try searchURL(path: "search/users", query: query, cursor: cursor, limit: limit, postType: nil, baseURL: baseURL)
        case .searchPosts(let query, let cursor, let limit, let postType):
            return try searchURL(path: "search/posts", query: query, cursor: cursor, limit: limit, postType: postType, baseURL: baseURL)
        case .searchHashtag(let tag, let cursor, let limit):
            let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
            return try listURL(path: "search/hashtags/\(encoded)", cursor: cursor, limit: limit, baseURL: baseURL)
        case .registerDevice, .unregisterDevice:
            return baseURL.appending(path: "devices/register")
        case .notifications(let cursor, let limit, let window):
            var components = URLComponents(
                url: baseURL.appending(path: "me/notifications"),
                resolvingAgainstBaseURL: false
            )
            var queryItems = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "window", value: String(window))
            ]
            if let cursor, !cursor.isEmpty {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            components?.queryItems = queryItems
            return try requireURL(components?.url)
        case .markAllNotificationsRead:
            return baseURL.appending(path: "me/notifications")
        case .markNotificationRead(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "me/notifications/\(id)/read")
        case .unreadNotificationCount:
            return baseURL.appending(path: "me/notifications/unread-count")
        case .creatorOverview(let from, let to):
            var components = URLComponents(
                url: baseURL.appending(path: "creator/overview"),
                resolvingAgainstBaseURL: false
            )
            var queryItems: [URLQueryItem] = []
            if let from, !from.isEmpty {
                queryItems.append(URLQueryItem(name: "from", value: from))
            }
            if let to, !to.isEmpty {
                queryItems.append(URLQueryItem(name: "to", value: to))
            }
            if !queryItems.isEmpty {
                components?.queryItems = queryItems
            }
            return try requireURL(components?.url)
        case .creatorBalance:
            return baseURL.appending(path: "creator/balance")
        case .requestPayout:
            return baseURL.appending(path: "creator/payouts")
        case .listPayouts(let cursor, let limit):
            return try listURL(path: "creator/payouts", cursor: cursor, limit: limit, baseURL: baseURL)
        case .adPlacements(let placement):
            var components = URLComponents(
                url: baseURL.appending(path: "ads/placements"),
                resolvingAgainstBaseURL: false
            )
            if let placement, !placement.isEmpty {
                components?.queryItems = [URLQueryItem(name: "placement", value: placement)]
            }
            return try requireURL(components?.url)
        case .recordAdImpression:
            return baseURL.appending(path: "ads/impressions")
        case .recordAdClick:
            return baseURL.appending(path: "ads/clicks")
        case .recordAdRevenue:
            return baseURL.appending(path: "ads/revenue")
        case .monetizationConfig:
            return baseURL.appending(path: "monetization/config")
        case .startSession:
            return baseURL.appending(path: "sessions/start")
        case .endSession:
            return baseURL.appending(path: "sessions/end")
        case .recordActivity:
            return baseURL.appending(path: "sessions/activity")
        case .recordProfileView(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "users/\(id)/view")
        case .updateAttConsent:
            return baseURL.appending(path: "users/me/att-consent")
        case .createPoll(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/poll")
        case .votePoll(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "polls/\(id)/vote")
        case .getPoll(let postID):
            try Self.validateResourceID(postID)
            return baseURL.appending(path: "posts/\(postID)/poll")
        case .linkPreview(let url):
            var components = URLComponents(
                url: baseURL.appending(path: "link-preview"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "url", value: url)]
            return try requireURL(components?.url)
        case .stickerPacks:
            return baseURL.appending(path: "stickers/packs")
        case .stickerPack(let id):
            try Self.validateResourceID(id)
            return baseURL.appending(path: "stickers/packs/\(id)")
        }
    }

    private func listURL(path: String, cursor: String?, limit: Int, baseURL: URL) throws -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems
        return try requireURL(components?.url)
    }

    private func searchURL(
        path: String,
        query: String,
        cursor: String?,
        limit: Int,
        postType: String?,
        baseURL: URL
    ) throws -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let postType, !postType.isEmpty {
            queryItems.append(URLQueryItem(name: "post_type", value: postType))
        }
        components?.queryItems = queryItems
        return try requireURL(components?.url)
    }

    private func requireURL(_ url: URL?) throws -> URL {
        guard let url else { throw APIError.invalidURL }
        return url
    }

    var method: HTTPMethod {
        switch self {
        case .feed, .comments, .comment, .postAnalytics, .bookmarks, .shareURL, .postActivity, .postLikers,
             .post, .currentUserProfile, .userProfile, .userByUsername, .userTakePosts, .userShotPosts,
             .userFollowers, .userFollowing,
             .searchUsers, .searchPosts, .searchHashtag, .drafts, .scheduled, .listBlocked,
             .creatorOverview, .creatorBalance, .listPayouts, .adPlacements, .monetizationConfig,
             .getPoll, .linkPreview, .usernameAvailable, .notifications, .unreadNotificationCount,
             .stickerPacks, .stickerPack, .reportReasons, .userInterests:
            return .get
        case .updateUsername, .updateInterests:
            return .put
        case .updateProfile, .updatePost:
            return .patch
        case .deleteComment, .unfollowUser, .deletePost, .unblockUser, .unregisterDevice:
            return .delete
        default:
            return .post
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .refresh:
            return false
        default:
            return true
        }
    }
}
