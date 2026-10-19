import LinkPresentation
import SwiftUI
import UIKit

/// Payload for the system share sheet: excerpt text + URL + rich link metadata.
struct PostSharePayload: Equatable, Sendable {
    let url: URL
    let textExcerpt: String?
    let username: String?
    /// Optional poster / thumbnail used when rendering the share card.
    let posterURL: URL?
    /// Optional local H.264 file for Instagram Stories background video.
    let localVideoURL: URL?
    /// Server post id for in-app Direct share (`POST /dm/share`).
    let postID: String?

    init(
        url: URL,
        textExcerpt: String? = nil,
        username: String? = nil,
        posterURL: URL? = nil,
        localVideoURL: URL? = nil,
        postID: String? = nil
    ) {
        self.url = url
        self.textExcerpt = textExcerpt
        self.username = username
        self.posterURL = posterURL
        self.localVideoURL = localVideoURL
        self.postID = postID
    }

    /// Share sheet message, e.g. `"Hello — @alice in Take"`.
    var shareMessage: String {
        let clipped: String = {
            guard let excerpt = Self.meaningfulExcerpt(textExcerpt) else { return "" }
            if excerpt.count <= 120 { return excerpt }
            let idx = excerpt.index(excerpt.startIndex, offsetBy: 120)
            return String(excerpt[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }()
        let handle: String = {
            guard let username, !username.isEmpty else { return "Take" }
            let bare = username.hasPrefix("@") ? String(username.dropFirst()) : username
            return "@\(bare) in Take"
        }()
        if clipped.isEmpty {
            return handle
        }
        return "\(clipped) — \(handle)"
    }

    var linkTitle: String {
        if let username, !username.isEmpty {
            let bare = username.hasPrefix("@") ? String(username.dropFirst()) : username
            return "@\(bare) on Take"
        }
        return "Take"
    }

    /// Drops whitespace-only and punctuation-only stubs like `"."` / `"…"`.
    static func meaningfulExcerpt(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let junk: Set<Character> = ["!", ".", ",", "-", "–", "—", "·", "…", "•", " ", "\t", "\n"]
        if trimmed.allSatisfy({ junk.contains($0) }) { return nil }
        return trimmed
    }
}

enum ShareChannelMapper {
    /// Maps `UIActivity.ActivityType` to engagement `channel` values accepted by the API.
    static func channel(for activityType: UIActivity.ActivityType?) -> String {
        guard let activityType else { return "other" }
        let raw = activityType.rawValue.lowercased()
        if activityType == .message || raw.contains("message") {
            return "messages"
        }
        if activityType == .copyToPasteboard || raw.contains("copy") {
            return "copy"
        }
        if raw.contains("telegram") || raw.contains("ph.telegra") {
            return "telegram"
        }
        if raw.contains("instagram") || raw.contains("burbn") {
            return "instagram"
        }
        return "other"
    }
}

/// System share sheet fallback ("More…" in `PostShareSheet`).
///
/// Shares **URL-only** — like TikTok/X: destinations fetch the OG-tag preview
/// from the link themselves. No big card image is attached, and no card is
/// rendered (the old coordinator rendered a 1080×1920 card on the main thread
/// in `init`).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let payload: PostSharePayload
    /// `(completed, channel)` — channel is set only when the user finished a share.
    let onComplete: (_ completed: Bool, _ channel: String?) -> Void

    /// Backward-compatible initializer for plain URL shares (comments, etc.).
    init(items: [Any], onComplete: @escaping (Bool) -> Void) {
        let url = items.compactMap { $0 as? URL }.first
            ?? (items.compactMap { $0 as? String }.first).flatMap(URL.init(string:))
        let text = items.compactMap { $0 as? String }.first
        self.payload = PostSharePayload(url: url ?? URL(string: "https://alton.social")!, textExcerpt: text, username: nil)
        self.onComplete = { completed, _ in onComplete(completed) }
    }

    init(payload: PostSharePayload, onComplete: @escaping (_ completed: Bool, _ channel: String?) -> Void) {
        self.payload = payload
        self.onComplete = onComplete
    }

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(payload: payload)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [context.coordinator.itemSource],
            applicationActivities: []
        )
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            if completed {
                onComplete(true, ShareChannelMapper.channel(for: activityType))
            } else {
                onComplete(false, nil)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    @MainActor
    final class Coordinator {
        let itemSource: PostShareItemSource

        init(payload: PostSharePayload) {
            self.itemSource = PostShareItemSource(payload: payload)
        }
    }
}

final class PostShareItemSource: NSObject, UIActivityItemSource {
    private let payload: PostSharePayload

    init(payload: PostSharePayload) {
        self.payload = payload
        super.init()
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        payload.url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        // Copy-pasteboard prefers plain URL; messaging apps get text + URL.
        if activityType == .copyToPasteboard {
            return payload.url
        }
        return "\(payload.shareMessage)\n\(payload.url.absoluteString)"
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        payload.linkTitle
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = payload.url
        metadata.url = payload.url
        metadata.title = payload.linkTitle
        return metadata
    }
}