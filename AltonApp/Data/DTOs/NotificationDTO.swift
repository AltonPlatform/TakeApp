import Foundation

struct NotificationDTO: Decodable {
    let id: String
    let type: String
    let actorID: String?
    let actorUsername: String?
    let actorDisplayName: String?
    let actorAvatarURL: String?
    let postID: String?
    let commentID: String?
    let postPreview: String?
    let postThumbnailURL: String?
    let commentPreview: String?
    let parentCommentContent: String?
    let createdAt: String?
    let readAt: String?
    let reason: String?
    let canAppeal: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case actorID = "actor_id"
        case actorUsername = "actor_username"
        case actorDisplayName = "actor_display_name"
        case actorAvatarURL = "actor_avatar_url"
        case postID = "post_id"
        case commentID = "comment_id"
        case postPreview = "post_preview"
        case postThumbnailURL = "post_thumbnail_url"
        case commentPreview = "comment_preview"
        case parentCommentContent = "parent_comment_content"
        case createdAt = "created_at"
        case readAt = "read_at"
        case reason
        case canAppeal = "can_appeal"
    }

    func toDomain() -> NotificationItem {
        let kind = NotificationKind(rawValue: type) ?? .like
        return NotificationItem(
            id: id,
            type: kind,
            actorID: actorID,
            actorUsername: actorUsername,
            actorDisplayName: actorDisplayName,
            actorAvatarURL: actorAvatarURL.flatMap(URL.init(string:)),
            postID: postID,
            commentID: commentID,
            postPreview: postPreview,
            postThumbnailURL: postThumbnailURL.flatMap(URL.init(string:)),
            commentPreview: commentPreview,
            parentCommentContent: parentCommentContent,
            createdAt: APIDateParser.parse(createdAt),
            readAt: APIDateParser.parse(readAt),
            reason: reason,
            canAppeal: canAppeal ?? false
        )
    }
}

struct NotificationsResponseDTO: Decodable {
    let notifications: [NotificationDTO]
    let nextCursor: String?
    let unreadCount: Int64?

    enum CodingKeys: String, CodingKey {
        case notifications
        case nextCursor = "next_cursor"
        case unreadCount = "unread_count"
    }
}

struct UnreadCountResponseDTO: Decodable {
    let count: Int64
}

struct AppealCommentResponseDTO: Decodable {
    let success: Bool
    let status: String?
}
