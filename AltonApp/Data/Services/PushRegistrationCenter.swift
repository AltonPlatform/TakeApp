import Foundation
import OSLog
import UIKit

enum PushRegistrationCenter {
    private static var apiClient: APIClient?
    private static var lastFcmToken: String?
    static var onDeepLink: ((URL) -> Void)?

    private static let logger = Logger(subsystem: "com.alton.altonApp", category: "Push")

    static func configure(apiClient: APIClient) {
        self.apiClient = apiClient
        if let lastFcmToken {
            register(fcmToken: lastFcmToken)
        }
        Task {
            await DevicePermissions.registerForRemoteNotificationsIfAuthorized()
        }
    }

    static func handleDeepLink(_ url: URL) {
        onDeepLink?(url)
    }

    static func register(fcmToken: String) {
        lastFcmToken = fcmToken
        guard let apiClient else {
            logger.debug("Deferred FCM registration — API client not ready")
            return
        }
        Task {
            await PushRegistrationService.registerFcmToken(fcmToken, apiClient: apiClient)
        }
    }

    static func reRegisterIfNeeded() {
        Task {
            await DevicePermissions.registerForRemoteNotificationsIfAuthorized()
            if let lastFcmToken, let apiClient {
                await PushRegistrationService.registerFcmToken(lastFcmToken, apiClient: apiClient)
            }
        }
    }

    static func unregisterOnLogout() async {
        guard let lastFcmToken, let apiClient else { return }
        await PushRegistrationService.unregisterFcmToken(lastFcmToken, apiClient: apiClient)
        self.lastFcmToken = nil
    }
}
