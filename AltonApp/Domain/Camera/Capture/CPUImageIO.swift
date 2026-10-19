import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UIKit

/// CPU-only image encode/decode helpers shared by still finish and markup export.
/// Never uses Core Image, Metal, `UIGraphicsImageRenderer`, or `UIImage.jpegData`
/// (those touch AGX on A13 — see `PostShareCardRenderer`).
enum CPUImageIO {
    static func makeBitmapContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Transparent bitmap for ink layers (eraser uses `.clear`).
    static func makeClearBitmapContext(width: Int, height: Int) -> CGContext? {
        guard let ctx = makeBitmapContext(width: width, height: height) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    static func encodeJPEG(cgImage: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func decodeOrientedImage(at url: URL, maxLongEdge: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxLongEdge),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func decodeOrientedThumbnail(from data: Data, maxLongEdge: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxLongEdge),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Scale a CGImage into a new bitmap (raw Quartz, no y-flip).
    static func scaled(_ image: CGImage, maxLongEdge: CGFloat) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let fitted = DMImageRules.fitLongEdge(width: w, height: h, maxEdge: maxLongEdge)
        let outW = max(1, Int(fitted.width.rounded()))
        let outH = max(1, Int(fitted.height.rounded()))
        if outW == Int(w), outH == Int(h) { return image }
        guard let ctx = makeBitmapContext(width: outW, height: outH) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return ctx.makeImage()
    }

    static func uiImage(from cgImage: CGImage) -> UIImage {
        UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
