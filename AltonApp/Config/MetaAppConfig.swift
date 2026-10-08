import Foundation

enum MetaAppConfig {
    /// Facebook / Instagram App ID from Info.plist (`AltonMetaAppID`).
    /// Used as `source_application` for Instagram Stories pasteboard sharing (KAN-26 / KAN-45).
    static var appID: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AltonMetaAppID") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }
        return "1993576677971360"
    }
}
