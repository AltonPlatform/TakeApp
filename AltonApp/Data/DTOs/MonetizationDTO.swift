import Foundation

// MARK: - Earnings / Creator

struct CreatorOverviewResponseDTO: Decodable {
    let totalViews30d: Int64
    let totalWatchTimeMs: Int64
    let monetizableViews: Int64
    let estimatedEarningsUsd: Double
    let creatorSharePct: Double
    let availableBalance: Double
    let pendingPayout: Double
    let sourceBreakdown: [SourceBreakdownDTO]
    let earningsByPost: [CreatorPostEarningsDTO]
    let profileViews: Int64

    enum CodingKeys: String, CodingKey {
        case totalViews30d = "total_views_30d"
        case totalWatchTimeMs = "total_watch_time_ms"
        case monetizableViews = "monetizable_views"
        case estimatedEarningsUsd = "estimated_earnings_usd"
        case creatorSharePct = "creator_share_pct"
        case availableBalance = "available_balance"
        case pendingPayout = "pending_payout"
        case sourceBreakdown = "source_breakdown"
        case earningsByPost = "earnings_by_post"
        case profileViews = "profile_views"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalViews30d = try container.decodeIfPresent(Int64.self, forKey: .totalViews30d) ?? 0
        totalWatchTimeMs = try container.decodeIfPresent(Int64.self, forKey: .totalWatchTimeMs) ?? 0
        monetizableViews = try container.decodeIfPresent(Int64.self, forKey: .monetizableViews) ?? 0
        estimatedEarningsUsd = try container.decodeIfPresent(Double.self, forKey: .estimatedEarningsUsd) ?? 0
        creatorSharePct = try container.decodeIfPresent(Double.self, forKey: .creatorSharePct) ?? 70
        availableBalance = try container.decodeIfPresent(Double.self, forKey: .availableBalance) ?? 0
        pendingPayout = try container.decodeIfPresent(Double.self, forKey: .pendingPayout) ?? 0
        sourceBreakdown = try container.decodeIfPresent([SourceBreakdownDTO].self, forKey: .sourceBreakdown) ?? []
        earningsByPost = try container.decodeIfPresent([CreatorPostEarningsDTO].self, forKey: .earningsByPost) ?? []
        profileViews = try container.decodeIfPresent(Int64.self, forKey: .profileViews) ?? 0
    }

    func toDomain() -> CreatorOverview {
        CreatorOverview(
            totalViews30d: Int(totalViews30d),
            totalWatchTimeMs: Int(totalWatchTimeMs),
            monetizableViews: Int(monetizableViews),
            estimatedEarningsUsd: estimatedEarningsUsd,
            creatorSharePct: creatorSharePct,
            availableBalance: availableBalance,
            pendingPayout: pendingPayout,
            sourceBreakdown: sourceBreakdown.map { $0.toDomain() },
            earningsByPost: earningsByPost.map { $0.toDomain() },
            profileViews: Int(profileViews)
        )
    }
}

struct CreatorPostEarningsDTO: Decodable {
    let postID: String
    let earningsUsd: Double
    let monetizableViews: Int64

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case earningsUsd = "earnings_usd"
        case monetizableViews = "monetizable_views"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        postID = try container.decode(String.self, forKey: .postID)
        earningsUsd = try container.decodeIfPresent(Double.self, forKey: .earningsUsd) ?? 0
        monetizableViews = try container.decodeIfPresent(Int64.self, forKey: .monetizableViews) ?? 0
    }

    func toDomain() -> CreatorPostEarnings {
        CreatorPostEarnings(
            postID: postID,
            earningsUsd: earningsUsd,
            monetizableViews: Int(monetizableViews)
        )
    }
}

struct CreatorBalanceResponseDTO: Decodable {
    let creatorID: String
    let availableUsd: Double
    let pendingUsd: Double
    let lifetimeEarnedUsd: Double
    let minPayoutUsd: Double
    let creatorSharePct: Double

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case availableUsd = "available_usd"
        case pendingUsd = "pending_usd"
        case lifetimeEarnedUsd = "lifetime_earned_usd"
        case minPayoutUsd = "min_payout_usd"
        case creatorSharePct = "creator_share_pct"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatorID = try container.decodeIfPresent(String.self, forKey: .creatorID) ?? ""
        availableUsd = try container.decodeIfPresent(Double.self, forKey: .availableUsd) ?? 0
        pendingUsd = try container.decodeIfPresent(Double.self, forKey: .pendingUsd) ?? 0
        lifetimeEarnedUsd = try container.decodeIfPresent(Double.self, forKey: .lifetimeEarnedUsd) ?? 0
        minPayoutUsd = try container.decodeIfPresent(Double.self, forKey: .minPayoutUsd) ?? 10
        creatorSharePct = try container.decodeIfPresent(Double.self, forKey: .creatorSharePct) ?? 70
    }

    func toDomain() -> CreatorBalance {
        CreatorBalance(
            creatorID: creatorID,
            availableUsd: availableUsd,
            pendingUsd: pendingUsd,
            lifetimeEarnedUsd: lifetimeEarnedUsd,
            minPayoutUsd: minPayoutUsd,
            creatorSharePct: creatorSharePct
        )
    }
}

struct PayoutResponseDTO: Decodable {
    let id: String
    let creatorID: String
    let amountUsd: Double
    let status: String
    let suiTxHash: String?
    let requestedAt: String?
    let processedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case amountUsd = "amount_usd"
        case status
        case suiTxHash = "sui_tx_hash"
        case requestedAt = "requested_at"
        case processedAt = "processed_at"
    }

    func toDomain() -> Payout {
        Payout(
            id: id,
            creatorID: creatorID,
            amountUsd: amountUsd,
            status: status,
            suiTxHash: suiTxHash,
            requestedAt: APIDateParser.parse(requestedAt),
            processedAt: APIDateParser.parse(processedAt)
        )
    }
}

struct ListPayoutsResponseDTO: Decodable {
    let payouts: [PayoutResponseDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case payouts
        case nextCursor = "next_cursor"
    }
}

struct RequestPayoutBodyDTO: Encodable {
    let amountUsd: Double

    enum CodingKeys: String, CodingKey {
        case amountUsd = "amount_usd"
    }
}

// MARK: - Ads

struct AdPlacementDTO: Decodable {
    let placementID: String
    let name: String
    let adNetwork: String
    let frequencyCap: Int
    let minPosition: Int
    let maxPosition: Int?
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case placementID = "placement_id"
        case name
        case adNetwork = "ad_network"
        case frequencyCap = "frequency_cap"
        case minPosition = "min_position"
        case maxPosition = "max_position"
        case active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placementID = try container.decode(String.self, forKey: .placementID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? placementID
        adNetwork = try container.decodeIfPresent(String.self, forKey: .adNetwork) ?? "cas.ai"
        frequencyCap = try container.decodeIfPresent(Int.self, forKey: .frequencyCap) ?? 5
        minPosition = try container.decodeIfPresent(Int.self, forKey: .minPosition) ?? 3
        maxPosition = try container.decodeIfPresent(Int.self, forKey: .maxPosition)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
    }

    func toDomain() -> AdPlacement {
        AdPlacement(
            placementID: placementID,
            name: name,
            adNetwork: adNetwork,
            frequencyCap: frequencyCap,
            minPosition: minPosition,
            maxPosition: maxPosition,
            active: active
        )
    }
}

struct AdPlacementsResponseDTO: Decodable {
    let placements: [AdPlacementDTO]
}

struct RecordAdImpressionBodyDTO: Encodable {
    let placementID: String
    let adUnitID: String
    let feedSessionID: String?
    let postIDAdjacent: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case placementID = "placement_id"
        case adUnitID = "ad_unit_id"
        case feedSessionID = "feed_session_id"
        case postIDAdjacent = "post_id_adjacent"
        case source
    }
}

struct RecordAdImpressionResponseDTO: Decodable {
    let impressionID: String?
    let accepted: Bool?

    enum CodingKeys: String, CodingKey {
        case impressionID = "impression_id"
        case accepted
    }
}

struct RecordAdClickBodyDTO: Encodable {
    let impressionID: String

    enum CodingKeys: String, CodingKey {
        case impressionID = "impression_id"
    }
}

struct RecordAdRevenueBodyDTO: Encodable {
    let impressionID: String
    let adNetwork: String
    let ecpmUsd: Double
    let revenueUsd: Double
    let currency: String
    let adjacentPostIDs: [String]

    enum CodingKeys: String, CodingKey {
        case impressionID = "impression_id"
        case adNetwork = "ad_network"
        case ecpmUsd = "ecpm_usd"
        case revenueUsd = "revenue_usd"
        case currency
        case adjacentPostIDs = "adjacent_post_ids"
    }
}

struct MonetizationConfigResponseDTO: Decodable {
    let creatorSharePct: Double
    let postsBetweenAdSlots: Int
    let minPayoutUsd: Double
    let monetizableSources: [String]

    enum CodingKeys: String, CodingKey {
        case creatorSharePct = "creator_share_pct"
        case postsBetweenAdSlots = "posts_between_ad_slots"
        case minPayoutUsd = "min_payout_usd"
        case monetizableSources = "monetizable_sources"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creatorSharePct = try container.decodeIfPresent(Double.self, forKey: .creatorSharePct) ?? 70
        postsBetweenAdSlots = try container.decodeIfPresent(Int.self, forKey: .postsBetweenAdSlots) ?? 5
        minPayoutUsd = try container.decodeIfPresent(Double.self, forKey: .minPayoutUsd) ?? 10
        monetizableSources = try container.decodeIfPresent([String].self, forKey: .monetizableSources) ?? ["feed"]
    }

    func toDomain() -> MonetizationConfig {
        MonetizationConfig(
            creatorSharePct: creatorSharePct,
            postsBetweenAdSlots: postsBetweenAdSlots,
            minPayoutUsd: minPayoutUsd,
            monetizableSources: monetizableSources
        )
    }
}

// MARK: - Moderation / sessions / polls

struct ReportPostBodyDTO: Encodable {
    let reason: String
}

struct ReportReasonItemDTO: Decodable, Sendable {
    let code: String
    let label: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case code
        case label
        case description
        case title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        if let label = try container.decodeIfPresent(String.self, forKey: .label) {
            self.label = label
        } else {
            label = try container.decodeIfPresent(String.self, forKey: .title) ?? code
        }
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

struct ReportReasonsResponseDTO: Decodable, Sendable {
    let reasons: [ReportReasonItemDTO]?
    let items: [ReportReasonItemDTO]?

    var all: [ReportReasonItemDTO] { reasons ?? items ?? [] }
}

struct SuccessResponseDTO: Decodable {
    let success: Bool?
}

struct BlockedUsersResponseDTO: Decodable {
    let users: [BlockedUserDTO]?
    let blocked: [BlockedUserDTO]?

    var items: [BlockedUserDTO] { users ?? blocked ?? [] }
}

struct BlockedUserDTO: Decodable {
    let id: String
    let username: String?
    let displayName: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }

    func toDomain() -> BlockedUser {
        BlockedUser(
            id: id,
            username: username ?? id,
            displayName: displayName ?? username ?? id,
            avatarURL: avatarURL.flatMap(URL.init(string:))
        )
    }
}

struct StartSessionBodyDTO: Encodable {
    let platform: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case platform
        case appVersion = "app_version"
    }
}

struct StartSessionResponseDTO: Decodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

struct EndSessionBodyDTO: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

struct SessionActivityBodyDTO: Encodable {
    let sessionID: String
    let activityType: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case activityType = "activity_type"
    }
}

struct AttConsentBodyDTO: Encodable {
    let status: String
}

struct UpdatePostBodyDTO: Encodable {
    let content: String?
    let mediaKey: String?

    enum CodingKeys: String, CodingKey {
        case content
        case mediaKey = "media_key"
    }
}

struct SchedulePostBodyDTO: Encodable {
    let publishAt: String

    enum CodingKeys: String, CodingKey {
        case publishAt = "publish_at"
    }
}

struct PostsPageDTO: Decodable {
    let posts: [PostDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case items
        case nextCursor = "next_cursor"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let posts = try container.decodeIfPresent([PostDTO].self, forKey: .posts) {
            self.posts = posts
        } else {
            self.posts = try container.decodeIfPresent([PostDTO].self, forKey: .items) ?? []
        }
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

struct CreatePollBodyDTO: Encodable {
    let question: String
    let options: [String]
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case question
        case options
        case expiresAt = "expires_at"
    }
}

struct VotePollBodyDTO: Encodable {
    let optionIndex: Int

    enum CodingKeys: String, CodingKey {
        case optionIndex = "option_index"
    }
}

struct PollOptionDTO: Decodable {
    let text: String
    let votes: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        votes = try container.decodeIfPresent(Int64.self, forKey: .votes) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case text, votes
    }

    func toDomain() -> PollOption {
        PollOption(text: text, votes: Int(votes))
    }
}

struct PollResponseDTO: Decodable {
    let id: String
    let postID: String
    let question: String
    let options: [PollOptionDTO]
    let votesCount: Int64
    let expiresAt: String?
    let viewerVote: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case question
        case options
        case votesCount = "votes_count"
        case expiresAt = "expires_at"
        case viewerVote = "viewer_vote"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        postID = try container.decode(String.self, forKey: .postID)
        question = try container.decodeIfPresent(String.self, forKey: .question) ?? ""
        options = try container.decodeIfPresent([PollOptionDTO].self, forKey: .options) ?? []
        votesCount = try container.decodeIfPresent(Int64.self, forKey: .votesCount) ?? 0
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        viewerVote = try container.decodeIfPresent(Int.self, forKey: .viewerVote)
    }

    func toDomain() -> Poll {
        Poll(
            id: id,
            postID: postID,
            question: question,
            options: options.map { $0.toDomain() },
            votesCount: Int(votesCount),
            expiresAt: APIDateParser.parse(expiresAt),
            viewerVote: viewerVote
        )
    }
}

struct LinkPreviewResponseDTO: Decodable {
    let url: String
    let title: String?
    let description: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case description
        case imageURL = "image_url"
    }

    func toDomain() -> LinkPreview? {
        guard let parsed = URL(string: url) else { return nil }
        return LinkPreview(
            url: parsed,
            title: title,
            description: description,
            imageURL: imageURL.flatMap(URL.init(string:))
        )
    }
}
