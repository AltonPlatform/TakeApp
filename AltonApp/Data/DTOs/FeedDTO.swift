import Foundation

struct FeedResponseDTO: Decodable {
    let items: [FeedTimelineItemDTO]
    let nextCursor: String?
    let adSlots: [FeedAdSlotDTO]?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case adSlots = "ad_slots"
    }
}

struct FeedAdSlotDTO: Decodable {
    let placementID: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case placementID = "placement_id"
        case position
    }

    func toDomain() -> FeedAdSlot {
        FeedAdSlot(placementID: placementID, position: position)
    }
}

struct FeedTimelineItemDTO: Decodable {
    let kind: String
    let post: PostDTO?
    let comment: CommentDTO?
    let parentPost: ParentPostPreviewDTO?
    let finalScore: Double?
    let userScore: Double?
    let creatorScore: Double?
    let brandScore: Double?
    let repostedByDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case post
        case comment
        case parentPost = "parent_post"
        case finalScore = "final_score"
        case userScore = "user_score"
        case creatorScore = "creator_score"
        case brandScore = "brand_score"
        case repostedByDisplayName = "reposted_by_display_name"
    }

    func toDomain() -> FeedTimelineItem? {
        switch kind {
        case "post":
            guard let post else { return nil }
            return .post(
                FeedItem(
                    post: post.toDomain(),
                    finalScore: finalScore ?? 0,
                    userScore: userScore ?? 0,
                    creatorScore: creatorScore ?? 0,
                    brandScore: brandScore ?? 0,
                    repostedByDisplayName: Self.normalizedRepostName(repostedByDisplayName),
                    quotedParent: parentPost?.toDomain()
                )
            )
        case "reply":
            guard let comment, let parentPost else { return nil }
            return .reply(
                FeedReplyItem(
                    comment: comment.toDomain(),
                    parentPost: parentPost.toDomain()
                )
            )
        default:
            return nil
        }
    }

    private static func normalizedRepostName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ParentPostPreviewDTO: Decodable {
    let id: String
    let creatorID: String
    let creatorUsername: String?
    let creatorDisplayName: String?
    let creatorAvatarURL: String?
    let content: String?
    let thumbnailURL: String?
    let createdAt: String?
    let ageGate: Bool?
    let moderation: PostDTO.ModerationDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case creatorUsername = "creator_username"
        case creatorDisplayName = "creator_display_name"
        case creatorAvatarURL = "creator_avatar_url"
        case content
        case thumbnailURL = "thumbnail_url"
        case createdAt = "created_at"
        case ageGate = "age_gate"
        case moderation
    }

    func toDomain() -> ParentPostPreview {
        ParentPostPreview(
            id: id,
            creatorID: creatorID,
            creatorUsername: creatorUsername,
            creatorDisplayName: creatorDisplayName,
            creatorAvatarURL: creatorAvatarURL.flatMap(URL.init(string:)),
            content: content,
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:)),
            createdAt: APIDateParser.parse(createdAt),
            ageGated: ageGate
                ?? moderation?.ageGate
                ?? (moderation?.action == "publish_age_gated"),
            sensitiveBlur: moderation?.blur ?? false
        )
    }
}

struct FeedItemDTO: Decodable {
    let post: PostDTO
    let finalScore: Double
    let userScore: Double
    let creatorScore: Double
    let brandScore: Double
    let repostedByDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case post
        case finalScore = "final_score"
        case userScore = "user_score"
        case creatorScore = "creator_score"
        case brandScore = "brand_score"
        case repostedByDisplayName = "reposted_by_display_name"
    }

    func toDomain() -> FeedItem {
        let name = repostedByDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return FeedItem(
            post: post.toDomain(),
            finalScore: finalScore,
            userScore: userScore,
            creatorScore: creatorScore,
            brandScore: brandScore,
            repostedByDisplayName: (name?.isEmpty == false) ? name : nil
        )
    }
}
