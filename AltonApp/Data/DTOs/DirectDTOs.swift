import Foundation

struct DMConversationDTO: Decodable {
    let id: String
    let kind: String?
    let peerUserID: String?
    let peerUsername: String?
    let peerDisplayName: String?
    let peerAvatarURL: String?
    let folder: String?
    let memberState: String?
    let lastSeq: Int64?
    let lastReadSeq: Int64?
    let peerLastReadSeq: Int64?
    let lastMessageID: String?
    let previewText: String?
    let previewKind: String?
    let updatedAt: String?
    let unreadCount: Int64?
    let title: String?
    let memberCount: Int?
    let members: [DMConversationMemberDTO]?
    let groupAvatarURL: String?
    let visibility: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, folder, title, members, visibility
        case peerUserID = "peer_user_id"
        case peerUsername = "peer_username"
        case peerDisplayName = "peer_display_name"
        case peerAvatarURL = "peer_avatar_url"
        case memberState = "member_state"
        case lastSeq = "last_seq"
        case lastReadSeq = "last_read_seq"
        case peerLastReadSeq = "peer_last_read_seq"
        case lastMessageID = "last_message_id"
        case previewText = "preview_text"
        case previewKind = "preview_kind"
        case updatedAt = "updated_at"
        case unreadCount = "unread_count"
        case memberCount = "member_count"
        case groupAvatarURL = "group_avatar_url"
    }

    func toDomain() -> DMConversation {
        DMConversation(
            id: id,
            kind: kind ?? "direct",
            peerUserID: peerUserID ?? "",
            peerUsername: peerUsername ?? "",
            peerDisplayName: peerDisplayName ?? peerUsername ?? "",
            peerAvatarURL: peerAvatarURL.flatMap(URL.init(string:)),
            folder: folder ?? "primary",
            memberState: memberState ?? "active",
            lastSeq: lastSeq ?? 0,
            lastReadSeq: lastReadSeq ?? 0,
            peerLastReadSeq: peerLastReadSeq ?? 0,
            lastMessageID: lastMessageID ?? "",
            previewText: previewText ?? "",
            previewKind: previewKind ?? "text",
            updatedAt: updatedAt ?? "",
            unreadCount: unreadCount ?? 0,
            title: title ?? "",
            memberCount: memberCount ?? 0,
            members: (members ?? []).map { $0.toDomain() },
            groupAvatarURL: groupAvatarURL.flatMap(URL.init(string:)),
            visibility: visibility ?? ""
        )
    }
}

struct DMConversationMemberDTO: Decodable {
    let userID: String?
    let username: String?
    let displayName: String?
    let avatarURL: String?
    let role: String?
    let rights: [String]?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case role, rights
    }

    func toDomain() -> DMConversationMember {
        DMConversationMember(
            userID: userID ?? "",
            username: username ?? "",
            displayName: displayName ?? username ?? "",
            avatarURL: avatarURL.flatMap(URL.init(string:)),
            role: role ?? "member",
            rights: Set(rights ?? [])
        )
    }
}

struct DMMessageDTO: Decodable {
    let id: String
    let conversationID: String
    let seq: Int64
    let senderID: String
    let kind: String?
    let body: String?
    let postID: String?
    let postType: String?
    let replyToSeq: Int64?
    let clientMsgID: String?
    let createdAt: String?
    let editedAt: String?
    let deletedAt: String?
    let mediaKey: String?
    let mediaURL: String?
    let mediaThumbKey: String?
    let mediaThumbURL: String?
    let mediaWidth: Int?
    let mediaHeight: Int?
    let mediaStatus: String?
    let forwardedFromUserID: String?
    let forwardedFromUsername: String?
    let reactions: [DMReactionDTO]?
    let payload: DMWirePayload?
    let checklistMarks: [DMChecklistMarkDTO]?
    let pollVotes: [DMPollVoteDTO]?
    let pollTallies: [DMPollTallyDTO]?
    let pollTotalVoters: Int?

    enum CodingKeys: String, CodingKey {
        case id, seq, kind, body, reactions
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case postID = "post_id"
        case postType = "post_type"
        case replyToSeq = "reply_to_seq"
        case clientMsgID = "client_msg_id"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
        case mediaKey = "media_key"
        case mediaURL = "media_url"
        case mediaThumbKey = "media_thumb_key"
        case mediaThumbURL = "media_thumb_url"
        case mediaWidth = "media_width"
        case mediaHeight = "media_height"
        case mediaStatus = "media_status"
        case forwardedFromUserID = "forwarded_from_user_id"
        case forwardedFromUsername = "forwarded_from_username"
        case payload
        case checklistMarks = "checklist_marks"
        case pollVotes = "poll_votes"
        case pollTallies = "poll_tallies"
        case pollTotalVoters = "poll_total_voters"
    }

    func toDomain(pending: Bool = false) -> DMMessage {
        let resolvedKind = DMMessageKind(rawValue: kind ?? "text") ?? .text
        return DMMessage(
            id: id,
            conversationID: conversationID,
            seq: seq,
            senderID: senderID,
            kind: resolvedKind,
            body: body ?? "",
            postID: postID,
            postType: postType,
            replyToSeq: replyToSeq,
            clientMsgID: clientMsgID ?? id,
            createdAt: createdAt ?? "",
            editedAt: editedAt,
            deletedAt: deletedAt,
            mediaURL: mediaURL.flatMap(URL.init(string:)),
            mediaThumbURL: mediaThumbURL.flatMap(URL.init(string:))
                ?? mediaURL.flatMap(URL.init(string:)),
            mediaWidth: mediaWidth,
            mediaHeight: mediaHeight,
            mediaStatus: mediaStatus,
            forwardedFromUserID: forwardedFromUserID,
            forwardedFromUsername: forwardedFromUsername,
            reactions: (reactions ?? []).map { $0.toDomain() },
            localImageData: nil,
            isPending: pending,
            isFailed: mediaStatus == "failed",
            location: payload?.location(for: resolvedKind),
            checklist: payload?.checklist(for: resolvedKind),
            checklistMarks: (checklistMarks ?? []).map { $0.toDomain() },
            poll: payload?.poll(for: resolvedKind),
            pollVotes: (pollVotes ?? []).map { $0.toDomain() },
            pollTallies: (pollTallies ?? []).map { $0.toDomain() },
            pollTotalVoters: pollTotalVoters ?? 0,
            stickerID: payload?.stickerID(for: resolvedKind)
        )
    }
}

struct DMWirePayload: Decodable {
    let lat: Double?
    let lng: Double?
    let name: String?
    let address: String?
    let title: String?
    let items: [DMChecklistItem]?
    let nextID: Int?
    let othersCanMark: Bool?
    let othersCanAdd: Bool?
    let question: String?
    let options: [DMPollOption]?
    let anonymous: Bool?
    let multiple: Bool?
    let quiz: Bool?
    let closed: Bool?
    let correctOptionID: Int?
    let explanation: String?
    let stickerID: String?
    let packID: String?
    let emojiHint: String?

    enum CodingKeys: String, CodingKey {
        case lat, lng, name, address, title, items
        case nextID = "next_id"
        case othersCanMark = "others_can_mark"
        case othersCanAdd = "others_can_add"
        case question, options, anonymous, multiple, quiz, closed, explanation
        case correctOptionID = "correct_option_id"
        case stickerID = "sticker_id"
        case packID = "pack_id"
        case emojiHint = "emoji_hint"
    }

    func stickerID(for kind: DMMessageKind) -> String? {
        guard kind == .sticker else { return nil }
        let trimmed = stickerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func location(for kind: DMMessageKind) -> DMLocation? {
        guard kind == .location, let lat, let lng else { return nil }
        return DMLocation(lat: lat, lng: lng, name: name, address: address)
    }

    func checklist(for kind: DMMessageKind) -> DMChecklist? {
        guard kind == .checklist, let items, !items.isEmpty else { return nil }
        return DMChecklist(
            title: title ?? "",
            items: items,
            nextID: nextID ?? (items.count + 1),
            othersCanMark: othersCanMark ?? true,
            othersCanAdd: othersCanAdd ?? false
        )
    }

    func poll(for kind: DMMessageKind) -> DMPoll? {
        guard kind == .poll, let options, options.count >= 2, let question else { return nil }
        return DMPoll(
            question: question,
            options: options,
            nextID: nextID ?? (options.count + 1),
            anonymous: anonymous ?? true,
            multiple: multiple ?? false,
            quiz: quiz ?? false,
            othersCanAdd: othersCanAdd ?? false,
            closed: closed ?? false,
            correctOptionID: correctOptionID,
            explanation: explanation
        )
    }
}

struct DMPollVoteDTO: Decodable {
    let optionID: Int
    let userID: String

    enum CodingKeys: String, CodingKey {
        case optionID = "option_id"
        case userID = "user_id"
    }

    func toDomain() -> DMPollVote {
        DMPollVote(optionID: optionID, userID: userID)
    }
}

struct DMPollTallyDTO: Decodable {
    let optionID: Int
    let count: Int

    enum CodingKeys: String, CodingKey {
        case optionID = "option_id"
        case count
    }

    func toDomain() -> DMPollTally {
        DMPollTally(optionID: optionID, count: count)
    }
}

struct DMChecklistMarkDTO: Decodable {
    let itemID: Int
    let userID: String

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case userID = "user_id"
    }

    func toDomain() -> DMChecklistMark {
        DMChecklistMark(itemID: itemID, userID: userID)
    }
}

struct DMReactionDTO: Decodable {
    let userID: String
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case emoji
    }

    func toDomain() -> DMMessageReaction {
        DMMessageReaction(userID: userID, emoji: emoji)
    }
}

struct DMPostCardDTO: Decodable {
    let postID: String
    let postType: String?
    let creatorID: String?
    let creatorUsername: String?
    let contentPreview: String?
    let thumbnailURL: String?
    let unavailable: Bool?
    let creatorAvatarURL: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case postType = "post_type"
        case creatorID = "creator_id"
        case creatorUsername = "creator_username"
        case contentPreview = "content_preview"
        case thumbnailURL = "thumbnail_url"
        case unavailable
        case creatorAvatarURL = "creator_avatar_url"
    }

    func toDomain() -> DMPostCard {
        DMPostCard(
            postID: postID,
            postType: postType ?? "take",
            creatorID: creatorID ?? "",
            creatorUsername: creatorUsername ?? "",
            contentPreview: contentPreview ?? "",
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:)),
            unavailable: unavailable ?? false,
            creatorAvatarURL: creatorAvatarURL.flatMap(URL.init(string:))
        )
    }
}

struct DMInboxResponseDTO: Decodable {
    let conversations: [DMConversationDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case conversations
        case nextCursor = "next_cursor"
    }
}

struct DMHistoryResponseDTO: Decodable {
    let messages: [DMMessageDTO]
    let postCards: [DMPostCardDTO]?
    let nextBeforeSeq: Int64?

    enum CodingKeys: String, CodingKey {
        case messages
        case postCards = "post_cards"
        case nextBeforeSeq = "next_before_seq"
    }
}

struct DMSendResponseDTO: Decodable {
    let message: DMMessageDTO?
    let conversation: DMConversationDTO?
    let duplicate: Bool?
}

struct DMConversationResponseDTO: Decodable {
    let conversation: DMConversationDTO?
}

struct DMShareResponseDTO: Decodable {
    let results: [DMSendResponseDTO]?
}

struct DMSuccessDTO: Decodable {
    let success: Bool?
}

struct DMAttachmentUploadDTO: Decodable {
    let uploadURL: String
    let objectKey: String
    let expiresIn: Int64?

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case objectKey = "object_key"
        case expiresIn = "expires_in"
    }

    func toDomain() throws -> DMAttachmentUpload {
        guard let url = URL(string: uploadURL) else {
            throw APIError.validation("Invalid upload URL")
        }
        return DMAttachmentUpload(
            uploadURL: url,
            objectKey: objectKey,
            expiresIn: expiresIn ?? 0
        )
    }
}

struct DMForwardResponseDTO: Decodable {
    let results: [DMSendResponseDTO]?
}
