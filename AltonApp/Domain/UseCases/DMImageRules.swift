import CoreGraphics
import UIKit

/// Client-side mirror of media-service `dm_target_dims` rules.
/// Aspect 1:3…3:1, min short edge 64 after crop, long edge ≤ 2048 (full) / 640 (thumb).
enum DMImageRules {
    static let maxAspect: CGFloat = 3
    static let minShortEdge: CGFloat = 64
    static let maxLongEdge: CGFloat = 2048
    static let thumbLongEdge: CGFloat = 640

    static func needsAspectCrop(_ image: UIImage) -> Bool {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return false }
        let ratio = size.width / size.height
        return ratio > maxAspect || ratio < 1 / maxAspect
    }

    /// Preferred crop aspect when the image is outside 1:3…3:1.
    static func preferredCropAspect(for image: UIImage) -> PhotoCropAspect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .story }
        if size.height / size.width > maxAspect {
            return .dmMaxPortrait
        }
        if size.width / size.height > maxAspect {
            return .dmMaxLandscape
        }
        return .original
    }

    /// Returns nil when short edge would be below minimum after aspect safety crop.
    static func isSendable(_ image: UIImage) -> Bool {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return false }
        let crop = centerCropToAspect(width: size.width, height: size.height)
        return min(crop.width, crop.height) >= minShortEdge
    }

    static func centerCropToAspect(width: CGFloat, height: CGFloat) -> CGSize {
        var w = width
        var h = height
        if w / h > maxAspect {
            w = h * maxAspect
        } else if h / w > maxAspect {
            h = w * maxAspect
        }
        return CGSize(width: w, height: h)
    }

    static func fitLongEdge(width: CGFloat, height: CGFloat, maxEdge: CGFloat) -> CGSize {
        let long = max(width, height)
        guard long > maxEdge else { return CGSize(width: width, height: height) }
        let scale = maxEdge / long
        return CGSize(width: floor(width * scale), height: floor(height * scale))
    }
}
