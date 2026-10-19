import Foundation
import Observation

struct InboxCategorySummary: Equatable, Sendable {
    var previewText: String
    var unreadCount: Int
    var hasContent: Bool

    static let empty = InboxCategorySummary(previewText: "", unreadCount: 0, hasContent: false)
}

@Observable
@MainActor
final class InboxHomeViewModel {
    let inbox: InboxViewModel

    var followersSummary = InboxCategorySummary.empty
    var activitySummary = InboxCategorySummary.empty
    var systemSummary = InboxCategorySummary.empty
    var requestsSummary = InboxCategorySummary.empty
    var activityUnreadTotal = 0

    private let notificationUseCase: NotificationUseCase
    private let directUseCase: DirectUseCase

    init(
        inbox: InboxViewModel,
        notificationUseCase: NotificationUseCase,
        directUseCase: DirectUseCase
    ) {
        self.inbox = inbox
        self.notificationUseCase = notificationUseCase
        self.directUseCase = directUseCase
    }

    /// Tab badge: unread notifications + unread DMs in primary inbox.
    var inboxBadge: Int {
        let dmUnread = inbox.conversations.reduce(0) { $0 + Int($1.unreadCount) }
        return activityUnreadTotal + dmUnread + requestsSummary.unreadCount
    }

    func start() {
        inbox.start()
        Task { await refreshSummaries() }
    }

    func stop() {
        inbox.stop()
    }

    func refresh() async {
        async let inboxRefresh: Void = inbox.refresh()
        async let summaries: Void = refreshSummaries()
        _ = await (inboxRefresh, summaries)
    }

    func refreshSummaries() async {
        async let followers = loadCategorySummary(.followers)
        async let activity = loadCategorySummary(.activity)
        async let system = loadCategorySummary(.system)
        async let requests = loadRequestsSummary()
        async let totalUnread = loadTotalUnread()

        let snapshot = InboxSummariesSnapshot(
            followers: await followers,
            activity: await activity,
            system: await system,
            requests: await requests,
            activityUnreadTotal: await totalUnread
        )
        let current = InboxSummariesSnapshot(
            followers: followersSummary,
            activity: activitySummary,
            system: systemSummary,
            requests: requestsSummary,
            activityUnreadTotal: activityUnreadTotal
        )
        guard snapshot != current else { return }
        followersSummary = snapshot.followers
        activitySummary = snapshot.activity
        systemSummary = snapshot.system
        requestsSummary = snapshot.requests
        activityUnreadTotal = snapshot.activityUnreadTotal
    }

    private struct InboxSummariesSnapshot: Equatable {
        var followers: InboxCategorySummary
        var activity: InboxCategorySummary
        var system: InboxCategorySummary
        var requests: InboxCategorySummary
        var activityUnreadTotal: Int
    }

    private func loadTotalUnread() async -> Int {
        (try? await notificationUseCase.fetchUnreadCount()) ?? 0
    }

    private func loadCategorySummary(_ category: NotificationCategory) async -> InboxCategorySummary {
        do {
            let page = try await notificationUseCase.fetchNotifications(
                limit: 1,
                windowDays: 30,
                category: category
            )
            let preview: String
            if let item = page.notifications.first {
                preview = "\(item.actorResolvedName) \(item.actionText)"
            } else {
                preview = emptyPreview(for: category)
            }
            return InboxCategorySummary(
                previewText: preview,
                unreadCount: page.unreadCount,
                hasContent: !page.notifications.isEmpty || page.unreadCount > 0
            )
        } catch {
            return InboxCategorySummary.empty
        }
    }

    private func loadRequestsSummary() async -> InboxCategorySummary {
        do {
            let page = try await directUseCase.inbox(folder: "requests", cursor: nil)
            guard let first = page.conversations.first else {
                return InboxCategorySummary.empty
            }
            let count = page.conversations.count
            // Fetch remaining pages only for count when there is a cursor — keep light for badge.
            var total = count
            var cursor = page.nextCursor
            var safety = 0
            while let next = cursor, !next.isEmpty, safety < 5 {
                safety += 1
                let more = try await directUseCase.inbox(folder: "requests", cursor: next)
                total += more.conversations.count
                cursor = more.nextCursor
            }
            let name = first.peerDisplayName.isEmpty ? first.peerUsername : first.peerDisplayName
            let preview = first.previewText.isEmpty
                ? "\(name) sent a message"
                : "\(name): \(first.previewText)"
            return InboxCategorySummary(
                previewText: preview,
                unreadCount: total,
                hasContent: total > 0
            )
        } catch {
            return InboxCategorySummary.empty
        }
    }

    private func emptyPreview(for category: NotificationCategory) -> String {
        switch category {
        case .followers: return "People who follow you"
        case .activity: return "Likes, comments and mentions"
        case .system: return "Account and content updates"
        }
    }
}
