import Foundation

struct FeedItem: Equatable, Hashable, Identifiable, Sendable {
    var id: String { post.id }

    let post: Post
    let finalScore: Double
    let userScore: Double
    let creatorScore: Double
    let brandScore: Double
    /// Present when this timeline card is someone else's repost of `post`.
    let repostedByDisplayName: String?
    /// Nested original shown inside a reply-style card (Figma Reply variant).
    let quotedParent: ParentPostPreview?

    init(
        post: Post,
        finalScore: Double,
        userScore: Double,
        creatorScore: Double,
        brandScore: Double,
        repostedByDisplayName: String? = nil,
        quotedParent: ParentPostPreview? = nil
    ) {
        self.post = post
        self.finalScore = finalScore
        self.userScore = userScore
        self.creatorScore = creatorScore
        self.brandScore = brandScore
        self.repostedByDisplayName = repostedByDisplayName
        self.quotedParent = quotedParent
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
            && lhs.finalScore == rhs.finalScore
            && lhs.userScore == rhs.userScore
            && lhs.creatorScore == rhs.creatorScore
            && lhs.brandScore == rhs.brandScore
            && lhs.post == rhs.post
            && lhs.repostedByDisplayName == rhs.repostedByDisplayName
            && lhs.quotedParent == rhs.quotedParent
    }

    func updatingPost(_ post: Post) -> FeedItem {
        FeedItem(
            post: post,
            finalScore: finalScore,
            userScore: userScore,
            creatorScore: creatorScore,
            brandScore: brandScore,
            repostedByDisplayName: repostedByDisplayName,
            quotedParent: quotedParent
        )
    }
}

enum FeedTimelineItem: Equatable, Identifiable, Sendable {
    case post(FeedItem)
    case reply(FeedReplyItem)

    var id: String {
        switch self {
        case .post(let item):
            return "post-\(item.id)"
        case .reply(let item):
            return "reply-\(item.id)"
        }
    }

    /// True when the underlying post is moderation-blurred or age-gated.
    var isSensitiveContent: Bool {
        isSensitiveBlurContent || isAgeGatedContent
    }

    var isSensitiveBlurContent: Bool {
        switch self {
        case .post(let item):
            return item.post.sensitiveBlur || (item.quotedParent?.sensitiveBlur ?? false)
        case .reply(let item):
            return item.parentPost.sensitiveBlur
        }
    }

    var isAgeGatedContent: Bool {
        switch self {
        case .post(let item):
            return item.post.ageGated || (item.quotedParent?.ageGated ?? false)
        case .reply(let item):
            return item.parentPost.ageGated
        }
    }
}

struct FeedAdSlot: Equatable, Sendable, Identifiable {
    var id: String { "\(placementID)-\(position)" }

    let placementID: String
    /// 1-based index into the post timeline where a native ad should appear.
    let position: Int
}

struct FeedPage: Equatable, Sendable {
    let items: [FeedTimelineItem]
    let nextCursor: String?
    let adSlots: [FeedAdSlot]

    init(items: [FeedTimelineItem], nextCursor: String?, adSlots: [FeedAdSlot] = []) {
        self.items = items
        self.nextCursor = nextCursor
        self.adSlots = adSlots
    }
}

struct ShotFeedPage: Equatable, Sendable {
    let items: [FeedItem]
    let nextCursor: String?
    let adSlots: [FeedAdSlot]

    init(items: [FeedItem], nextCursor: String?, adSlots: [FeedAdSlot] = []) {
        self.items = items
        self.nextCursor = nextCursor
        self.adSlots = adSlots
    }
}
