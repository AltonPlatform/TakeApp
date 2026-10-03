import Foundation

struct PostDTO: Decodable {
    let id: String
    let creatorID: String
    let creatorUsername: String?
    let creatorDisplayName: String?
    let creatorAvatarURL: String?
    let postType: String
    /// Search payloads may omit status; treat missing as published.
    let status: String?
    let content: String?
    let mediaKey: String?
    let thumbnailKey: String?
    let playbackURL: String?
    let thumbnailURL: String?
    let viewCount: Int64?
    let likeCount: Int64?
    let commentCount: Int64?
    let saveCount: Int64?
    let shareCount: Int64?
    let repostCount: Int64?
    let isLiked: Bool?
    let isBookmarked: Bool?
    let isReposted: Bool?
    let createdAt: String?
    let sensitiveBlur: Bool?
    let moderation: ModerationDTO?
    let canReport: Bool?
    let feedEligible: Bool?
    let subtitlesURL: String?
    let subtitlesLanguage: String?

    struct MediaModerationDTO: Decodable {
        let index: Int?
        let blur: Bool?
        let ageGate: Bool?
        let unknown: Bool?

        enum CodingKeys: String, CodingKey {
            case index
            case blur
            case ageGate = "age_gate"
            case unknown
        }
    }

    struct ModerationDTO: Decodable {
        let action: String?
        let blur: Bool?
        let ageGate: Bool?
        let categories: [String]?
        let media: [MediaModerationDTO]?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case action
            case blur
            case ageGate = "age_gate"
            case categories
            case media
            case reason
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case creatorUsername = "creator_username"
        case creatorDisplayName = "creator_display_name"
        case creatorAvatarURL = "creator_avatar_url"
        case postType = "post_type"
        case status
        case content
        case mediaKey = "media_key"
        case thumbnailKey = "thumbnail_key"
        case playbackURL = "playback_url"
        case thumbnailURL = "thumbnail_url"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case saveCount = "save_count"
        case shareCount = "share_count"
        case repostCount = "repost_count"
        case isLiked = "is_liked"
        case isBookmarked = "is_bookmarked"
        case isReposted = "is_reposted"
        case createdAt = "created_at"
        case sensitiveBlur = "sensitive_blur"
        case moderation
        case canReport = "can_report"
        case feedEligible = "feed_eligible"
        case subtitlesURL = "subtitles_url"
        case subtitlesLanguage = "subtitles_language"
    }

    func toDomain() -> Post {
        let imageURLs = Self.imageURLs(
            postType: postType,
            mediaKey: mediaKey,
            playbackURL: playbackURL,
            thumbnailURL: thumbnailURL
        )
        let resolvedPlaybackURL = Self.resolvePlaybackURL(
            postType: postType,
            playbackURL: playbackURL,
            mediaKey: mediaKey
        )
        let resolvedThumbnailURL = Self.resolveThumbnailURL(
            thumbnailURL: thumbnailURL,
            thumbnailKey: thumbnailKey,
            mediaKey: mediaKey,
            imageURLs: imageURLs
        )

        return Post(
            id: id,
            creatorID: creatorID,
            creatorUsername: creatorUsername,
            creatorDisplayName: creatorDisplayName,
            creatorAvatarURL: creatorAvatarURL.flatMap(URL.init(string:)),
            postType: PostType(rawValue: postType),
            status: PostStatus(rawValue: status ?? "published"),
            content: content,
            mediaKey: mediaKey,
            thumbnailKey: thumbnailKey,
            playbackURL: resolvedPlaybackURL,
            thumbnailURL: resolvedThumbnailURL,
            imageURLs: imageURLs,
            viewCount: Int(viewCount ?? 0),
            likeCount: Int(likeCount ?? 0),
            commentCount: Int(commentCount ?? 0),
            saveCount: Int(saveCount ?? 0),
            shareCount: Int(shareCount ?? 0),
            repostCount: Int(repostCount ?? 0),
            isLiked: isLiked ?? false,
            isBookmarked: isBookmarked ?? false,
            isReposted: isReposted ?? false,
            createdAt: APIDateParser.parse(createdAt),
            sensitiveBlur: moderation?.blur ?? sensitiveBlur ?? false,
            moderationAction: moderation?.action,
            moderationReason: moderation?.reason,
            canReport: canReport ?? true,
            feedEligible: feedEligible ?? true,
            ageGated: moderation?.ageGate
                ?? (moderation?.action == "publish_age_gated"),
            mediaBlurFlags: Self.mediaBlurFlags(moderation: moderation, imageCount: imageURLs.count),
            mediaUnknownFlags: Self.mediaUnknownFlags(moderation: moderation, imageCount: imageURLs.count),
            subtitlesURL: subtitlesURL.flatMap(URL.init(string:)),
            subtitlesLanguage: subtitlesLanguage
        )
    }

    private static func mediaBlurFlags(moderation: ModerationDTO?, imageCount: Int) -> [Bool] {
        guard let media = moderation?.media, !media.isEmpty, imageCount > 0 else { return [] }
        return (0..<imageCount).map { index in
            guard let item = media.first(where: { $0.index == index }) else {
                return true
            }
            return (item.blur ?? false) || (item.unknown ?? false)
        }
    }

    private static func mediaUnknownFlags(moderation: ModerationDTO?, imageCount: Int) -> [Bool] {
        guard let media = moderation?.media, !media.isEmpty, imageCount > 0 else { return [] }
        return (0..<imageCount).map { index in
            guard let item = media.first(where: { $0.index == index }) else {
                return true
            }
            return item.unknown ?? false
        }
    }

    private static func imageURLs(
        postType: String,
        mediaKey: String?,
        playbackURL: String?,
        thumbnailURL: String?
    ) -> [URL] {
        guard postType.lowercased() == "take" else { return [] }

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

    /// Resolves the playback URL, falling back to a client-built URL from `media_key`
    /// when the API omits `playback_url` (matches backend `playback_url` logic).
    private static func resolvePlaybackURL(
        postType: String,
        playbackURL: String?,
        mediaKey: String?
    ) -> URL? {
        if let playbackURL, !playbackURL.isEmpty {
            return URL(string: playbackURL)
        }
        // Take posts may carry comma-separated image keys — not a single video asset.
        guard postType.lowercased() == "shot",
              let mediaKey, !mediaKey.isEmpty, !mediaKey.contains(",") else {
            return nil
        }
        return AppEnvironment.current.playbackURL(forObjectKey: mediaKey)
    }

    /// First usable thumb: API URL, first `thumbnail_key`, or a sibling of the playback key.
    private static func resolveThumbnailURL(
        thumbnailURL: String?,
        thumbnailKey: String?,
        mediaKey: String?,
        imageURLs: [URL]
    ) -> URL? {
        if let thumbnailURL, !thumbnailURL.isEmpty, let url = URL(string: thumbnailURL) {
            return url
        }

        if let firstKey = thumbnailKey?
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            if firstKey.hasPrefix("http"), let url = URL(string: firstKey) {
                return url
            }
            if let url = AppEnvironment.current.playbackURL(forObjectKey: firstKey) {
                return url
            }
        }

        if let firstImage = imageURLs.first,
           let derived = MediaThumbnailURL.derived(fromPlayback: firstImage) {
            return derived
        }

        guard let mediaKey, !mediaKey.isEmpty else { return nil }
        let firstMedia = mediaKey
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let firstMedia else { return nil }
        let playback = firstMedia.hasPrefix("http")
            ? URL(string: firstMedia)
            : AppEnvironment.current.playbackURL(forObjectKey: firstMedia)
        return playback.flatMap { MediaThumbnailURL.derived(fromPlayback: $0) }
    }
}

struct CreatePostRequestDTO: Encodable {
    let postType: String
    let content: String?
    let mediaKey: String?
    let imageKey: String?
    let lat: Double?
    let lon: Double?
    let geoSource: String?
    let aiGeneratedLabel: Bool?

    enum CodingKeys: String, CodingKey {
        case postType = "post_type"
        case content
        case mediaKey = "media_key"
        case imageKey = "image_key"
        case lat
        case lon
        case geoSource = "geo_source"
        case aiGeneratedLabel = "ai_generated_label"
    }
}

struct CreatePostResponseDTO: Decodable {
    let id: String
    let creatorID: String
    let postType: String
    let status: String
    let content: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case postType = "post_type"
        case status
        case content
        case createdAt = "created_at"
    }

    func toDomain() -> Post {
        Post(
            id: id,
            creatorID: creatorID,
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: PostType(rawValue: postType),
            status: PostStatus(rawValue: status),
            content: content,
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: nil,
            imageURLs: [],
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: APIDateParser.parse(createdAt)
        )
    }
}

struct PublishPostResponseDTO: Decodable {
    let id: String
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt = "created_at"
    }
}

struct DeletePostResponseDTO: Decodable {
    let success: Bool
}

struct UploadURLResponseDTO: Decodable {
    let uploadURL: String
    let objectKey: String
    let expiresIn: Int64

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case objectKey = "object_key"
        case expiresIn = "expires_in"
    }
}

struct UploadCompleteResponseDTO: Decodable {
    let postID: String
    let accepted: Bool
    let message: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case accepted
        case message
    }
}

struct UploadURLRequestDTO: Encodable {
    let contentType: String
    let mediaType: String
    let index: Int?

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case mediaType = "media_type"
        case index
    }
}

struct UploadCompleteRequestDTO: Encodable {
    let objectKey: String?
    let mediaType: String?

    enum CodingKeys: String, CodingKey {
        case objectKey = "object_key"
        case mediaType = "media_type"
    }
}
