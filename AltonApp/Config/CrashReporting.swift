import Foundation
import FirebaseCrashlytics

/// Thin wrapper around Firebase Crashlytics for breadcrumbs, user context, and non-fatals.
enum CrashReporting {
    static func configure() {
        let crashlytics = Crashlytics.crashlytics()
        let environment: String = switch AppEnvironment.current {
        case .development: "development"
        case .production: "production"
        }
        crashlytics.setCustomValue(environment, forKey: "environment")
        #if DEBUG
        crashlytics.setCustomValue(true, forKey: "debug_build")
        #else
        crashlytics.setCustomValue(false, forKey: "debug_build")
        #endif
    }

    static func setUser(id: String?) {
        Crashlytics.crashlytics().setUserID(id ?? "")
    }

    static func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    static func setValue(_ value: Any?, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    /// Records a non-fatal error visible in the Crashlytics dashboard.
    static func record(
        _ error: Error,
        message: String? = nil,
        keys: [String: Any] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        if error is CancellationError { return }

        let crashlytics = Crashlytics.crashlytics()
        if let message, !message.isEmpty {
            crashlytics.log("\(message) @\(file):\(line)")
        }
        for (key, value) in keys {
            crashlytics.setCustomValue(value, forKey: key)
        }

        let nsError = error as NSError
        var userInfo = nsError.userInfo
        userInfo["alton_message"] = message ?? ""
        userInfo["alton_file"] = file
        userInfo["alton_line"] = line
        let enriched = NSError(domain: nsError.domain, code: nsError.code, userInfo: userInfo)
        crashlytics.record(error: enriched)
    }
}
