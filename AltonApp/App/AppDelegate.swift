import UIKit
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        CrashReporting.configure()
        AnalyticsReporting.configure()
        Messaging.messaging().delegate = self
        GoogleAuthConfig.configure()
        ImagePipelineConfig.configure()
        CASManager.shared.initialize()
        UNUserNotificationCenter.current().delegate = self
        TemporaryCaptureStore.purgeStale()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task {
            await DevicePermissions.registerForRemoteNotificationsIfAuthorized()
        }
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        PushRegistrationCenter.handleDeepLink(url)
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        PushRegistrationCenter.register(fcmToken: fcmToken)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let link = userInfo["deep_link"] as? String,
           let url = URL(string: link),
           url.scheme == AppEnvironment.current.appURLScheme || url.scheme == "https" {
            PushRegistrationCenter.handleDeepLink(url)
        }
    }
}
