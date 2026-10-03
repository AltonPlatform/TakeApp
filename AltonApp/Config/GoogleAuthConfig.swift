import Foundation
import GoogleSignIn

enum GoogleAuthConfig {
    private static let plistName = "GoogleService-Info"

    static func configure() {
        guard let clientID = plistValue(for: "CLIENT_ID") else {
            assertionFailure(
                "Missing GoogleService-Info.plist with CLIENT_ID. " +
                "Copy GoogleService-Info.example.plist → GoogleService-Info.plist and fill in your iOS OAuth client."
            )
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    static var isConfigured: Bool {
        plistValue(for: "CLIENT_ID") != nil
    }

    static func plistValue(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: plistName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty,
              !value.hasPrefix("YOUR_") else {
            return nil
        }
        return value
    }
}
