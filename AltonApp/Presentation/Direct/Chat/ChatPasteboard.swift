import Foundation
import Nuke
import UniformTypeIdentifiers
import UIKit

enum ChatPasteboard {
    @MainActor
    static func copyText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
    }

    /// Copies still image or animated GIF data to the pasteboard.
    @MainActor
    static func copyMedia(from message: DMMessage) async -> Bool {
        if let data = message.localImageData, let image = UIImage(data: data) {
            UIPasteboard.general.image = image
            return true
        }
        guard let url = message.mediaURL ?? message.mediaThumbURL else { return false }
        do {
            let (data, _) = try await ImagePipeline.shared.data(for: ImageRequest(url: url))
            if message.kind == .gif {
                return copyAnimatedData(data)
            }
            if let image = UIImage(data: data) {
                UIPasteboard.general.image = image
                return true
            }
            return false
        } catch {
            return false
        }
    }

    @MainActor
    private static func copyAnimatedData(_ data: Data) -> Bool {
        if isGIF(data) {
            UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
            if let image = UIImage(data: data) {
                UIPasteboard.general.image = image
            }
            return true
        }
        // WebP / other: first frame as PNG so paste still works.
        if let image = AnimatedImageDecoder.make(data: data, maxPixelSize: 1024)
            ?? UIImage(data: data),
           let png = image.pngData()
        {
            UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
            UIPasteboard.general.image = image
            return true
        }
        return false
    }

    private static func isGIF(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let header = data.prefix(6)
        return header.starts(with: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
            || header.starts(with: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
    }
}
