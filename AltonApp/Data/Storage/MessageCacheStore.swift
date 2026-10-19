import Foundation
import SwiftData

private struct CachedReaction: Codable {
    let userID: String
    let emoji: String
}

@Model
final class CachedDMMessage {
    @Attribute(.unique) var id: String
    var conversationID: String
    var seq: Int64
    var senderID: String
    var kind: String
    var body: String
    var postID: String?
    var postType: String?
    var replyToSeq: Int64?
    var clientMsgID: String
    var createdAt: String
    var editedAt: String?
    var deletedAt: String?
    var mediaURL: String?
    var mediaThumbURL: String?
    var mediaWidth: Int?
    var mediaHeight: Int?
    var mediaStatus: String?
    var forwardedFromUserID: String?
    var forwardedFromUsername: String?
    var payloadJSON: String?
    var reactionsJSON: String?

    init(from message: DMMessage) {
        self.id = message.id
        self.conversationID = message.conversationID
        self.seq = message.seq
        self.senderID = message.senderID
        self.kind = message.kind.rawValue
        self.body = message.body
        self.postID = message.postID
        self.postType = message.postType
        self.replyToSeq = message.replyToSeq
        self.clientMsgID = message.clientMsgID
        self.createdAt = message.createdAt
        self.editedAt = message.editedAt
        self.deletedAt = message.deletedAt
        self.mediaURL = message.mediaURL?.absoluteString
        self.mediaThumbURL = message.mediaThumbURL?.absoluteString
        self.mediaWidth = message.mediaWidth
        self.mediaHeight = message.mediaHeight
        self.mediaStatus = message.mediaStatus
        self.forwardedFromUserID = message.forwardedFromUserID
        self.forwardedFromUsername = message.forwardedFromUsername
        self.payloadJSON = Self.encodePayload(message)
        self.reactionsJSON = Self.encodeReactions(message.reactions)
    }

    func toDomain() -> DMMessage {
        DMMessage(
            id: id,
            conversationID: conversationID,
            seq: seq,
            senderID: senderID,
            kind: DMMessageKind(rawValue: kind) ?? .text,
            body: body,
            postID: postID,
            postType: postType,
            replyToSeq: replyToSeq,
            clientMsgID: clientMsgID,
            createdAt: createdAt,
            editedAt: editedAt,
            deletedAt: deletedAt,
            mediaURL: mediaURL.flatMap(URL.init(string:)),
            mediaThumbURL: mediaThumbURL.flatMap(URL.init(string:)),
            mediaWidth: mediaWidth,
            mediaHeight: mediaHeight,
            mediaStatus: mediaStatus,
            forwardedFromUserID: forwardedFromUserID,
            forwardedFromUsername: forwardedFromUsername,
            reactions: Self.decodeReactions(reactionsJSON),
            localImageData: nil,
            isPending: false,
            isFailed: false,
            location: Self.decodeLocation(kind: kind, json: payloadJSON),
            checklist: Self.decodeChecklist(kind: kind, json: payloadJSON),
            poll: Self.decodePoll(kind: kind, json: payloadJSON),
            stickerID: Self.decodeStickerID(kind: kind, json: payloadJSON)
        )
    }

    static func encodeReactions(_ reactions: [DMMessageReaction]) -> String? {
        guard !reactions.isEmpty else { return nil }
        let cached = reactions.map { CachedReaction(userID: $0.userID, emoji: $0.emoji) }
        let data = try? JSONEncoder().encode(cached)
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decodeReactions(_ json: String?) -> [DMMessageReaction] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        let cached = (try? JSONDecoder().decode([CachedReaction].self, from: data)) ?? []
        return cached.map { DMMessageReaction(userID: $0.userID, emoji: $0.emoji) }
    }

    static func encodePayload(_ message: DMMessage) -> String? {
        let data: Data?
        if let location = message.location {
            data = try? JSONEncoder().encode(location)
        } else if let checklist = message.checklist {
            data = try? JSONEncoder().encode(checklist)
        } else if let poll = message.poll {
            data = try? JSONEncoder().encode(poll)
        } else if let stickerID = message.stickerID, message.kind == .sticker {
            data = try? JSONEncoder().encode(["sticker_id": stickerID])
        } else {
            data = nil
        }
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decodeLocation(kind: String, json: String?) -> DMLocation? {
        guard kind == DMMessageKind.location.rawValue, let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DMLocation.self, from: data)
    }

    private static func decodeChecklist(kind: String, json: String?) -> DMChecklist? {
        guard kind == DMMessageKind.checklist.rawValue, let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DMChecklist.self, from: data)
    }

    private static func decodePoll(kind: String, json: String?) -> DMPoll? {
        guard kind == DMMessageKind.poll.rawValue, let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DMPoll.self, from: data)
    }

    private static func decodeStickerID(kind: String, json: String?) -> String? {
        guard kind == DMMessageKind.sticker.rawValue,
              let json,
              let data = json.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        let trimmed = object["sticker_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@Model
final class CachedDMShare {
    @Attribute(.unique) var postID: String
    var payloadJSON: String

    init(postID: String, payloadJSON: String) {
        self.postID = postID
        self.payloadJSON = payloadJSON
    }
}

private struct CachedSharePayload: Codable {
    var postID: String
    var postType: String
    var creatorID: String
    var creatorUsername: String
    var creatorDisplayName: String?
    var creatorAvatarURL: String?
    var content: String
    var thumbnailURL: String?
    var thumbnailKey: String?
    var imageURLs: [String]
    var playbackURL: String?
    var mediaKey: String?
    var unavailable: Bool
    var createdAt: Date?
    var viewCount: Int
    var likeCount: Int
    var commentCount: Int
    var saveCount: Int
    var shareCount: Int
    var repostCount: Int
    var isLiked: Bool
    var isBookmarked: Bool
    var isReposted: Bool
    var ageGated: Bool
    var sensitiveBlur: Bool
    var hydrated: Bool

    static func from(card: DMPostCard) -> CachedSharePayload {
        CachedSharePayload(
            postID: card.postID,
            postType: card.postType,
            creatorID: card.creatorID,
            creatorUsername: card.creatorUsername,
            creatorDisplayName: nil,
            creatorAvatarURL: card.creatorAvatarURL?.absoluteString,
            content: card.contentPreview,
            thumbnailURL: card.thumbnailURL?.absoluteString,
            thumbnailKey: nil,
            imageURLs: [],
            playbackURL: nil,
            mediaKey: nil,
            unavailable: card.unavailable,
            createdAt: nil,
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            ageGated: false,
            sensitiveBlur: false,
            hydrated: false
        )
    }

    static func from(post: Post) -> CachedSharePayload {
        CachedSharePayload(
            postID: post.id,
            postType: post.postType.rawValue,
            creatorID: post.creatorID,
            creatorUsername: post.creatorUsername ?? "",
            creatorDisplayName: post.creatorDisplayName,
            creatorAvatarURL: post.creatorAvatarURL?.absoluteString,
            content: post.content ?? "",
            thumbnailURL: post.thumbnailURL?.absoluteString,
            thumbnailKey: post.thumbnailKey,
            imageURLs: post.imageURLs.map(\.absoluteString),
            playbackURL: post.playbackURL?.absoluteString,
            mediaKey: post.mediaKey,
            unavailable: false,
            createdAt: post.createdAt,
            viewCount: post.viewCount,
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            saveCount: post.saveCount,
            shareCount: post.shareCount,
            repostCount: post.repostCount,
            isLiked: post.isLiked,
            isBookmarked: post.isBookmarked,
            isReposted: post.isReposted,
            ageGated: post.ageGated,
            sensitiveBlur: post.sensitiveBlur,
            hydrated: true
        )
    }

    func share() -> DMCachedShare {
        let card = DMPostCard(
            postID: postID,
            postType: postType.isEmpty ? "take" : postType,
            creatorID: creatorID,
            creatorUsername: creatorUsername,
            contentPreview: content,
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:)),
            unavailable: unavailable,
            creatorAvatarURL: creatorAvatarURL.flatMap(URL.init(string:))
        )
        guard hydrated, !unavailable else {
            return DMCachedShare(card: card, post: nil)
        }
        let post = Post(
            id: postID,
            creatorID: creatorID,
            creatorUsername: creatorUsername.isEmpty ? nil : creatorUsername,
            creatorDisplayName: creatorDisplayName,
            creatorAvatarURL: creatorAvatarURL.flatMap(URL.init(string:)),
            postType: PostType(rawValue: postType),
            status: .published,
            content: content,
            mediaKey: mediaKey,
            thumbnailKey: thumbnailKey,
            playbackURL: playbackURL.flatMap(URL.init(string:)),
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:)),
            imageURLs: imageURLs.compactMap(URL.init(string:)),
            viewCount: viewCount,
            likeCount: likeCount,
            commentCount: commentCount,
            saveCount: saveCount,
            shareCount: shareCount,
            repostCount: repostCount,
            isLiked: isLiked,
            isBookmarked: isBookmarked,
            isReposted: isReposted,
            createdAt: createdAt,
            sensitiveBlur: sensitiveBlur,
            ageGated: ageGated
        )
        return DMCachedShare(card: card, post: post)
    }

    static func encode(_ payload: CachedSharePayload) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String) -> CachedSharePayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedSharePayload.self, from: data)
    }
}

@MainActor
final class MessageCacheStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// After logout wipe, block `upsert` until the next signed-in session so in-flight
    /// `fetchHistory` cannot repopulate the previous account's messages.
    private var writesEnabled = true
    /// Bumped on logout and on account switch. Writes captured under an older value are dropped.
    private(set) var cacheGeneration: UInt = 0
    private var ownerUserID: String?
    private let persistsOwner: Bool
    private static let ownerKey = "dm.cache.ownerUserID"

    // Must not share DraftStore's default.store: SwiftData won't add this schema's tables to it.
    private static let storeName = "dm-message-cache"

    init(inMemory: Bool = false) throws {
        let schema = Schema([CachedDMMessage.self, CachedDMShare.self])
        let configuration = Self.configuration(schema: schema, inMemory: inMemory)
        container = try ModelContainer(for: schema, configurations: [configuration])
        persistsOwner = !inMemory
    }

    private static func configuration(schema: Schema, inMemory: Bool) -> ModelConfiguration {
        ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory)
    }

    static func makePersistent() -> MessageCacheStore {
        do {
            return try MessageCacheStore(inMemory: false)
        } catch {
            Self.destroyStore()
            if let recovered = try? MessageCacheStore(inMemory: false) {
                return recovered
            }
            return (try? MessageCacheStore(inMemory: true)) ?? {
                fatalError("MessageCacheStore unavailable")
            }()
        }
    }

    private static func destroyStore() {
        let url = configuration(schema: Schema([CachedDMMessage.self]), inMemory: false).url
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Clears all cached DM bodies. Call on logout so the next account cannot read them.
    func wipeAll() {
        writesEnabled = false
        cacheGeneration &+= 1
        ownerUserID = nil
        guard deleteAllRows() else { return }
        if persistsOwner {
            UserDefaults.standard.removeObject(forKey: Self.ownerKey)
        }
    }

    /// Re-enable cache writes after a new account signs in.
    func enableWrites() {
        writesEnabled = true
    }

    /// Same user keeps rows. A different persisted owner wipes them. A nil owner adopts rows written before the first session.
    func beginSession(userID: String) {
        if ownerUserID == userID && writesEnabled {
            return
        }
        let persisted = persistsOwner ? UserDefaults.standard.string(forKey: Self.ownerKey) : nil
        let keep = writesEnabled && ownerUserID == nil && (persisted == nil || persisted == userID)
        if !keep {
            cacheGeneration &+= 1
            guard deleteAllRows() else {
                writesEnabled = false
                ownerUserID = nil
                return
            }
        }
        ownerUserID = userID
        writesEnabled = true
        if persistsOwner {
            UserDefaults.standard.set(userID, forKey: Self.ownerKey)
        }
    }

    func updateReactions(messageID: String, reactions: [DMMessageReaction]) {
        guard writesEnabled else { return }
        let id = messageID
        let descriptor = FetchDescriptor<CachedDMMessage>(
            predicate: #Predicate { $0.id == id }
        )
        guard let existing = try? context.fetch(descriptor).first else { return }
        existing.reactionsJSON = CachedDMMessage.encodeReactions(reactions)
        try? context.save()
    }

    func upsert(messages: [DMMessage], generation: UInt) {
        guard writesEnabled, generation == cacheGeneration else { return }
        for message in messages where !message.isPending {
            let id = message.id
            let descriptor = FetchDescriptor<CachedDMMessage>(
                predicate: #Predicate { $0.id == id }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.body = message.body
                existing.editedAt = message.editedAt
                existing.deletedAt = message.deletedAt
                existing.seq = message.seq
                existing.kind = message.kind.rawValue
                existing.replyToSeq = message.replyToSeq
                existing.mediaURL = message.mediaURL?.absoluteString
                existing.mediaThumbURL = message.mediaThumbURL?.absoluteString
                existing.mediaWidth = message.mediaWidth
                existing.mediaHeight = message.mediaHeight
                existing.mediaStatus = message.mediaStatus
                existing.forwardedFromUserID = message.forwardedFromUserID
                existing.forwardedFromUsername = message.forwardedFromUsername
                existing.payloadJSON = CachedDMMessage.encodePayload(message)
                existing.reactionsJSON = CachedDMMessage.encodeReactions(message.reactions)
            } else {
                context.insert(CachedDMMessage(from: message))
            }
        }
        try? context.save()
    }

    /// History previews. A later full post is kept: replacing it with the short
    /// card would shrink the bubble the next time the chat opens.
    func upsertPostCards(_ cards: [DMPostCard], generation: UInt) {
        guard writesEnabled, generation == cacheGeneration else { return }
        for card in cards where !card.postID.isEmpty {
            if let existing = fetchShare(postID: card.postID),
               let payload = CachedSharePayload.decode(existing.payloadJSON),
               payload.hydrated,
               !card.unavailable {
                continue
            }
            guard let json = CachedSharePayload.encode(.from(card: card)) else { continue }
            writeShare(postID: card.postID, json: json)
        }
        try? context.save()
    }

    func upsertSharedPost(_ post: Post, generation: UInt) {
        guard writesEnabled, generation == cacheGeneration, !post.id.isEmpty else { return }
        guard let json = CachedSharePayload.encode(.from(post: post)) else { return }
        writeShare(postID: post.id, json: json)
        try? context.save()
    }

    func shares(postIDs: [String]) -> [DMCachedShare] {
        guard writesEnabled else { return [] }
        var seen = Set<String>()
        var result: [DMCachedShare] = []
        for postID in postIDs where seen.insert(postID).inserted {
            guard let row = fetchShare(postID: postID),
                  let payload = CachedSharePayload.decode(row.payloadJSON) else { continue }
            result.append(payload.share())
        }
        return result
    }

    private func fetchShare(postID: String) -> CachedDMShare? {
        let id = postID
        let descriptor = FetchDescriptor<CachedDMShare>(
            predicate: #Predicate { $0.postID == id }
        )
        return try? context.fetch(descriptor).first
    }

    private func writeShare(postID: String, json: String) {
        if let existing = fetchShare(postID: postID) {
            existing.payloadJSON = json
        } else {
            context.insert(CachedDMShare(postID: postID, payloadJSON: json))
        }
    }

    private func deleteAllRows() -> Bool {
        do {
            try context.delete(model: CachedDMMessage.self)
            try context.delete(model: CachedDMShare.self)
            try context.save()
            return true
        } catch {
            PipelineLogger.logError(PipelineLogger.media, "DM cache wipe failed", error: error)
            return false
        }
    }

    func messages(conversationID: String, limit: Int = 200) -> [DMMessage] {
        guard writesEnabled else { return [] }
        var descriptor = FetchDescriptor<CachedDMMessage>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.seq, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor))?.map { $0.toDomain() } ?? []
    }

    func latestSeq(conversationID: String) -> Int64 {
        guard writesEnabled else { return 0 }
        var descriptor = FetchDescriptor<CachedDMMessage>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.seq, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first?.seq) ?? 0
    }
}
