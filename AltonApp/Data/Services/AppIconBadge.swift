import Foundation
import UserNotifications

/// Keeps the SpringBoard app-icon badge in sync with inbox unread totals.
enum AppIconBadge {
    @MainActor
    static func set(_ count: Int) {
        let value = max(0, count)
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(value)
        }
    }

    @MainActor
    static func clear() {
        set(0)
    }
}
