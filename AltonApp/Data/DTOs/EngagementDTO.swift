import Foundation

struct ToggleResponseDTO: Decodable {
    let active: Bool
    let count: Int64
}

struct RepostResponseDTO: Decodable {
    let active: Bool
    let count: Int64
    let repostID: String?

    enum CodingKeys: String, CodingKey {
        case active
        case count
        case repostID = "repost_id"
    }
}

struct ShareResponseDTO: Decodable {
    let shareCount: Int64
    let shareURL: String
    let newlyRecorded: Bool

    enum CodingKeys: String, CodingKey {
        case shareCount = "share_count"
        case shareURL = "share_url"
        case newlyRecorded = "newly_recorded"
    }
}

struct RecordViewResponseDTO: Decodable {
    let accepted: Bool
}

struct CommentDTO: Decodable {
    let id: String
    let postID: String
    let authorID: String
    let authorUsername: String?
    let authorDisplayName: String?
    let authorAvatarURL: String?
    let content: String
    let createdAt: String?
    let showInFeed: Bool?
    let parentCommentID: String?
    let likeCount: Int64?
    let isLiked: Bool?
    let mediaKey: String?
    let thumbnailKey: String?
    let playbackURL: String?
    let thumbnailURL: String?
    let sticker: CommentStickerDTO?
    let gif: CommentGifDTO?
    let canReport: Bool?
    let moderationStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarURL = "author_avatar_url"
        case content
        case createdAt = "created_at"
        case showInFeed = "show_in_feed"
        case parentCommentID = "parent_comment_id"
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case mediaKey = "media_key"
        case thumbnailKey = "thumbnail_key"
        case playbackURL = "playback_url"
        case thumbnailURL = "thumbnail_url"
        case sticker
        case gif
        case canReport = "can_report"
        case moderationStatus = "moderation_status"
    }

    func toDomain() -> Comment {
        Comment(
            id: id,
            postID: postID,
            authorID: authorID,
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorAvatarURL: authorAvatarURL.flatMap(URL.init(string:)),
            content: content,
            createdAt: APIDateParser.parse(createdAt),
            showInFeed: showInFeed ?? true,
            parentCommentID: parentCommentID,
            mediaKey: mediaKey,
            thumbnailKey: thumbnailKey,
            imageURLs: Self.imageURLs(mediaKey: mediaKey, playbackURL: playbackURL, thumbnailURL: thumbnailURL),
            sticker: sticker?.toDomain(),
            gif: gif?.toDomain(),
            likeCount: Int(likeCount ?? 0),
            isLiked: isLiked ?? false,
            canReport: canReport ?? true,
            moderationStatus: CommentModerationStatus(rawValue: moderationStatus ?? "ok")
        )
    }

    /// Same CSV resolution as take posts.
    private static func imageURLs(
        mediaKey: String?,
        playbackURL: String?,
        thumbnailURL: String?
    ) -> [URL] {
        if let playbackURL, !playbackURL.isEmpty {
            return playbackURL
                .split(separator: ",")
                .compactMap { URL(string: String($0).trimmingCharacters(in: .whitespaces)) }
        }

        if let mediaKey, !mediaKey.isEmpty {
            return mediaKey
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .compactMap { key in
                    if key.hasPrefix("http") {
                        return URL(string: key)
                    }
                    return AppEnvironment.current.playbackURL(forObjectKey: key)
                }
        }

        if let thumbnailURL, !thumbnailURL.isEmpty {
            return [URL(string: thumbnailURL)].compactMap { $0 }
        }

        return []
    }
}

struct CommentStickerDTO: Decodable {
    let id: String
    let url: String?
    let thumbURL: String?
    let packID: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case thumbURL = "thumb_url"
        case packID = "pack_id"
        case width
        case height
    }

    func toDomain() -> CommentSticker? {
        guard let urlString = url, let resolved = URL(string: urlString) else { return nil }
        return CommentSticker(
            stickerID: id,
            packID: packID,
            url: resolved,
            thumbURL: thumbURL.flatMap(URL.init(string:)),
            width: width,
            height: height
        )
    }
}

struct CommentGifDTO: Decodable {
    let id: String
    let url: String?
    let thumbURL: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case thumbURL = "thumb_url"
        case width
        case height
    }

    func toDomain() -> CommentGif? {
        guard let urlString = url, let resolved = URL(string: urlString) else { return nil }
        return CommentGif(
            id: id,
            url: resolved,
            thumbURL: thumbURL.flatMap(URL.init(string:)),
            width: width,
            height: height
        )
    }
}

struct StickerPackSummaryDTO: Decodable {
    let id: String
    let slug: String
    let title: String
    let coverURL: String?
    let stickerCount: Int?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, slug, title
        case coverURL = "cover_url"
        case stickerCount = "sticker_count"
        case sortOrder = "sort_order"
    }

    func toDomain() -> StickerPackSummary {
        StickerPackSummary(
            id: id,
            slug: slug,
            title: title,
            coverURL: coverURL.flatMap(URL.init(string:)),
            stickerCount: stickerCount ?? 0,
            sortOrder: sortOrder ?? 0
        )
    }
}

struct StickerPacksResponseDTO: Decodable {
    let packs: [StickerPackSummaryDTO]
}

struct StickerDTO: Decodable {
    let id: String
    let emojiHint: String?
    let url: String
    let thumbURL: String?
    let width: Int?
    let height: Int?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case emojiHint = "emoji_hint"
        case url
        case thumbURL = "thumb_url"
        case width, height
        case sortOrder = "sort_order"
    }
}

struct StickerPackDetailDTO: Decodable {
    let id: String
    let slug: String
    let title: String
    let coverURL: String?
    let stickerCount: Int?
    let sortOrder: Int?
    let stickers: [StickerDTO]

    enum CodingKeys: String, CodingKey {
        case id, slug, title, stickers
        case coverURL = "cover_url"
        case stickerCount = "sticker_count"
        case sortOrder = "sort_order"
    }

    func toDomain() -> StickerPackDetail? {
        let mapped: [Sticker] = stickers.compactMap { dto in
            guard let url = URL(string: dto.url) else { return nil }
            let thumb = dto.thumbURL.flatMap(URL.init(string:)) ?? url
            return Sticker(
                id: dto.id,
                packID: id,
                emojiHint: dto.emojiHint,
                url: url,
                thumbURL: thumb,
                width: dto.width,
                height: dto.height,
                sortOrder: dto.sortOrder ?? 0
            )
        }
        return StickerPackDetail(
            id: id,
            slug: slug,
            title: title,
            coverURL: coverURL.flatMap(URL.init(string:)),
            stickerCount: stickerCount ?? mapped.count,
            sortOrder: sortOrder ?? 0,
            stickers: mapped
        )
    }
}

struct CommentsResponseDTO: Decodable {
    let comments: [CommentDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case comments
        case nextCursor = "next_cursor"
    }
}

struct AddCommentRequestDTO: Encodable {
    let content: String
    let showInFeed: Bool
    let parentCommentID: String?
    let mediaKey: String?
    let imageKey: String?
    let stickerID: String?
    let pendingMedia: Bool?
    let klipyGifID: String?
    let gifSourceURL: String?
    let gifContentType: String?
    let gifWidth: Int?
    let gifHeight: Int?

    enum CodingKeys: String, CodingKey {
        case content
        case showInFeed = "show_in_feed"
        case parentCommentID = "parent_comment_id"
        case mediaKey = "media_key"
        case imageKey = "image_key"
        case stickerID = "sticker_id"
        case pendingMedia = "pending_media"
        case klipyGifID = "klipy_gif_id"
        case gifSourceURL = "gif_source_url"
        case gifContentType = "gif_content_type"
        case gifWidth = "gif_width"
        case gifHeight = "gif_height"
    }

    init(
        content: String,
        showInFeed: Bool,
        parentCommentID: String?,
        mediaKey: String? = nil,
        imageKey: String? = nil,
        stickerID: String? = nil,
        pendingMedia: Bool = false,
        pendingGif: PendingCommentGif? = nil
    ) {
        self.content = content
        self.showInFeed = showInFeed
        self.parentCommentID = parentCommentID
        self.mediaKey = mediaKey
        self.imageKey = imageKey
        self.stickerID = stickerID
        self.pendingMedia = pendingMedia ? true : nil
        self.klipyGifID = pendingGif?.klipyGifID
        self.gifSourceURL = pendingGif?.sourceURL.absoluteString
        self.gifContentType = pendingGif?.contentType
        self.gifWidth = pendingGif?.width
        self.gifHeight = pendingGif?.height
    }
}

struct ShareRequestDTO: Encodable {
    let channel: String
}

struct RecordViewRequestDTO: Encodable {
    let source: String
    let watchTimeMs: Int

    enum CodingKeys: String, CodingKey {
        case source
        case watchTimeMs = "watch_time_ms"
    }
}

struct PostAnalyticsResponseDTO: Decodable {
    let totalViews: Int64
    let uniqueVisitors: Int64
    let avgWatchTimeMs: Int64
    let repeatViews: Int64
    let sourceBreakdown: [SourceBreakdownDTO]
    let daily: [DailyViewsDTO]
    let monetizableViews: Int64
    let estimatedEarningsUsd: Double
    let earningsPer1kViews: Double
    let adjacentAdImpressions: Int64
    let creatorSharePct: Double
    let likeCount: Int64
    let commentCount: Int64
    let shareCount: Int64
    let repostCount: Int64
    let profileViews: Int64
    let followersGained: Int64
    let ageBreakdown: [AudienceBucketDTO]
    let genderBreakdown: [AudienceBucketDTO]

    enum CodingKeys: String, CodingKey {
        case totalViews = "total_views"
        case uniqueVisitors = "unique_visitors"
        case avgWatchTimeMs = "avg_watch_time_ms"
        case repeatViews = "repeat_views"
        case sourceBreakdown = "source_breakdown"
        case daily
        case monetizableViews = "monetizable_views"
        case estimatedEarningsUsd = "estimated_earnings_usd"
        case earningsPer1kViews = "earnings_per_1k_views"
        case adjacentAdImpressions = "adjacent_ad_impressions"
        case creatorSharePct = "creator_share_pct"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
        case repostCount = "repost_count"
        case profileViews = "profile_views"
        case followersGained = "followers_gained"
        case ageBreakdown = "age_breakdown"
        case genderBreakdown = "gender_breakdown"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalViews = try container.decodeIfPresent(Int64.self, forKey: .totalViews) ?? 0
        uniqueVisitors = try container.decodeIfPresent(Int64.self, forKey: .uniqueVisitors) ?? 0
        avgWatchTimeMs = try container.decodeIfPresent(Int64.self, forKey: .avgWatchTimeMs) ?? 0
        repeatViews = try container.decodeIfPresent(Int64.self, forKey: .repeatViews) ?? 0
        sourceBreakdown = try container.decodeIfPresent([SourceBreakdownDTO].self, forKey: .sourceBreakdown) ?? []
        daily = try container.decodeIfPresent([DailyViewsDTO].self, forKey: .daily) ?? []
        monetizableViews = try container.decodeIfPresent(Int64.self, forKey: .monetizableViews) ?? 0
        estimatedEarningsUsd = try container.decodeIfPresent(Double.self, forKey: .estimatedEarningsUsd) ?? 0
        earningsPer1kViews = try container.decodeIfPresent(Double.self, forKey: .earningsPer1kViews) ?? 0
        adjacentAdImpressions = try container.decodeIfPresent(Int64.self, forKey: .adjacentAdImpressions) ?? 0
        creatorSharePct = try container.decodeIfPresent(Double.self, forKey: .creatorSharePct) ?? 70
        likeCount = try container.decodeIfPresent(Int64.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int64.self, forKey: .commentCount) ?? 0
        shareCount = try container.decodeIfPresent(Int64.self, forKey: .shareCount) ?? 0
        repostCount = try container.decodeIfPresent(Int64.self, forKey: .repostCount) ?? 0
        profileViews = try container.decodeIfPresent(Int64.self, forKey: .profileViews) ?? 0
        followersGained = try container.decodeIfPresent(Int64.self, forKey: .followersGained) ?? 0
        ageBreakdown = try container.decodeIfPresent([AudienceBucketDTO].self, forKey: .ageBreakdown) ?? []
        genderBreakdown = try container.decodeIfPresent([AudienceBucketDTO].self, forKey: .genderBreakdown) ?? []
    }

    func toDomain() -> PostAnalytics {
        PostAnalytics(
            totalViews: Int(totalViews),
            uniqueVisitors: Int(uniqueVisitors),
            avgWatchTimeMs: Int(avgWatchTimeMs),
            repeatViews: Int(repeatViews),
            sourceBreakdown: sourceBreakdown.map { $0.toDomain() },
            daily: daily.map { $0.toDomain() },
            monetizableViews: Int(monetizableViews),
            estimatedEarningsUsd: estimatedEarningsUsd,
            earningsPer1kViews: earningsPer1kViews,
            adjacentAdImpressions: Int(adjacentAdImpressions),
            creatorSharePct: creatorSharePct,
            likeCount: Int(likeCount),
            commentCount: Int(commentCount),
            shareCount: Int(shareCount),
            repostCount: Int(repostCount),
            profileViews: Int(profileViews),
            followersGained: Int(followersGained),
            ageBreakdown: ageBreakdown.map { $0.toDomain() },
            genderBreakdown: genderBreakdown.map { $0.toDomain() }
        )
    }
}

struct AudienceBucketDTO: Decodable {
    let label: String
    let count: Int64

    func toDomain() -> AudienceBucket {
        AudienceBucket(label: label, count: Int(count))
    }
}

struct SourceBreakdownDTO: Decodable {
    let source: String
    let count: Int64

    func toDomain() -> SourceBreakdown {
        SourceBreakdown(source: source, count: Int(count))
    }
}

struct DailyViewsDTO: Decodable {
    let date: String
    let totalViews: Int64
    let uniqueVisitors: Int64
    let monetizableViews: Int64
    let likes: Int64
    let comments: Int64
    let shares: Int64
    let reposts: Int64

    enum CodingKeys: String, CodingKey {
        case date
        case totalViews = "total_views"
        case uniqueVisitors = "unique_visitors"
        case monetizableViews = "monetizable_views"
        case likes
        case comments
        case shares
        case reposts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        totalViews = try container.decodeIfPresent(Int64.self, forKey: .totalViews) ?? 0
        uniqueVisitors = try container.decodeIfPresent(Int64.self, forKey: .uniqueVisitors) ?? 0
        monetizableViews = try container.decodeIfPresent(Int64.self, forKey: .monetizableViews) ?? 0
        likes = try container.decodeIfPresent(Int64.self, forKey: .likes) ?? 0
        comments = try container.decodeIfPresent(Int64.self, forKey: .comments) ?? 0
        shares = try container.decodeIfPresent(Int64.self, forKey: .shares) ?? 0
        reposts = try container.decodeIfPresent(Int64.self, forKey: .reposts) ?? 0
    }

    func toDomain() -> DailyViews {
        DailyViews(
            date: date,
            totalViews: Int(totalViews),
            uniqueVisitors: Int(uniqueVisitors),
            monetizableViews: Int(monetizableViews),
            likes: Int(likes),
            comments: Int(comments),
            shares: Int(shares),
            reposts: Int(reposts)
        )
    }
}

struct DeleteCommentResponseDTO: Decodable {
    let success: Bool
}

struct ShareUrlResponseDTO: Decodable {
    let shareURL: String

    enum CodingKeys: String, CodingKey {
        case shareURL = "share_url"
    }
}

struct PostActivityResponseDTO: Decodable {
    let likeCount: Int64
    let repostCount: Int64
    let commentCount: Int64
    let shareCount: Int64

    enum CodingKeys: String, CodingKey {
        case likeCount = "like_count"
        case repostCount = "repost_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
    }

    func toDomain() -> PostActivity {
        PostActivity(
            likeCount: Int(likeCount),
            repostCount: Int(repostCount),
            commentCount: Int(commentCount),
            shareCount: Int(shareCount)
        )
    }
}

struct PostLikerDTO: Decodable {
    let userID: String
    let username: String
    let displayName: String
    let likedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case likedAt = "liked_at"
    }

    func toDomain() -> PostLiker {
        PostLiker(
            userID: userID,
            username: username,
            displayName: displayName,
            likedAt: APIDateParser.parse(likedAt)
        )
    }
}

struct PostLikersResponseDTO: Decodable {
    let likers: [PostLikerDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case likers
        case nextCursor = "next_cursor"
    }
}
