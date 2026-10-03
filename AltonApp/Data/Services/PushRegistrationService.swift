import Foundation
import OSLog

enum PushRegistrationService {
    private static let logger = Logger(subsystem: "com.alton.altonApp", category: "Push")

    static func registerFcmToken(_ token: String, apiClient: APIClient) async {
        struct Body: Encodable {
            let platform: String
            let token: String
        }
        do {
            struct Response: Decodable { let success: Bool }
            let _: Response = try await apiClient.authorizedRequest(
                .registerDevice,
                body: Body(platform: "ios", token: token)
            )
            logger.info("FCM token registered")
        } catch {
            logger.error("FCM token registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func unregisterFcmToken(_ token: String, apiClient: APIClient) async {
        struct Body: Encodable {
            let platform: String
            let token: String
        }
        do {
            struct Response: Decodable { let success: Bool }
            let _: Response = try await apiClient.authorizedRequest(
                .unregisterDevice,
                body: Body(platform: "ios", token: token)
            )
            logger.info("FCM token unregistered")
        } catch {
            logger.error("FCM token unregister failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
