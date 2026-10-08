import LinkPresentation
import SwiftUI
import UIKit

/// Payload for the system share sheet: excerpt text + URL + rich link metadata.
struct PostSharePayload: Equatable, Sendable {
    let url: URL
    let textExcerpt: String?
    let username: String?

    /// Share sheet message, e.g. `"Hello — @alice in Take"`.
    var shareMessage: String {
        let excerpt = (textExcerpt ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped: String = {
            guard !excerpt.isEmpty else { return "" }
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

    func makeCoordinator() -> Coordinator {
        Coordinator(payload: payload)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = context.coordinator.itemSource
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
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
