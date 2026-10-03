import Foundation
import Observation

@MainActor
@Observable
final class ActivityViewModel {
    var items: [NotificationItem] = []
    var unreadCount = 0
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var lastRefreshedAt: Date?

    private var nextCursor7: String?
    private var nextCursor30: String?
    private var windowDays = 7
    private var hasExhausted7 = false
    private let notificationUseCase: NotificationUseCase
    private let userUseCase: UserUseCase?

    init(notificationUseCase: NotificationUseCase, userUseCase: UserUseCase? = nil) {
        self.notificationUseCase = notificationUseCase
        self.userUseCase = userUseCase
    }

    var recent7Days: [NotificationItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return items.filter { ($0.createdAt ?? .distantPast) >= cutoff }
    }

    var older30Days: [NotificationItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return items.filter { ($0.createdAt ?? .distantPast) < cutoff }
    }

    var shouldAutoRefresh: Bool {
        guard let lastRefreshedAt else { return true }
        return Date().timeIntervalSince(lastRefreshedAt) > 60
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            windowDays = 7
            hasExhausted7 = false
            nextCursor7 = nil
            nextCursor30 = nil
            let page = try await notificationUseCase.fetchNotifications(windowDays: 7)
            items = page.notifications
            nextCursor7 = page.nextCursor
            unreadCount = page.unreadCount
            if page.nextCursor == nil {
                hasExhausted7 = true
            }
            lastRefreshedAt = Date()

            // If the 7-day window is empty (or exhausted), pull older activity from 30 days.
            if hasExhausted7 {
                await loadMore30(isNested: true)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refresh() async {
        await loadInitial()
    }

    func refreshUnreadCount() async {
        do {
            unreadCount = try await notificationUseCase.fetchUnreadCount()
        } catch {
            // Best-effort badge update
        }
    }

    func loadMoreIfNeeded(current: NotificationItem) async {
        guard !isLoadingMore else { return }
        guard items.last?.id == current.id else { return }

        if !hasExhausted7 {
            guard let cursor = nextCursor7, !cursor.isEmpty else {
                hasExhausted7 = true
                await loadMore30()
                return
            }
            isLoadingMore = true
            defer { isLoadingMore = false }
            do {
                let page = try await notificationUseCase.fetchNotifications(
                    cursor: cursor,
                    windowDays: 7
                )
                appendUnique(page.notifications)
                nextCursor7 = page.nextCursor
                unreadCount = page.unreadCount
                if page.nextCursor == nil {
                    hasExhausted7 = true
                    await loadMore30(isNested: true)
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            return
        }

        await loadMore30()
    }

    /// Loads older notifications (7–30 days). Loops while the API returns pages that
    /// are entirely within the recent 7-day window (filtered out client-side).
    private func loadMore30(isNested: Bool = false) async {
        if !isNested {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        }
        defer {
            if !isNested { isLoadingMore = false }
        }

        var safety = 0
        repeat {
            safety += 1
            do {
                let page = try await notificationUseCase.fetchNotifications(
                    cursor: nextCursor30,
                    windowDays: 30
                )
                let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                let older = page.notifications.filter { ($0.createdAt ?? .distantPast) < cutoff }
                appendUnique(older)
                nextCursor30 = page.nextCursor
                unreadCount = page.unreadCount

                // Stop when no more pages, or we got at least one older item (user can scroll for more).
                if page.nextCursor == nil || !older.isEmpty {
                    break
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                break
            }
        } while safety < 5
    }

    func markRead(_ item: NotificationItem) async {
        guard item.isUnread else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].readAt = Date()
            unreadCount = max(0, unreadCount - 1)
        }
        do {
            try await notificationUseCase.markRead(id: item.id)
        } catch {
            // Keep optimistic update
        }
    }

    func markAllRead() async {
        for index in items.indices where items[index].isUnread {
            items[index].readAt = Date()
        }
        unreadCount = 0
        do {
            try await notificationUseCase.markAllRead()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func followBack(actorID: String) async {
        guard let userUseCase else { return }
        do {
            _ = try await userUseCase.follow(userID: actorID)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func appealComment(_ item: NotificationItem) async {
        guard let commentID = item.commentID, item.canAppeal else { return }
        do {
            try await notificationUseCase.appealComment(commentID: commentID)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].canAppeal = false
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func appendUnique(_ newItems: [NotificationItem]) {
        let existing = Set(items.map(\.id))
        items.append(contentsOf: newItems.filter { !existing.contains($0.id) })
    }
}
