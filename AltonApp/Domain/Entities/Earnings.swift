import Foundation

struct CreatorOverview: Equatable, Sendable {
    let totalViews30d: Int
    let totalWatchTimeMs: Int
    let monetizableViews: Int
    let estimatedEarningsUsd: Double
    let creatorSharePct: Double
    let availableBalance: Double
    let pendingPayout: Double
    let sourceBreakdown: [SourceBreakdown]
    let earningsByPost: [CreatorPostEarnings]
    let profileViews: Int
}

struct CreatorPostEarnings: Equatable, Identifiable, Sendable {
    var id: String { postID }

    let postID: String
    let earningsUsd: Double
    let monetizableViews: Int
}

struct CreatorBalance: Equatable, Sendable {
    let creatorID: String
    let availableUsd: Double
    let pendingUsd: Double
    let lifetimeEarnedUsd: Double
    let minPayoutUsd: Double
    let creatorSharePct: Double
}

struct Payout: Equatable, Identifiable, Sendable {
    let id: String
    let creatorID: String
    let amountUsd: Double
    let status: String
    let suiTxHash: String?
    let requestedAt: Date?
    let processedAt: Date?
}

struct MonetizationConfig: Equatable, Sendable {
    let creatorSharePct: Double
    let postsBetweenAdSlots: Int
    let minPayoutUsd: Double
    let monetizableSources: [String]
}

struct AdPlacement: Equatable, Identifiable, Sendable {
    var id: String { placementID }

    let placementID: String
    let name: String
    let adNetwork: String
    let frequencyCap: Int
    let minPosition: Int
    let maxPosition: Int?
    let active: Bool
}

struct Poll: Equatable, Identifiable, Sendable {
    let id: String
    let postID: String
    let question: String
    let options: [PollOption]
    let votesCount: Int
    let expiresAt: Date?
    let viewerVote: Int?
}

struct PollOption: Equatable, Identifiable, Sendable {
    var id: String { text }

    let text: String
    let votes: Int
}

struct LinkPreview: Equatable, Sendable {
    let url: URL
    let title: String?
    let description: String?
    let imageURL: URL?
}

struct BlockedUser: Equatable, Identifiable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
}
