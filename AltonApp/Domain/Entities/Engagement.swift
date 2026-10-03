import Foundation

enum CommentModerationStatus: String, Codable, Sendable {
    case ok
    case inReview = "in_review"
    case removed
    case underAppeal = "under_appeal"

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "ok": self = .ok
        case "in_review": self = .inReview
        case "removed": self = .removed
        case "under_appeal": self = .underAppeal
        default: self = .ok
        }
    }
}

struct Comment: Equatable, Identifiable, Sendable {
    let id: String
    let postID: String
    let authorID: String
    let authorUsername: String?
    let authorDisplayName: String?
    let authorAvatarURL: URL?
    let content: String
    let createdAt: Date?
    let showInFeed: Bool
    let parentCommentID: String?
    let mediaKey: String?
    let thumbnailKey: String?
    let imageURLs: [URL]
    let sticker: CommentSticker?
    let gif: CommentGif?
    var likeCount: Int
    var isLiked: Bool
    let canReport: Bool
    let moderationStatus: CommentModerationStatus

    var resolvedDisplayName: String {
        if let authorDisplayName, !authorDisplayName.isEmpty {
            return authorDisplayName
        }
        if let authorUsername, !authorUsername.isEmpty {
            return "@\(authorUsername)"
        }
        return authorID
    }

    var atUsername: String? {
        guard let authorUsername, !authorUsername.isEmpty else { return nil }
        return "@\(authorUsername)"
    }

    func resolvedAuthorAvatarURL(currentUser: User?) -> URL? {
        if let authorAvatarURL {
            return authorAvatarURL
        }
        if let currentUser, authorID == currentUser.id {
            return currentUser.avatarURL
        }
        return nil
    }

    func authorAsUser(currentUser: User? = nil) -> User {
        User(
            id: authorID,
            username: authorUsername ?? "",
            displayName: resolvedDisplayName,
            bio: nil,
            avatarURL: resolvedAuthorAvatarURL(currentUser: currentUser),
            suiWallet: nil,
            createdAt: nil
        )
    }

    init(
        id: String,
        postID: String,
        authorID: String,
        authorUsername: String?,
        authorDisplayName: String?,
        authorAvatarURL: URL?,
        content: String,
        createdAt: Date?,
        showInFeed: Bool,
        parentCommentID: String?,
        mediaKey: String?,
        thumbnailKey: String?,
        imageURLs: [URL],
        sticker: CommentSticker?,
        gif: CommentGif?,
        likeCount: Int,
        isLiked: Bool,
        canReport: Bool = true,
        moderationStatus: CommentModerationStatus = .ok
    ) {
        self.id = id
        self.postID = postID
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorAvatarURL = authorAvatarURL
        self.content = content
        self.createdAt = createdAt
        self.showInFeed = showInFeed
        self.parentCommentID = parentCommentID
        self.mediaKey = mediaKey
        self.thumbnailKey = thumbnailKey
        self.imageURLs = imageURLs
        self.sticker = sticker
        self.gif = gif
        self.likeCount = likeCount
        self.isLiked = isLiked
        self.canReport = canReport
        self.moderationStatus = moderationStatus
    }

    func fillingAuthorAvatar(_ url: URL?) -> Comment {
        guard authorAvatarURL == nil, let url else { return self }
        return Comment(
            id: id,
            postID: postID,
            authorID: authorID,
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorAvatarURL: url,
            content: content,
            createdAt: createdAt,
            showInFeed: showInFeed,
            parentCommentID: parentCommentID,
            mediaKey: mediaKey,
            thumbnailKey: thumbnailKey,
            imageURLs: imageURLs,
            sticker: sticker,
            gif: gif,
            likeCount: likeCount,
            isLiked: isLiked,
            canReport: canReport,
            moderationStatus: moderationStatus
        )
    }
}

struct CommentSticker: Equatable, Identifiable, Sendable {
    var id: String { stickerID }

    let stickerID: String
    let packID: String?
    let url: URL
    let thumbURL: URL?
    let width: Int?
    let height: Int?
}

struct CommentGif: Equatable, Identifiable, Sendable {
    let id: String
    let url: URL
    let thumbURL: URL?
    let width: Int?
    let height: Int?
}

/// Klipy metadata sent on first ingest. The server stores our copy and returns `CommentGif`.
struct PendingCommentGif: Equatable, Sendable {
    let klipyGifID: String
    let sourceURL: URL
    let contentType: String
    let width: Int
    let height: Int
}

struct StickerPackSummary: Equatable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let coverURL: URL?
    let stickerCount: Int
    let sortOrder: Int
}

struct Sticker: Equatable, Identifiable, Sendable {
    let id: String
    let packID: String
    let emojiHint: String?
    let url: URL
    let thumbURL: URL
    let width: Int?
    let height: Int?
    let sortOrder: Int
}

struct StickerPackDetail: Equatable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let coverURL: URL?
    let stickerCount: Int
    let sortOrder: Int
    let stickers: [Sticker]
}

struct ParentPostPreview: Equatable, Sendable {
    let id: String
    let creatorID: String
    let creatorUsername: String?
    let creatorDisplayName: String?
    let creatorAvatarURL: URL?
    let content: String?
    let thumbnailURL: URL?
    let createdAt: Date?
    let ageGated: Bool
    let sensitiveBlur: Bool

    init(
        id: String,
        creatorID: String,
        creatorUsername: String?,
        creatorDisplayName: String?,
        creatorAvatarURL: URL?,
        content: String?,
        thumbnailURL: URL?,
        createdAt: Date?,
        ageGated: Bool = false,
        sensitiveBlur: Bool = false
    ) {
        self.id = id
        self.creatorID = creatorID
        self.creatorUsername = creatorUsername
        self.creatorDisplayName = creatorDisplayName
        self.creatorAvatarURL = creatorAvatarURL
        self.content = content
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
        self.ageGated = ageGated
        self.sensitiveBlur = sensitiveBlur
    }
}

struct FeedReplyItem: Equatable, Identifiable, Sendable {
    var id: String { comment.id }

    let comment: Comment
    let parentPost: ParentPostPreview
}

struct PostLiker: Equatable, Identifiable, Sendable {
    var id: String { userID }

    let userID: String
    let username: String
    let displayName: String
    let likedAt: Date?
}

struct PostLikerPage: Sendable {
    let likers: [PostLiker]
    let nextCursor: String?
}

struct PostActivity: Equatable, Sendable {
    let likeCount: Int
    let repostCount: Int
    let commentCount: Int
    let shareCount: Int
}

struct CommentPage: Sendable {
    let comments: [Comment]
    let nextCursor: String?
}

enum ViewSource: String, Sendable, CaseIterable {
    case feed
    case profile
    case search
    case internalLink = "internal_link"
    case direct
    case recommendation
    case hashtag
    case mention
    case adAdjacent = "ad_adjacent"
}

struct SourceBreakdown: Equatable, Sendable {
    let source: String
    let count: Int
}

struct DailyViews: Equatable, Sendable, Identifiable {
    var id: String { date }
    let date: String
    let totalViews: Int
    let uniqueVisitors: Int
    let monetizableViews: Int
    let likes: Int
    let comments: Int
    let shares: Int
    let reposts: Int

    func value(for metric: AnalyticsChartMetric) -> Int {
        switch metric {
        case .views: return totalViews
        case .uniqueViewers: return uniqueVisitors
        case .monetizableViews: return monetizableViews
        case .likes: return likes
        case .replies: return comments
        case .shares: return shares
        case .reposts: return reposts
        }
    }
}

enum AnalyticsChartMetric: String, CaseIterable, Identifiable, Sendable {
    case views
    case uniqueViewers
    case monetizableViews
    case likes
    case replies
    case shares
    case reposts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .views: return "Views"
        case .uniqueViewers: return "Unique viewers"
        case .monetizableViews: return "Monetizable"
        case .likes: return "Likes"
        case .replies: return "Replies"
        case .shares: return "Shares"
        case .reposts: return "Reposts"
        }
    }
}

struct PostAnalytics: Equatable, Sendable {
    let totalViews: Int
    let uniqueVisitors: Int
    let avgWatchTimeMs: Int
    let repeatViews: Int
    let sourceBreakdown: [SourceBreakdown]
    let daily: [DailyViews]
    let monetizableViews: Int
    let estimatedEarningsUsd: Double
    let earningsPer1kViews: Double
    let adjacentAdImpressions: Int
    let creatorSharePct: Double
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let repostCount: Int
    let profileViews: Int
    let followersGained: Int
    let ageBreakdown: [AudienceBucket]
    let genderBreakdown: [AudienceBucket]

    /// Engagement rates are relative to unique viewers (not total views).
    var likeRate: Double { rate(likeCount) }
    var replyRate: Double { rate(commentCount) }
    var shareRate: Double { rate(shareCount) }
    var repostRate: Double { rate(repostCount) }

    private func rate(_ count: Int) -> Double {
        guard uniqueVisitors > 0 else { return 0 }
        return Double(count) / Double(uniqueVisitors)
    }
}

struct AudienceBucket: Equatable, Sendable, Identifiable {
    var id: String { label }
    let label: String
    let count: Int
}

struct ToggleResult: Sendable {
    let active: Bool
    let count: Int
}

struct RepostResult: Sendable {
    let active: Bool
    let count: Int
    let repostID: String?
}

struct ShareResult: Sendable {
    let shareCount: Int
    let shareURL: URL
    let newlyRecorded: Bool
}

struct RecordViewResult: Sendable {
    let accepted: Bool
}
