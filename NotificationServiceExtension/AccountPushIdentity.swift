import Foundation
import UserNotifications

/// Shared between the app and the notification service extension.
enum AccountPushIdentity {
    static let appGroupID = "group.com.alton.altonApp"
    static let currentUserIDKey = "alton.currentUserID"

    private static var store: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func setCurrentUserID(_ userID: String?) {
        if let userID {
            store.set(userID, forKey: currentUserIDKey)
        } else {
            store.removeObject(forKey: currentUserIDKey)
        }
        // Mirror into standard defaults so older readers stay consistent.
        if store !== UserDefaults.standard {
            if let userID {
                UserDefaults.standard.set(userID, forKey: currentUserIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: currentUserIDKey)
            }
        }
    }

    static func currentUserID() -> String? {
        store.string(forKey: currentUserIDKey)
            ?? UserDefaults.standard.string(forKey: currentUserIDKey)
    }

    /// Fail-closed: missing current user or missing recipient means "not for this session".
    static func belongsToAnotherAccount(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let current = currentUserID(),
              let recipient = userInfo["user_id"] as? String
        else { return true }
        return recipient != current
    }

    /// Strip alert text, badge, and deep links so a stale push cannot leak another account.
    static func redact(_ content: UNMutableNotificationContent) {
        content.title = ""
        content.subtitle = ""
        content.body = ""
        content.badge = 0
        content.sound = nil
        content.attachments = []
        content.threadIdentifier = ""
        var info = content.userInfo
        info.removeValue(forKey: "deep_link")
        info.removeValue(forKey: "actor_name")
        info.removeValue(forKey: "avatar_url")
        info.removeValue(forKey: "image_url")
        content.userInfo = info
        content.interruptionLevel = .passive
    }
}
