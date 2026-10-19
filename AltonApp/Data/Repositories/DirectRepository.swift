import Foundation

final class DirectRepository: DirectRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient
    private let mediaUploadClient: MediaUploadClient
    private let cache: MessageCacheStore

    init(
        apiClient: APIClient,
        mediaUploadClient: MediaUploadClient,
        cache: MessageCacheStore
    ) {
        self.apiClient = apiClient
        self.mediaUploadClient = mediaUploadClient
        self.cache = cache
    }

    private func currentCacheGeneration() async -> UInt {
        await MainActor.run { cache.cacheGeneration }
    }

    private func writeCache(_ messages: [DMMessage], generation: UInt) async {
        await MainActor.run { cache.upsert(messages: messages, generation: generation) }
    }

    convenience init(apiClient: APIClient, cache: MessageCacheStore) {
        self.init(
            apiClient: apiClient,
            mediaUploadClient: MediaUploadClient(),
            cache: cache
        )
    }

    func fetchInbox(folder: String, cursor: String?, limit: Int) async throws -> DMInboxPage {
        let response: DMInboxResponseDTO = try await apiClient.authorizedRequest(
            .dmInbox(folder: folder, cursor: cursor, limit: limit)
        )
        return DMInboxPage(
            conversations: response.conversations.map { $0.toDomain() },
            nextCursor: response.nextCursor
        )
    }

    func getOrCreateDirect(recipientID: String) async throws -> DMConversation {
        struct Body: Encodable { let recipient_id: String }
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmCreateConversation,
            body: Body(recipient_id: recipientID)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Conversation unavailable")
        }
        return conversation
    }

    func createGroup(memberIDs: [String], title: String) async throws -> DMConversation {
        struct Body: Encodable {
            let member_ids: [String]
            let title: String
        }
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmCreateGroup,
            body: Body(member_ids: memberIDs, title: title)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Group unavailable")
        }
        return conversation
    }

    func updateGroupInfo(
        conversationID: String,
        title: String?,
        avatarKey: String?
    ) async throws -> DMConversation {
        struct Body: Encodable {
            let title: String?
            let avatarKey: String?
            enum CodingKeys: String, CodingKey {
                case title
                case avatarKey = "avatar_key"
            }
        }
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmUpdateGroup(conversationID: conversationID),
            body: Body(title: title, avatarKey: avatarKey)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Group unavailable")
        }
        return conversation
    }

    func addGroupMembers(conversationID: String, memberIDs: [String]) async throws -> DMConversation {
        struct Body: Encodable {
            let memberIDs: [String]
            enum CodingKeys: String, CodingKey { case memberIDs = "member_ids" }
        }
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmAddGroupMembers(conversationID: conversationID),
            body: Body(memberIDs: memberIDs)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Group unavailable")
        }
        return conversation
    }

    func removeGroupMember(conversationID: String, userID: String) async throws -> DMConversation? {
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmRemoveGroupMember(conversationID: conversationID, userID: userID)
        )
        return response.conversation?.toDomain()
    }

    func setGroupAdmin(
        conversationID: String,
        memberID: String,
        isAdmin: Bool,
        rights: [String]
    ) async throws -> DMConversation {
        struct Body: Encodable {
            let memberID: String
            let isAdmin: Bool
            let rights: [String]
            enum CodingKeys: String, CodingKey {
                case memberID = "member_id"
                case isAdmin = "is_admin"
                case rights
            }
        }
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmSetGroupAdmin(conversationID: conversationID),
            body: Body(memberID: memberID, isAdmin: isAdmin, rights: rights)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Group unavailable")
        }
        return conversation
    }

    func banGroupMember(conversationID: String, memberID: String) async throws -> DMConversation {
        struct Body: Encodable {
            let memberID: String
            enum CodingKeys: String, CodingKey { case memberID = "member_id" }
        }
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmBanGroupMember(conversationID: conversationID),
            body: Body(memberID: memberID)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Group unavailable")
        }
        return conversation
    }

    func unbanGroupMember(conversationID: String, userID: String) async throws -> DMConversation {
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmUnbanGroupMember(conversationID: conversationID, userID: userID)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Group unavailable")
        }
        return conversation
    }

    func groupMembers(conversationID: String) async throws -> [DMConversationMember] {
        struct Response: Decodable { let members: [DMConversationMemberDTO] }
        let response: Response = try await apiClient.authorizedRequest(
            .dmGroupMembers(conversationID: conversationID)
        )
        return response.members.map { $0.toDomain() }
    }

    func uploadGroupAvatar(conversationID: String, data: Data) async throws -> String {
        let uploaded = try await uploadImageData(
            conversationID: conversationID,
            data: data,
            contentType: "image/jpeg"
        )
        return uploaded.mediaKey
    }

    func fetchHistory(
        conversationID: String,
        beforeSeq: Int64?,
        afterSeq: Int64?,
        limit: Int
    ) async throws -> DMHistoryPage {
        let generation = await currentCacheGeneration()
        let response: DMHistoryResponseDTO = try await apiClient.authorizedRequest(
            .dmMessages(
                conversationID: conversationID,
                beforeSeq: beforeSeq,
                afterSeq: afterSeq,
                limit: limit
            )
        )
        let messages = response.messages.map { $0.toDomain() }
        let postCards = (response.postCards ?? []).map { $0.toDomain() }
        await writeCache(messages, generation: generation)
        await MainActor.run { cache.upsertPostCards(postCards, generation: generation) }
        return DMHistoryPage(
            messages: messages,
            postCards: postCards,
            nextBeforeSeq: response.nextBeforeSeq
        )
    }

    func sendMessage(
        conversationID: String,
        clientMsgID: String,
        kind: String,
        body: String?,
        postID: String?,
        mediaKey: String? = nil,
        mediaWidth: Int? = nil,
        mediaHeight: Int? = nil,
        replyToSeq: Int64? = nil,
        klipyGifID: String? = nil,
        gifSourceURL: String? = nil,
        gifContentType: String? = nil,
        payload: DMSendPayload? = nil
    ) async throws -> DMMessage {
        let generation = await currentCacheGeneration()
        struct Body: Encodable {
            let client_msg_id: String
            let kind: String
            let body: String?
            let post_id: String?
            let media_key: String?
            let media_width: Int?
            let media_height: Int?
            let reply_to_seq: Int64?
            let klipy_gif_id: String?
            let gif_source_url: String?
            let gif_content_type: String?
            let payload: DMSendPayload?
        }
        let response: DMSendResponseDTO = try await apiClient.authorizedRequest(
            .dmSendMessage(conversationID: conversationID),
            body: Body(
                client_msg_id: clientMsgID,
                kind: kind,
                body: body,
                post_id: postID,
                media_key: mediaKey,
                media_width: mediaWidth,
                media_height: mediaHeight,
                reply_to_seq: replyToSeq,
                klipy_gif_id: klipyGifID,
                gif_source_url: gifSourceURL,
                gif_content_type: gifContentType,
                payload: payload
            )
        )
        guard let message = response.message?.toDomain() else {
            throw APIError.validation("Send failed")
        }
        await writeCache([message], generation: generation)
        return message
    }

    func attachmentUploadURL(
        conversationID: String,
        contentType: String
    ) async throws -> DMAttachmentUpload {
        struct Body: Encodable { let content_type: String }
        let response: DMAttachmentUploadDTO = try await apiClient.authorizedRequest(
            .dmAttachmentUpload(conversationID: conversationID),
            body: Body(content_type: contentType)
        )
        return try response.toDomain()
    }

    func uploadImageData(
        conversationID: String,
        data: Data,
        contentType: String
    ) async throws -> (mediaKey: String, width: Int?, height: Int?) {
        let upload = try await attachmentUploadURL(
            conversationID: conversationID,
            contentType: contentType
        )
        try await mediaUploadClient.upload(
            data: data,
            to: upload.uploadURL,
            contentType: contentType
        )
        return (upload.objectKey, nil, nil)
    }

    func forwardMessage(messageID: String, conversationIDs: [String]) async throws {
        struct Body: Encodable { let conversation_ids: [String] }
        let response: DMForwardResponseDTO = try await apiClient.authorizedRequest(
            .dmForwardMessage(messageID: messageID),
            body: Body(conversation_ids: conversationIDs)
        )
        if response.results?.isEmpty != false {
            throw APIError.validation("Couldn’t forward this message")
        }
    }

    func editMessage(messageID: String, body: String) async throws -> DMMessage {
        struct Body: Encodable { let body: String }
        struct Resp: Decodable { let message: DMMessageDTO }
        let resp: Resp = try await apiClient.authorizedRequest(
            .dmEditMessage(messageID: messageID),
            body: Body(body: body)
        )
        return resp.message.toDomain()
    }

    func deleteMessage(messageID: String) async throws {
        struct Resp: Decodable { let message: DMMessageDTO? }
        let _: Resp = try await apiClient.authorizedRequest(
            .dmDeleteMessage(messageID: messageID)
        )
    }

    func setReaction(messageID: String, emoji: String) async throws -> [DMMessageReaction] {
        struct Body: Encodable { let emoji: String }
        struct Resp: Decodable {
            let reactions: [DMReactionDTO]?
        }
        let resp: Resp = try await apiClient.authorizedRequest(
            .dmSetReaction(messageID: messageID),
            body: Body(emoji: emoji)
        )
        let reactions = (resp.reactions ?? []).map { $0.toDomain() }
        await MainActor.run { cache.updateReactions(messageID: messageID, reactions: reactions) }
        return reactions
    }

    func clearReaction(messageID: String) async throws -> [DMMessageReaction] {
        struct Resp: Decodable {
            let reactions: [DMReactionDTO]?
        }
        let resp: Resp = try await apiClient.authorizedRequest(
            .dmClearReaction(messageID: messageID)
        )
        let reactions = (resp.reactions ?? []).map { $0.toDomain() }
        await MainActor.run { cache.updateReactions(messageID: messageID, reactions: reactions) }
        return reactions
    }

    /// A realtime reaction list is already the server's copy. Keep the cache on it
    /// so the next open does not flash the previous set before history arrives.
    func rememberReactions(messageID: String, reactions: [DMMessageReaction]) async {
        await MainActor.run { cache.updateReactions(messageID: messageID, reactions: reactions) }
    }

    func setChecklistItem(messageID: String, itemID: Int, done: Bool) async throws -> [DMChecklistMark] {
        struct Body: Encodable { let done: Bool }
        struct Resp: Decodable { let marks: [DMChecklistMarkDTO]? }
        let endpoint: APIEndpoint = done
            ? .dmSetChecklistItem(messageID: messageID, itemID: itemID)
            : .dmClearChecklistItem(messageID: messageID, itemID: itemID)
        let body: Body? = done ? Body(done: true) : nil
        let resp: Resp = try await apiClient.authorizedRequest(
            endpoint,
            body: body
        )
        return (resp.marks ?? []).map { $0.toDomain() }
    }

    func appendChecklistItems(messageID: String, items: [String]) async throws -> DMMessage {
        let generation = await currentCacheGeneration()
        struct Body: Encodable { let items: [String] }
        let message: DMMessageDTO = try await apiClient.authorizedRequest(
            .dmAppendChecklistItems(messageID: messageID),
            body: Body(items: items)
        )
        let domain = message.toDomain()
        await writeCache([domain], generation: generation)
        return domain
    }

    func votePoll(messageID: String, optionIDs: [Int]) async throws -> DMMessage {
        let generation = await currentCacheGeneration()
        struct Body: Encodable { let option_ids: [Int] }
        let message: DMMessageDTO = try await apiClient.authorizedRequest(
            .dmVotePoll(messageID: messageID),
            body: Body(option_ids: optionIDs)
        )
        let domain = message.toDomain()
        await writeCache([domain], generation: generation)
        return domain
    }

    func closePoll(messageID: String) async throws -> DMMessage {
        let generation = await currentCacheGeneration()
        let message: DMMessageDTO = try await apiClient.authorizedRequest(
            .dmClosePoll(messageID: messageID)
        )
        let domain = message.toDomain()
        await writeCache([domain], generation: generation)
        return domain
    }

    func appendPollOptions(messageID: String, options: [String]) async throws -> DMMessage {
        let generation = await currentCacheGeneration()
        struct Body: Encodable { let options: [String] }
        let message: DMMessageDTO = try await apiClient.authorizedRequest(
            .dmAppendPollOptions(messageID: messageID),
            body: Body(options: options)
        )
        let domain = message.toDomain()
        await writeCache([domain], generation: generation)
        return domain
    }

    func markRead(conversationID: String, seq: Int64) async throws {
        struct Body: Encodable { let seq: Int64 }
        let _: DMSuccessDTO = try await apiClient.authorizedRequest(
            .dmMarkRead(conversationID: conversationID),
            body: Body(seq: seq)
        )
    }

    func acceptRequest(conversationID: String) async throws -> DMConversation {
        let response: DMConversationResponseDTO = try await apiClient.authorizedRequest(
            .dmAccept(conversationID: conversationID)
        )
        guard let conversation = response.conversation?.toDomain() else {
            throw APIError.validation("Accept failed")
        }
        return conversation
    }

    func declineRequest(conversationID: String) async throws {
        let _: DMSuccessDTO = try await apiClient.authorizedRequest(
            .dmDecline(conversationID: conversationID)
        )
    }

    func sharePost(postID: String, recipientIDs: [String], text: String?) async throws {
        struct Body: Encodable {
            let post_id: String
            let recipient_ids: [String]
            let text: String?
        }
        let response: DMShareResponseDTO = try await apiClient.authorizedRequest(
            .dmShare,
            body: Body(post_id: postID, recipient_ids: recipientIDs, text: text)
        )
        if response.results?.isEmpty != false {
            throw APIError.validation("Couldn’t send this post")
        }
    }

    /// Fills the message cache for inbox rows so opening a chat does not wait on history.
    /// Skips a conversation whose cache already includes `lastSeq`. At most three requests at once.
    func prefetchHistories(_ conversations: [DMConversation]) async {
        let pending = Array(conversations.prefix(12))
        var index = 0
        while index < pending.count {
            if Task.isCancelled { return }
            let end = min(index + 3, pending.count)
            let batch = pending[index..<end]
            index = end
            await withTaskGroup(of: Void.self) { group in
                for conversation in batch {
                    group.addTask { [self] in
                        await self.prefetchHistory(conversation)
                    }
                }
            }
        }
    }

    private func prefetchHistory(_ conversation: DMConversation) async {
        if Task.isCancelled { return }
        let latest = await MainActor.run { cache.latestSeq(conversationID: conversation.id) }
        guard latest < conversation.lastSeq else { return }
        _ = try? await fetchHistory(
            conversationID: conversation.id,
            beforeSeq: nil,
            afterSeq: nil,
            limit: 50
        )
    }

    func rememberSharedPost(_ post: Post) async {
        let generation = await currentCacheGeneration()
        await MainActor.run { cache.upsertSharedPost(post, generation: generation) }
    }

    @MainActor
    func cachedMessages(conversationID: String) -> [DMMessage] {
        cache.messages(conversationID: conversationID)
    }

    @MainActor
    func cachedShares(postIDs: [String]) -> [DMCachedShare] {
        cache.shares(postIDs: postIDs)
    }
}
