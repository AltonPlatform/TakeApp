import Foundation

struct NotificationUseCase: Sendable {
    private let repository: NotificationRepositoryProtocol

    init(repository: NotificationRepositoryProtocol) {
        self.repository = repository
    }

    func fetchNotifications(cursor: String? = nil, limit: Int = 30, windowDays: Int = 7) async throws -> NotificationPage {
        try await repository.fetchNotifications(cursor: cursor, limit: limit, windowDays: windowDays)
    }

    func markRead(id: String) async throws {
        try await repository.markRead(id: id)
    }

    func markAllRead() async throws {
        try await repository.markAllRead()
    }

    func fetchUnreadCount() async throws -> Int {
        try await repository.fetchUnreadCount()
    }

    func appealComment(commentID: String, message: String? = nil) async throws {
        try await repository.appealComment(commentID: commentID, message: message)
    }
}
