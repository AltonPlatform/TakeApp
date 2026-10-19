import Foundation

enum DMEditRules {
    /// Matches message-service `EDIT_WINDOW_MINS`.
    static let windowMinutes: TimeInterval = 15 * 60

    static func canEdit(
        _ message: DMMessage,
        currentUserID: String,
        now: Date = Date()
    ) -> Bool {
        guard message.kind == .text else { return false }
        guard message.deletedAt == nil else { return false }
        guard !message.isPending, !message.isFailed else { return false }
        guard message.senderID == currentUserID || message.senderID == "me" else { return false }
        guard let created = ChatDateCache.date(message.createdAt) else { return false }
        return now.timeIntervalSince(created) <= windowMinutes
    }
}
