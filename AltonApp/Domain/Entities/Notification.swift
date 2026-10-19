import Foundation

/// TikTok-style inbox notification category (server-side filter).
enum NotificationCategory: String, Sendable, Hashable, CaseIterable {
    case followers
    case activity
    case system

    var title: String {
        switch self {
        case .followers: return "New followers"
        case .activity: return "Activity"
        case .system: return "System notifications"
        }
    }

    /// Short label for inbox category chips.
    var shortTitle: String {
        switch self {
        case .followers: return "Followers"
        case .activity: return "Activity"
        case .system: return "System"
        }
    }

    var systemImage: String {
        switch self {
        case .followers: return "person.badge.plus.fill"
        case .activity: return "heart.fill"
        case .system: return "bell.badge.fill"
        }
    }
}

enum NotificationKind: String, Sendable, CaseIterable {
    case like
    case comment
    case follow
    case repost
    case mention
    case reply
    case profileView = "profile_view"
    case commentRemoved = "comment_removed"

    var systemImage: String {
        switch self {
        case .like: return "heart.fill"
        case .comment: return "bubble.right.fill"
        case .follow: return "person.fill.badge.plus"
        case .repost: return "arrow.2.squarepath"
        case .mention: return "at"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .profileView: return "eye.fill"
        case .commentRemoved: return "exclamationmark.bubble.fill"
        }
    }

    var badgeColorName: String {
        switch self {
        case .like: return "pink"
        case .comment, .reply: return "blue"
        case .follow, .profileView: return "purple"
        case .repost: return "green"
        case .mention: return "orange"
        case .commentRemoved: return "red"
        }
    }
}

struct NotificationItem: Equatable, Identifiable, Sendable {
    let id: String
    let type: NotificationKind
    let actorID: String?
    let actorUsername: String?
    let actorDisplayName: String?
    let actorAvatarURL: URL?
    let postID: String?
    let commentID: String?
    let postPreview: String?
    let postThumbnailURL: URL?
    let commentPreview: String?
    let parentCommentContent: String?
    let createdAt: Date?
    var readAt: Date?
    let reason: String?
    var canAppeal: Bool

    var isUnread: Bool { readAt == nil }

    var actorResolvedName: String {
        if let actorDisplayName, !actorDisplayName.isEmpty { return actorDisplayName }
        if let actorUsername, !actorUsername.isEmpty { return "@\(actorUsername)" }
        return actorID ?? "Someone"
    }

    var actionText: String {
        switch type {
        case .like: return "liked your post"
        case .comment: return "commented on your post"
        case .follow: return "started following you"
        case .repost: return "reposted your post"
        case .mention: return "mentioned you"
        case .reply: return "replied to your comment"
        case .profileView: return "viewed your profile"
        case .commentRemoved: return "Your comment was removed"
        }
    }
}

struct NotificationPage: Sendable {
    let notifications: [NotificationItem]
    let nextCursor: String?
    let unreadCount: Int
}
