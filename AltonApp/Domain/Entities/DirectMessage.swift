import Foundation

struct DMConversationMember: Identifiable, Equatable, Hashable, Sendable {
    var id: String { userID }
    let userID: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    var role: String

    var rights: Set<String>

    init(
        userID: String,
        username: String,
        displayName: String,
        avatarURL: URL?,
        role: String = "member",
        rights: Set<String> = []
    ) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.role = role
        self.rights = rights
    }

    var isOwner: Bool { role == "owner" }
    var isAdmin: Bool { role == "admin" }

    func allows(_ right: String) -> Bool {
        isOwner || (isAdmin && rights.contains(right))
    }

    var canChangeInfo: Bool { allows("change_info") }
    var canDeleteMessages: Bool { allows("delete_messages") }
    var canBanMembers: Bool { allows("ban_members") }
    var canAssignAdmins: Bool { allows("assign_admins") }
}

struct DMConversation: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let kind: String
    let peerUserID: String
    let peerUsername: String
    let peerDisplayName: String
    let peerAvatarURL: URL?
    let folder: String
    let memberState: String
    var lastSeq: Int64
    var lastReadSeq: Int64
    var peerLastReadSeq: Int64
    var lastMessageID: String
    var previewText: String
    var previewKind: String
    var updatedAt: String
    var unreadCount: Int64
    var title: String
    var memberCount: Int
    var members: [DMConversationMember]
    var groupAvatarURL: URL?
    var visibility: String

    var isGroup: Bool { kind == "group" }

    var displayTitle: String {
        if isGroup, !title.isEmpty { return title }
        return peerDisplayName
    }

    func applying(_ update: DMGroupUpdate) -> DMConversation {
        guard update.conversationID == id else { return self }
        var copy = self
        copy.title = update.title
        copy.groupAvatarURL = update.groupAvatarURL
        copy.visibility = update.visibility
        copy.memberCount = update.memberCount
        copy.members = update.members
        return copy
    }
}

struct DMGroupUpdate: Equatable, Sendable {
    var conversationID: String
    var title: String
    var groupAvatarURL: URL?
    var visibility: String
    var memberCount: Int
    var members: [DMConversationMember]
}

enum DMMessageKind: String, Sendable {
    case text
    case postShare = "post_share"
    case system
    case image
    case gif
    case location
    case checklist
    case poll
    case sticker
}

struct DMLocation: Equatable, Sendable, Codable {
    var lat: Double
    var lng: Double
    var name: String?
    var address: String?
}

struct DMChecklistItem: Equatable, Sendable, Identifiable, Codable {
    var id: Int
    var text: String
}

struct DMChecklist: Equatable, Sendable, Codable {
    var title: String
    var items: [DMChecklistItem]
    var nextID: Int
    var othersCanMark: Bool
    var othersCanAdd: Bool

    enum CodingKeys: String, CodingKey {
        case title, items
        case nextID = "next_id"
        case othersCanMark = "others_can_mark"
        case othersCanAdd = "others_can_add"
    }
}

struct DMChecklistMark: Equatable, Sendable, Hashable {
    var itemID: Int
    var userID: String
}

struct DMPollOption: Equatable, Sendable, Identifiable, Codable {
    var id: Int
    var text: String
}

struct DMPoll: Equatable, Sendable, Codable {
    var question: String
    var options: [DMPollOption]
    var nextID: Int
    var anonymous: Bool
    var multiple: Bool
    var quiz: Bool
    var othersCanAdd: Bool
    var closed: Bool
    var correctOptionID: Int?
    var explanation: String?

    enum CodingKeys: String, CodingKey {
        case question, options, anonymous, multiple, quiz, closed, explanation
        case nextID = "next_id"
        case othersCanAdd = "others_can_add"
        case correctOptionID = "correct_option_id"
    }
}

struct DMPollVote: Equatable, Sendable, Hashable {
    var optionID: Int
    var userID: String
}

struct DMPollTally: Equatable, Sendable, Hashable {
    var optionID: Int
    var count: Int
}

enum DMSendPayload: Encodable {
    case location(DMLocation)
    case checklist(DMChecklist)
    case poll(DMPoll)
    case sticker(id: String)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .location(let location):
            try location.encode(to: encoder)
        case .checklist(let checklist):
            try checklist.encode(to: encoder)
        case .poll(let poll):
            try poll.encode(to: encoder)
        case .sticker(let id):
            var container = encoder.container(keyedBy: StickerKeys.self)
            try container.encode(id, forKey: .stickerID)
        }
    }

    private enum StickerKeys: String, CodingKey {
        case stickerID = "sticker_id"
    }
}

enum DMPayloadCodec {
    static func location(from object: [String: Any]) -> DMLocation? {
        guard let lat = doubleValue(object["lat"]),
              let lng = doubleValue(object["lng"]) else { return nil }
        return DMLocation(
            lat: lat,
            lng: lng,
            name: trimmed(object["name"]),
            address: trimmed(object["address"])
        )
    }

    static func checklist(from object: [String: Any]) -> DMChecklist? {
        guard let rawItems = object["items"] as? [[String: Any]] else { return nil }
        let items = rawItems.compactMap { item -> DMChecklistItem? in
            guard let id = intValue(item["id"]),
                  let text = item["text"] as? String else { return nil }
            return DMChecklistItem(id: id, text: text)
        }
        guard !items.isEmpty else { return nil }
        return DMChecklist(
            title: (object["title"] as? String) ?? "",
            items: items,
            nextID: intValue(object["next_id"]) ?? (items.count + 1),
            othersCanMark: object["others_can_mark"] as? Bool ?? true,
            othersCanAdd: object["others_can_add"] as? Bool ?? false
        )
    }

    static func marks(from raw: Any?) -> [DMChecklistMark] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let itemID = intValue(row["item_id"]),
                  let userID = row["user_id"] as? String else { return nil }
            return DMChecklistMark(itemID: itemID, userID: userID)
        }
    }

    static func poll(from object: [String: Any]) -> DMPoll? {
        guard let question = object["question"] as? String else { return nil }
        let rawOptions = object["options"] as? [[String: Any]] ?? []
        let options = rawOptions.compactMap { option -> DMPollOption? in
            guard let id = intValue(option["id"]),
                  let text = option["text"] as? String else { return nil }
            return DMPollOption(id: id, text: text)
        }
        guard options.count >= 2 else { return nil }
        return DMPoll(
            question: question,
            options: options,
            nextID: intValue(object["next_id"]) ?? (options.count + 1),
            anonymous: object["anonymous"] as? Bool ?? true,
            multiple: object["multiple"] as? Bool ?? false,
            quiz: object["quiz"] as? Bool ?? false,
            othersCanAdd: object["others_can_add"] as? Bool ?? false,
            closed: object["closed"] as? Bool ?? false,
            correctOptionID: intValue(object["correct_option_id"]),
            explanation: trimmed(object["explanation"])
        )
    }

    static func pollVotes(from raw: Any?) -> [DMPollVote] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let optionID = intValue(row["option_id"]),
                  let userID = row["user_id"] as? String else { return nil }
            return DMPollVote(optionID: optionID, userID: userID)
        }
    }

    static func pollTallies(from raw: Any?) -> [DMPollTally] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let optionID = intValue(row["option_id"]),
                  let count = intValue(row["count"]) else { return nil }
            return DMPollTally(optionID: optionID, count: count)
        }
    }

    static func applyPayload(kind: DMMessageKind, object: [String: Any]?) -> (DMLocation?, DMChecklist?, DMPoll?) {
        guard let object else { return (nil, nil, nil) }
        switch kind {
        case .location:
            return (location(from: object), nil, nil)
        case .checklist:
            return (nil, checklist(from: object), nil)
        case .poll:
            return (nil, nil, poll(from: object))
        default:
            return (nil, nil, nil)
        }
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        return nil
    }

    private static func trimmed(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ChatChecklistState {
    static func canMark(_ checklist: DMChecklist, isAuthor: Bool) -> Bool {
        isAuthor || checklist.othersCanMark
    }

    static func canAdd(_ checklist: DMChecklist, isAuthor: Bool) -> Bool {
        isAuthor || checklist.othersCanAdd
    }

    static func toggled(
        marks: [DMChecklistMark],
        itemID: Int,
        userID: String,
        done: Bool
    ) -> [DMChecklistMark] {
        var next = marks.filter { $0.itemID != itemID }
        if done {
            next.append(DMChecklistMark(itemID: itemID, userID: userID))
            next.sort { $0.itemID < $1.itemID }
        }
        return next
    }
}

enum ChatPollState {
    static let maxOptions = 12

    static func hasVoted(_ votes: [DMPollVote], userID: String) -> Bool {
        votes.contains { $0.userID == userID }
    }

    static func canVote(_ poll: DMPoll, hasVoted: Bool, isPending: Bool) -> Bool {
        !poll.closed && !isPending && !(poll.quiz && hasVoted)
    }

    static func canRetract(_ poll: DMPoll, hasVoted: Bool) -> Bool {
        hasVoted && !poll.closed && !poll.quiz
    }

    static func canAddOption(_ poll: DMPoll, isAuthor: Bool) -> Bool {
        !poll.closed && !poll.quiz && poll.options.count < maxOptions && (isAuthor || poll.othersCanAdd)
    }

    static func canClose(_ poll: DMPoll, isAuthor: Bool) -> Bool {
        isAuthor && !poll.closed
    }

    static func isRevealed(_ poll: DMPoll, hasVoted: Bool) -> Bool {
        poll.closed || hasVoted
    }

    /// Largest-remainder percentages. The returned values sum to 100 when any option has votes.
    static func percentages(counts: [Int: Int]) -> [Int: Int] {
        let total = counts.values.reduce(0, +)
        guard total > 0 else {
            return Dictionary(uniqueKeysWithValues: counts.keys.map { ($0, 0) })
        }
        struct Share {
            var id: Int
            var floor: Int
            var remainder: Double
        }
        var shares: [Share] = []
        var used = 0
        for (id, count) in counts {
            let exact = Double(count) * 100 / Double(total)
            let floor = Int(exact)
            shares.append(Share(id: id, floor: floor, remainder: exact - Double(floor)))
            used += floor
        }
        shares.sort { lhs, rhs in
            if lhs.remainder != rhs.remainder { return lhs.remainder > rhs.remainder }
            return lhs.id < rhs.id
        }
        var leftover = 100 - used
        var result: [Int: Int] = [:]
        for share in shares {
            var value = share.floor
            if leftover > 0, share.remainder > 0 {
                value += 1
                leftover -= 1
            }
            result[share.id] = value
        }
        return result
    }

    static func optimisticVote(
        votes: [DMPollVote],
        tallies: [DMPollTally],
        totalVoters: Int,
        userID: String,
        optionIDs: [Int]
    ) -> (votes: [DMPollVote], tallies: [DMPollTally], totalVoters: Int) {
        let previous = Set(votes.filter { $0.userID == userID }.map(\.optionID))
        let nextIDs = Set(optionIDs)
        var counts = Dictionary(uniqueKeysWithValues: tallies.map { ($0.optionID, $0.count) })
        for id in previous {
            counts[id] = max(0, (counts[id] ?? 0) - 1)
        }
        for id in nextIDs {
            counts[id, default: 0] += 1
        }
        var total = totalVoters
        if previous.isEmpty, !nextIDs.isEmpty { total += 1 }
        if !previous.isEmpty, nextIDs.isEmpty { total = max(0, total - 1) }
        let nextVotes = votes.filter { $0.userID != userID }
            + nextIDs.sorted().map { DMPollVote(optionID: $0, userID: userID) }
        let nextTallies = counts
            .filter { $0.value > 0 }
            .map { DMPollTally(optionID: $0.key, count: $0.value) }
            .sorted { $0.optionID < $1.optionID }
        return (nextVotes, nextTallies, total)
    }
}

struct DMMessageReaction: Equatable, Sendable, Hashable {
    let userID: String
    let emoji: String
}

struct DMMessage: Identifiable, Equatable, Sendable {
    let id: String
    let conversationID: String
    let seq: Int64
    let senderID: String
    let kind: DMMessageKind
    var body: String
    let postID: String?
    let postType: String?
    let replyToSeq: Int64?
    let clientMsgID: String
    let createdAt: String
    var editedAt: String?
    var deletedAt: String?
    var mediaURL: URL?
    var mediaThumbURL: URL?
    var mediaWidth: Int?
    var mediaHeight: Int?
    var mediaStatus: String?
    var forwardedFromUserID: String?
    var forwardedFromUsername: String?
    var reactions: [DMMessageReaction] = []
    /// Local JPEG preview while upload/send is in flight (not persisted).
    var localImageData: Data? = nil
    var isPending: Bool
    var isFailed: Bool = false
    var location: DMLocation? = nil
    var checklist: DMChecklist? = nil
    var checklistMarks: [DMChecklistMark] = []
    var poll: DMPoll? = nil
    var pollVotes: [DMPollVote] = []
    var pollTallies: [DMPollTally] = []
    var pollTotalVoters: Int = 0
    var stickerID: String? = nil

    static func == (lhs: DMMessage, rhs: DMMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.conversationID == rhs.conversationID
            && lhs.seq == rhs.seq
            && lhs.senderID == rhs.senderID
            && lhs.kind == rhs.kind
            && lhs.body == rhs.body
            && lhs.postID == rhs.postID
            && lhs.postType == rhs.postType
            && lhs.replyToSeq == rhs.replyToSeq
            && lhs.clientMsgID == rhs.clientMsgID
            && lhs.createdAt == rhs.createdAt
            && lhs.editedAt == rhs.editedAt
            && lhs.deletedAt == rhs.deletedAt
            && lhs.mediaURL == rhs.mediaURL
            && lhs.mediaThumbURL == rhs.mediaThumbURL
            && lhs.mediaWidth == rhs.mediaWidth
            && lhs.mediaHeight == rhs.mediaHeight
            && lhs.mediaStatus == rhs.mediaStatus
            && lhs.forwardedFromUserID == rhs.forwardedFromUserID
            && lhs.forwardedFromUsername == rhs.forwardedFromUsername
            && lhs.reactions == rhs.reactions
            && lhs.isPending == rhs.isPending
            && lhs.isFailed == rhs.isFailed
            && lhs.location == rhs.location
            && lhs.checklist == rhs.checklist
            && lhs.checklistMarks == rhs.checklistMarks
            && lhs.poll == rhs.poll
            && lhs.pollVotes == rhs.pollVotes
            && lhs.pollTallies == rhs.pollTallies
            && lhs.pollTotalVoters == rhs.pollTotalVoters
            && lhs.stickerID == rhs.stickerID
    }

    var isMediaProcessing: Bool {
        mediaStatus == "processing"
    }

    /// Aggregated reaction badges: emoji → count.
    /// Sorted by count descending; ties keep first-seen order.
    var reactionBadges: [(emoji: String, count: Int)] {
        var counts: [String: Int] = [:]
        var firstIndex: [String: Int] = [:]
        for (idx, r) in reactions.enumerated() {
            counts[r.emoji, default: 0] += 1
            if firstIndex[r.emoji] == nil {
                firstIndex[r.emoji] = idx
            }
        }
        return counts
            .map { (emoji: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return (firstIndex[lhs.emoji] ?? 0) < (firstIndex[rhs.emoji] ?? 0)
            }
    }

    func myReaction(currentUserID: String) -> String? {
        reactions.first(where: { $0.userID == currentUserID })?.emoji
    }
}

/// Local copy of a shared take or shot. `post` is set once the full post has
/// been loaded, so the next open can draw the final card height immediately.
struct DMCachedShare: Sendable {
    let card: DMPostCard
    let post: Post?
}

struct DMPostCard: Identifiable, Equatable, Sendable {
    var id: String { postID }
    let postID: String
    let postType: String
    let creatorID: String
    let creatorUsername: String
    let contentPreview: String
    let thumbnailURL: URL?
    let unavailable: Bool
    let creatorAvatarURL: URL?
}

struct DMInboxPage: Sendable {
    let conversations: [DMConversation]
    let nextCursor: String?
}

struct DMHistoryPage: Sendable {
    let messages: [DMMessage]
    let postCards: [DMPostCard]
    let nextBeforeSeq: Int64?
}

struct DMAttachmentUpload: Sendable {
    let uploadURL: URL
    let objectKey: String
    let expiresIn: Int64
}
