import UIKit
import os

private let storiesLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AltonApp", category: "InstagramStories")

/// Instagram Stories share via pasteboard + `instagram-stories://` (no Facebook SDK).
enum InstagramStoriesShare {
    static var isAvailable: Bool {
        guard let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Shares a background image (and optional sticker / H.264 background video) to Instagram Stories.
    /// - Parameters:
    ///   - backgroundImageData: Full-bleed JPEG/PNG for Stories background.
    ///   - stickerImageData: Optional sticker layered on top.
    ///   - backgroundVideoURL: Optional local H.264 file URL (`com.instagram.sharedSticker.backgroundVideo`).
    ///   - contentURL: Optional tappable link attached to the story (Spotify/TikTok-style),
    ///     mapped to `com.instagram.sharedSticker.contentURL`.
    @discardableResult
    static func share(
        backgroundImageData: Data?,
        stickerImageData: Data? = nil,
        backgroundVideoURL: URL? = nil,
        contentURL: URL? = nil,
        appID: String = MetaAppConfig.appID
    ) -> Bool {
        storiesLog.info("share begin available=\(isAvailable, privacy: .public) bg=\(backgroundImageData?.count ?? 0, privacy: .public)")
        guard isAvailable else {
            storiesLog.error("share abort: Instagram Stories URL not available")
            return false
        }

        guard let sticker = pasteboardPayload(
            backgroundImageData: backgroundImageData,
            stickerImageData: stickerImageData,
            backgroundVideoURL: backgroundVideoURL,
            contentURL: contentURL,
            appID: appID
        ) else {
            storiesLog.error("share abort: no sticker payload")
            return false
        }

        storiesLog.info("share setItems pasteboard")
        UIPasteboard.general.setItems(
            [sticker],
            options: [
                .expirationDate: Date().addingTimeInterval(60 * 5),
            ]
        )

        guard let url = URL(string: "instagram-stories://share?source_application=\(appID)") else {
            storiesLog.error("share abort: bad URL")
            return false
        }
        storiesLog.info("share openURL")
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        storiesLog.info("share openURL dispatched")
        return true
    }

    /// Pure builder for the `com.instagram.sharedSticker.*` pasteboard payload.
    /// Returns `nil` when the payload carries no media (Instagram would show a blank story).
    static func pasteboardPayload(
        backgroundImageData: Data?,
        stickerImageData: Data? = nil,
        backgroundVideoURL: URL? = nil,
        contentURL: URL? = nil,
        appID: String = MetaAppConfig.appID
    ) -> [String: Any]? {
        var sticker: [String: Any] = [
            "com.instagram.sharedSticker.appID": appID,
        ]
        if let backgroundImageData {
            sticker["com.instagram.sharedSticker.backgroundImage"] = backgroundImageData
        }
        if let stickerImageData {
            sticker["com.instagram.sharedSticker.stickerImage"] = stickerImageData
        }
        if let backgroundVideoURL,
           backgroundVideoURL.isFileURL,
           let videoData = try? Data(contentsOf: backgroundVideoURL) {
            sticker["com.instagram.sharedSticker.backgroundVideo"] = videoData
        }
        if let contentURL {
            sticker["com.instagram.sharedSticker.contentURL"] = contentURL.absoluteString
        }

        let hasMedia = sticker["com.instagram.sharedSticker.backgroundImage"] != nil
            || sticker["com.instagram.sharedSticker.stickerImage"] != nil
            || sticker["com.instagram.sharedSticker.backgroundVideo"] != nil
        guard hasMedia else { return nil }
        return sticker
    }
}