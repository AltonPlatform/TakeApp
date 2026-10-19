import Foundation

protocol NotificationRepositoryProtocol: Sendable {
    func fetchNotifications(
        cursor: String?,
        limit: Int,
        windowDays: Int,
        category: NotificationCategory?
    ) async throws -> NotificationPage
    func markRead(id: String) async throws
    func markAllRead() async throws
    func fetchUnreadCount() async throws -> Int
    func appealComment(commentID: String, message: String?) async throws
}
