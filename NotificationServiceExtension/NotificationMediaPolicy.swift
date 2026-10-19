import Foundation

enum NotificationMediaPolicy {
    static let communicationTypes: Set<String> = [
        "comment", "reply", "mention", "like", "follow", "repost", "profile_view", "dm",
    ]

    /// Glyph drawn in the communication-notification avatar when the sender has no photo.
    static func avatarInitial(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let source = withoutAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }
    static let maxImageBytes = 512 * 1024

    static func isCommunicationEvent(_ type: String?) -> Bool {
        guard let type, !type.isEmpty else { return false }
        return communicationTypes.contains(type)
    }

    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard let host = normalizedHost(of: url) else { return false }

        if isLoopbackHost(host) {
            return scheme == "http" || scheme == "https"
        }
        guard scheme == "https" else { return false }
        if isBlockedIPHost(host) { return false }
        return isTrustedMediaHost(host)
    }

    static func normalizedHost(of url: URL) -> String? {
        url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func isTrustedMediaHost(_ host: String) -> Bool {
        host == "altons.trade" || host.hasSuffix(".altons.trade")
    }

    static func isBlockedIPHost(_ host: String) -> Bool {
        if host.contains(":") {
            return host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
        }
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        let a = parts[0]
        let b = parts[1]
        if a == 0 || a == 10 || a == 127 { return true }
        if a == 169 && b == 254 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 192 && b == 168 { return true }
        return false
    }
}
