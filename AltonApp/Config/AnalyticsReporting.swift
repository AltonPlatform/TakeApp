import AppTrackingTransparency
import Foundation
import FirebaseAnalytics

/// Thin wrapper around Google Analytics for Firebase (GA4).
enum AnalyticsReporting {
    static func configure() {
        Analytics.setAnalyticsCollectionEnabled(true)

        let environment: String = switch AppEnvironment.current {
        case .development: "development"
        case .production: "production"
        }
        Analytics.setUserProperty(environment, forName: "environment")
        #if DEBUG
        Analytics.setUserProperty("true", forName: "debug_build")
        #else
        Analytics.setUserProperty("false", forName: "debug_build")
        #endif

        applyTrackingConsent(ATTrackingManager.trackingAuthorizationStatus)
    }

    static func setUser(id: String?) {
        Analytics.setUserID(id)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: parameters)
    }

    static func logScreen(_ name: String, class screenClass: String? = nil) {
        var parameters: [String: Any] = [
            AnalyticsParameterScreenName: name,
        ]
        if let screenClass {
            parameters[AnalyticsParameterScreenClass] = screenClass
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
    }

    static func logLogin(method: String) {
        Analytics.logEvent(
            AnalyticsEventLogin,
            parameters: [AnalyticsParameterMethod: method]
        )
    }

    static func logLogout() {
        Analytics.logEvent("logout", parameters: nil)
    }

    /// Maps ATT status to Analytics consent mode (ad-related signals).
    static func applyTrackingConsent(_ status: ATTrackingManager.AuthorizationStatus) {
        let adsGranted = status == .authorized
        Analytics.setConsent([
            .analyticsStorage: .granted,
            .adStorage: adsGranted ? .granted : .denied,
            .adUserData: adsGranted ? .granted : .denied,
            .adPersonalization: adsGranted ? .granted : .denied,
        ])
    }
}
