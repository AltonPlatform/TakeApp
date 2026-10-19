import Foundation

struct ChatRow: Identifiable, Equatable {
    let message: DMMessage
    let showDate: Bool
    let grouped: Bool
    let showTail: Bool
    let replyPreview: DMMessage?
    let senderName: String?
    let senderAvatarURL: URL?

    var id: String {
        message.clientMsgID.isEmpty ? message.id : message.clientMsgID
    }
}

enum ChatRowsBuilder {
    static func build(
        messages: [DMMessage],
        members: [DMConversationMember]
    ) -> [ChatRow] {
        guard !messages.isEmpty else { return [] }
        var bySeq: [Int64: DMMessage] = [:]
        bySeq.reserveCapacity(messages.count)
        for msg in messages {
            bySeq[msg.seq] = msg
        }
        var memberByID: [String: DMConversationMember] = [:]
        memberByID.reserveCapacity(members.count)
        for member in members {
            memberByID[member.userID] = member
        }

        var rows: [ChatRow] = []
        rows.reserveCapacity(messages.count)
        var previousDayKey: String?

        for index in messages.indices {
            let message = messages[index]
            let day = ChatDateCache.dayKey(message.createdAt)
            let showDate = index == 0 || previousDayKey != day
            previousDayKey = day
            let grouped = ChatBubbleGrouping.isGroupedWithPrevious(messages: messages, at: index)
            let showTail = ChatBubbleGrouping.shouldShowTail(messages: messages, at: index)
            let reply: DMMessage? = {
                guard let seq = message.replyToSeq else { return nil }
                return bySeq[seq]
            }()
            let member = memberByID[message.senderID]
            let name = member?.displayName.nilIfEmpty ?? member?.username.nilIfEmpty
            rows.append(
                ChatRow(
                    message: message,
                    showDate: showDate,
                    grouped: grouped,
                    showTail: showTail,
                    replyPreview: reply,
                    senderName: name,
                    senderAvatarURL: member?.avatarURL
                )
            )
        }
        return rows
    }

    /// Swaps the message inside an existing row. Grouping and date flags stay put.
    static func replacing(_ rows: [ChatRow], message: DMMessage) -> [ChatRow] {
        let rowID = message.clientMsgID.isEmpty ? message.id : message.clientMsgID
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return rows }
        var next = rows
        let old = next[index]
        next[index] = ChatRow(
            message: message,
            showDate: old.showDate,
            grouped: old.grouped,
            showTail: old.showTail,
            replyPreview: old.replyPreview,
            senderName: old.senderName,
            senderAvatarURL: old.senderAvatarURL
        )
        return next
    }

    /// Appends one row and refreshes the previous tail. `messages` already includes `message`.
    static func appending(
        _ message: DMMessage,
        onto rows: [ChatRow],
        messages: [DMMessage],
        members: [DMConversationMember]
    ) -> [ChatRow] {
        var next = rows
        let index = messages.count - 1
        guard index >= 0 else { return next }
        if index > 0, let previous = next.indices.last {
            let old = next[previous]
            next[previous] = ChatRow(
                message: old.message,
                showDate: old.showDate,
                grouped: old.grouped,
                showTail: ChatBubbleGrouping.shouldShowTail(messages: messages, at: index - 1),
                replyPreview: old.replyPreview,
                senderName: old.senderName,
                senderAvatarURL: old.senderAvatarURL
            )
        }
        next.append(makeRow(message, index: index, messages: messages, members: members))
        return next
    }

    private static func makeRow(
        _ message: DMMessage,
        index: Int,
        messages: [DMMessage],
        members: [DMConversationMember]
    ) -> ChatRow {
        let day = ChatDateCache.dayKey(message.createdAt)
        let previousDay = index > 0 ? ChatDateCache.dayKey(messages[index - 1].createdAt) : nil
        let member = members.first { $0.userID == message.senderID }
        let name = member?.displayName.nilIfEmpty ?? member?.username.nilIfEmpty
        let reply: DMMessage? = {
            guard let seq = message.replyToSeq else { return nil }
            return messages.first { $0.seq == seq }
        }()
        return ChatRow(
            message: message,
            showDate: index == 0 || previousDay != day,
            grouped: ChatBubbleGrouping.isGroupedWithPrevious(messages: messages, at: index),
            showTail: ChatBubbleGrouping.shouldShowTail(messages: messages, at: index),
            replyPreview: reply,
            senderName: name,
            senderAvatarURL: member?.avatarURL
        )
    }
}

struct TypingThrottle {
    var interval: TimeInterval = 3
    private var lastSentAt: Date?

    mutating func shouldSend(now: Date = Date()) -> Bool {
        if let last = lastSentAt, now.timeIntervalSince(last) < interval {
            return false
        }
        lastSentAt = now
        return true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
