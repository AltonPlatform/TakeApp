import Foundation

protocol DirectRepositoryProtocol: Sendable {
    func fetchInbox(folder: String, cursor: String?, limit: Int) async throws -> DMInboxPage
    func getOrCreateDirect(recipientID: String) async throws -> DMConversation
    func createGroup(memberIDs: [String], title: String) async throws -> DMConversation
    func updateGroupInfo(conversationID: String, title: String?, avatarKey: String?) async throws -> DMConversation
    func addGroupMembers(conversationID: String, memberIDs: [String]) async throws -> DMConversation
    func removeGroupMember(conversationID: String, userID: String) async throws -> DMConversation?
    func setGroupAdmin(conversationID: String, memberID: String, isAdmin: Bool, rights: [String]) async throws -> DMConversation
    func banGroupMember(conversationID: String, memberID: String) async throws -> DMConversation
    func unbanGroupMember(conversationID: String, userID: String) async throws -> DMConversation
    func groupMembers(conversationID: String) async throws -> [DMConversationMember]
    func uploadGroupAvatar(conversationID: String, data: Data) async throws -> String
    func fetchHistory(
        conversationID: String,
        beforeSeq: Int64?,
        afterSeq: Int64?,
        limit: Int
    ) async throws -> DMHistoryPage
    func sendMessage(
        conversationID: String,
        clientMsgID: String,
        kind: String,
        body: String?,
        postID: String?,
        mediaKey: String?,
        mediaWidth: Int?,
        mediaHeight: Int?,
        replyToSeq: Int64?,
        klipyGifID: String?,
        gifSourceURL: String?,
        gifContentType: String?,
        payload: DMSendPayload?
    ) async throws -> DMMessage
    func attachmentUploadURL(
        conversationID: String,
        contentType: String
    ) async throws -> DMAttachmentUpload
    func forwardMessage(messageID: String, conversationIDs: [String]) async throws
    func editMessage(messageID: String, body: String) async throws -> DMMessage
    func deleteMessage(messageID: String) async throws
    func setReaction(messageID: String, emoji: String) async throws -> [DMMessageReaction]
    func clearReaction(messageID: String) async throws -> [DMMessageReaction]
    func setChecklistItem(messageID: String, itemID: Int, done: Bool) async throws -> [DMChecklistMark]
    func appendChecklistItems(messageID: String, items: [String]) async throws -> DMMessage
    func votePoll(messageID: String, optionIDs: [Int]) async throws -> DMMessage
    func closePoll(messageID: String) async throws -> DMMessage
    func appendPollOptions(messageID: String, options: [String]) async throws -> DMMessage
    func markRead(conversationID: String, seq: Int64) async throws
    func acceptRequest(conversationID: String) async throws -> DMConversation
    func declineRequest(conversationID: String) async throws
    func sharePost(postID: String, recipientIDs: [String], text: String?) async throws
}
