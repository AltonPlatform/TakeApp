import UIKit

/// Instagram Stories share via pasteboard + `instagram-stories://` (no Facebook SDK).
enum InstagramStoriesShare {
    static var isAvailable: Bool {
        guard let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Shares a background image (and optional sticker / H.264 background video) to Instagram Stories.
    /// - Parameters:
    ///   - backgroundImageData: Full-bleed JPEG/PNG for Stories background.
    ///   - stickerImageData: Optional sticker (card / QR) layered on top.
    ///   - backgroundVideoURL: Optional local H.264 file URL (`com.instagram.sharedSticker.backgroundVideo`).
    @discardableResult
    static func share(
        backgroundImageData: Data?,
        stickerImageData: Data? = nil,
        backgroundVideoURL: URL? = nil,
        appID: String = MetaAppConfig.appID
    ) -> Bool {
        guard isAvailable else { return false }

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

        guard sticker["com.instagram.sharedSticker.backgroundImage"] != nil
            || sticker["com.instagram.sharedSticker.backgroundVideo"] != nil
            || sticker["com.instagram.sharedSticker.stickerImage"] != nil else {
            return false
        }

        UIPasteboard.general.setItems(
            [sticker],
            options: [
                .expirationDate: Date().addingTimeInterval(60 * 5),
            ]
        )

        guard let url = URL(string: "instagram-stories://share?source_application=\(appID)") else {
            return false
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }
}

/// Custom share-sheet activity that posts to Instagram Stories when installed.
final class InstagramStoriesActivity: UIActivity {
    private let backgroundImage: UIImage?
    private let stickerImage: UIImage?
    private let backgroundVideoURL: URL?
    private let onShared: () -> Void

    init(
        backgroundImage: UIImage?,
        stickerImage: UIImage?,
        backgroundVideoURL: URL? = nil,
        onShared: @escaping () -> Void = {}
    ) {
        self.backgroundImage = backgroundImage
        self.stickerImage = stickerImage
        self.backgroundVideoURL = backgroundVideoURL
        self.onShared = onShared
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .share }

    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.alton.altonApp.instagram-stories")
    }

    override var activityTitle: String? { "Instagram Stories" }

    override var activityImage: UIImage? {
        UIImage(systemName: "camera.circle.fill")
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        InstagramStoriesShare.isAvailable
            && (backgroundImage != nil || stickerImage != nil || backgroundVideoURL != nil)
    }

    override func prepare(withActivityItems activityItems: [Any]) {}

    override func perform() {
        let backgroundData = backgroundImage?.jpegData(compressionQuality: 0.9)
        let stickerData = stickerImage?.pngData()
        let ok = InstagramStoriesShare.share(
            backgroundImageData: backgroundData,
            stickerImageData: stickerData,
            backgroundVideoURL: backgroundVideoURL
        )
        if ok {
            onShared()
        }
        activityDidFinish(ok)
    }
}
