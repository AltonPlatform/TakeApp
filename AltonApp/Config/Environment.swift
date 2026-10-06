import Foundation
import os

enum AppEnvironment {
    case development
    case production

    static var current: AppEnvironment {
        #if ALTON_DEV
        return .development
        #else
        return .production
        #endif
    }

    /// REST API (feed, posts, refresh).
    var apiBaseURL: URL {
        switch self {
        case .development:
            return URL(string: "https://dev-api.altons.trade")!
        case .production:
            return URL(string: "https://api.altons.trade")!
        }
    }

    /// SSO service — passwordless auth providers.
    var ssoBaseURL: URL {
        switch self {
        case .development:
            return URL(string: "https://dev-sso.altons.trade")!
        case .production:
            return URL(string: "https://sso.altons.trade")!
        }
    }

    /// Media CDN (upload/playback URLs are built server-side from R2_PUBLIC_BASE_URL).
    var mediaBaseURL: URL {
        switch self {
        case .development:
            return URL(string: "https://dev-media.altons.trade")!
        case .production:
            return URL(string: "https://media.altons.trade")!
        }
    }

    /// WebAuthn relying party ID — must match WEBAUTHN_RP_ID on sso-service.
    var webAuthnRelyingPartyID: String {
        switch self {
        case .development:
            return "dev-sso.altons.trade"
        case .production:
            return "sso.altons.trade"
        }
    }

    var appURLScheme: String { "alton" }

    var magicLinkCallbackHost: String { "auth" }

    var magicLinkUniversalHosts: Set<String> {
        switch self {
        case .development:
            return ["dev-sso.altons.trade"]
        case .production:
            return ["sso.altons.trade"]
        }
    }

    var shareDomain: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AltonShareDomain") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }
        return "alton.social"
    }

    var shareUniversalHosts: Set<String> {
        var hosts = Set<String>()
        hosts.insert(shareDomain.lowercased())
        if let raw = Bundle.main.object(forInfoDictionaryKey: "AltonShareDomains") as? String {
            for part in raw.split(separator: ",") {
                let host = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !host.isEmpty, !host.hasPrefix("$(") {
                    hosts.insert(host)
                }
            }
        }
        hosts.insert("alton.social")
        return hosts
    }

    var trustedUploadHosts: Set<String> {
        switch self {
        case .development:
            return [
                "dev-media.altons.trade",
                "localhost",
                "127.0.0.1",
            ]
        case .production:
            return [
                "media.altons.trade",
            ]
        }
    }

    func isAllowedUploadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || (self == .development && scheme == "http"),
              let host = url.host?.lowercased() else {
            return false
        }
        if trustedUploadHosts.contains(host) {
            return true
        }
        // Direct Cloudflare R2 presigned PUT hosts (account.r2.cloudflarestorage.com).
        if host.hasSuffix(".r2.cloudflarestorage.com") || host == "r2.cloudflarestorage.com" {
            return true
        }
        // Dev: media-service on the Mac's LAN address (same Wi-Fi as the phone).
        if self == .development && isPrivateIPv4Host(host) {
            return true
        }
        return false
    }

    private func isPrivateIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    var defaultFeedLimit: Int { 20 }

    /// Builds a public playback URL from a storage object key (fallback when API omits playback_url).
    func playbackURL(forObjectKey objectKey: String) -> URL? {
        let key = objectKey.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !key.isEmpty else { return nil }

        var components = URLComponents(url: mediaBaseURL, resolvingAgainstBaseURL: false)
        let pathPrefix: String
        switch self {
        case .development:
            pathPrefix = "/objects"
        case .production:
            pathPrefix = ""
        }
        let basePath = components?.path ?? ""
        components?.path = "\(basePath)\(pathPrefix)/\(key)"
        return components?.url
    }
}

/// Structured logging for camera → editor export → upload pipeline.
/// Filter in Xcode Console: subsystem:com.alton.altonApp category:Editor|Media|Camera
enum PipelineLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.alton.altonApp"

    static let editor = Logger(subsystem: subsystem, category: "Editor")
    static let media = Logger(subsystem: subsystem, category: "Media")
    static let camera = Logger(subsystem: subsystem, category: "Camera")

    static func logError(_ logger: Logger, _ message: String, error: Error, file: String = #fileID, line: Int = #line) {
        let ns = error as NSError
        logger.error(
            "\(message, privacy: .public) domain=\(ns.domain, privacy: .public) code=\(ns.code) desc=\(ns.localizedDescription, privacy: .public) @\(file, privacy: .public):\(line)"
        )
        if !ns.userInfo.isEmpty {
            logger.debug("userInfo=\(String(describing: ns.userInfo), privacy: .public)")
        }
        CrashReporting.record(error, message: message, file: file, line: line)
        CrashReporting.log("\(message) domain=\(ns.domain) code=\(ns.code)")
    }

    static func fileSummary(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        let size = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "?"
        let exists = FileManager.default.fileExists(atPath: url.path)
        return "path=\(url.lastPathComponent) exists=\(exists) size=\(size)"
    }
}
