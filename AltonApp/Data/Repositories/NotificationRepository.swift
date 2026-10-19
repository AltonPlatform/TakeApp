import Foundation

final class NotificationRepository: NotificationRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchNotifications(
        cursor: String?,
        limit: Int,
        windowDays: Int,
        category: NotificationCategory?
    ) async throws -> NotificationPage {
        let response: NotificationsResponseDTO = try await apiClient.authorizedRequest(
            .notifications(cursor: cursor, limit: limit, window: windowDays, category: category?.rawValue)
        )
        return NotificationPage(
            notifications: response.notifications.map { $0.toDomain() },
            nextCursor: response.nextCursor,
            unreadCount: Int(response.unreadCount ?? 0)
        )
    }

    func markRead(id: String) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
            .markNotificationRead(id: id)
        )
    }

    func markAllRead() async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(.markAllNotificationsRead)
    }

    func fetchUnreadCount() async throws -> Int {
        let response: UnreadCountResponseDTO = try await apiClient.authorizedRequest(
            .unreadNotificationCount
        )
        return Int(response.count)
    }

    func appealComment(commentID: String, message: String?) async throws {
        struct Body: Encodable {
            let message: String?
        }
        let _: AppealCommentResponseDTO = try await apiClient.authorizedRequest(
            .appealComment(id: commentID),
            body: Body(message: message)
        )
    }
}
