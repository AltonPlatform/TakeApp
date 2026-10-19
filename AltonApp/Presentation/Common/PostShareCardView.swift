import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import os

private let shareCardLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AltonApp", category: "ShareCard")

/// Branded share card for Instagram Stories.
///
/// ## Coordinate model — the invariant that prevents the "upside-down card" bug
///
/// Everything is drawn in a **raw Quartz bitmap context: origin bottom-left,
/// y grows up, with no CTM flips anywhere**. In that single coordinate system
/// every primitive used here renders upright in the final image:
///
/// - `CTFrameDraw` (Core Text) renders upright in raw y-up contexts
///   (it only flips inside UIKit-style flipped contexts).
/// - `CGContext.draw(image, in:)` renders right side up in raw y-up contexts.
/// - `ctx.makeImage()` maps **high y to the top** of the final image.
///
/// The previous version mixed an unflipped gradient with a flipped
/// `drawForeground` and a re-flipped poster branch — three coordinate systems
/// in one canvas — and shipped an upside-down Stories card. Do not reintroduce
/// `translateBy`/`scaleBy` flips in this file. Orientation is guarded by
/// `renderOrientationProbe()` + pixel tests.
///
/// ## Metal / AGX safety
///
/// **No CoreImage at all** in this file — not even
/// `CIContext(options: [.useSoftwareRenderer: true])`. On A13 devices
/// CoreImage still touches Metal and crashed Stories share with
/// `-[AGXA13FamilyFunctionHandle resourceIndex]`. Also forbidden:
/// SwiftUI.ImageRenderer, UIGraphicsImageRenderer, `UIImage.jpegData` /
/// `pngData`. QR uses pure-Swift `QRCodeEncoder` + `CGContext.fill`.
/// JPEG encode uses ImageIO.
enum PostShareCardRenderer {
    static let canvasSize = CGSize(width: 1080, height: 1920)

    /// Brand colors (top → bottom of the final image).
    private static let brandNavy = (red: 0.07, green: 0.09, blue: 0.16)
    private static let brandPurple = (red: 0.18, green: 0.08, blue: 0.28)

    private static let sidePadding: CGFloat = 96
    /// Instagram covers the bottom ~310 px of a story with its own chrome.
    private static let footerBaseline: CGFloat = 320

    // MARK: - Public API

    static func render(payload: PostSharePayload, poster: CGImage? = nil) -> UIImage? {
        shareCardLog.info("render begin")
        defer { shareCardLog.info("render end") }
        guard let cgImage = makeCGImage(payload: payload, poster: poster) else {
            shareCardLog.error("render failed: nil cgImage")
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// JPEG bytes via ImageIO (never `UIImage` encode APIs — those can hit GPU).
    static func makeJPEG(payload: PostSharePayload, poster: CGImage? = nil, quality: CGFloat = 0.85) -> Data? {
        shareCardLog.info("makeJPEG begin")
        defer { shareCardLog.info("makeJPEG end") }
        guard let cgImage = makeCGImage(payload: payload, poster: poster) else { return nil }
        return encodeJPEG(cgImage: cgImage, quality: quality)
    }

    /// Minimal solid card — isolates pasteboard/openURL from complex drawing.
    static func solidBackgroundJPEG(quality: CGFloat = 0.85) -> Data? {
        shareCardLog.info("solidJPEG begin")
        defer { shareCardLog.info("solidJPEG end") }
        let w = Int(canvasSize.width)
        let h = Int(canvasSize.height)
        guard let ctx = makeBitmapContext(width: w, height: h) else { return nil }
        ctx.setFillColor(
            red: brandNavy.red,
            green: brandNavy.green,
            blue: brandNavy.blue,
            alpha: 1
        )
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cgImage = ctx.makeImage() else { return nil }
        return encodeJPEG(cgImage: cgImage, quality: quality)
    }

    /// Real QR code drawn with pure-Swift `QRCodeEncoder` + `CGBitmapContext.fill`.
    /// Returns `nil` when the string exceeds version-10 / ECC-M capacity.
    static func qrCode(for string: String, dimension: CGFloat) -> UIImage? {
        guard let matrix = QRCodeEncoder.encode(string) else { return nil }
        let quiet = 2
        let modules = matrix.size + quiet * 2
        let modulePx = max(1, Int(dimension) / modules)
        let pixelSize = modules * modulePx
        guard let ctx = makeBitmapContext(width: pixelSize, height: pixelSize) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        ctx.setFillColor(gray: 0, alpha: 1)
        // Raw Quartz y-up: matrix row 0 (top of QR) maps to high y so the
        // final CGImage shows finder patterns in the correct corners.
        for my in 0..<matrix.size {
            for mx in 0..<matrix.size where matrix.isDark(x: mx, y: my) {
                let px = (mx + quiet) * modulePx
                let py = (matrix.size - 1 - my + quiet) * modulePx
                ctx.fill(CGRect(x: px, y: py, width: modulePx, height: modulePx))
            }
        }
        guard let cgImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// Loads a poster from a local file with EXIF orientation baked into the
    /// pixels (`kCGImageSourceCreateThumbnailWithTransform`), so plain
    /// `CGContext.draw` can never show a rotated/mirrored photo. Also
    /// downsamples huge camera JPEGs before they hit the canvas.
    static func loadOrientedPoster(from fileURL: URL, maxPixelSize: CGFloat = 1920) -> CGImage? {
        guard fileURL.isFileURL else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else {
            shareCardLog.error("loadOrientedPoster failed: \(fileURL.lastPathComponent, privacy: .public)")
            return nil
        }
        return decodePosterData(data, maxPixelSize: maxPixelSize)
    }

    /// Downloads a remote poster (HTTPS only) and decodes it via ImageIO.
    /// Caps body size at 8 MB; short timeouts so Stories share never hangs.
    static func loadRemotePoster(from url: URL, maxPixelSize: CGFloat = 1920) async -> CGImage? {
        guard url.scheme?.lowercased() == "https" else {
            shareCardLog.error("loadRemotePoster reject scheme=\(url.scheme ?? "nil", privacy: .public)")
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, response) = try await posterSession.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                shareCardLog.error("loadRemotePoster http=\(http.statusCode, privacy: .public)")
                return nil
            }
            guard data.count <= maxRemotePosterBytes else {
                shareCardLog.error("loadRemotePoster oversized bytes=\(data.count, privacy: .public)")
                return nil
            }
            return decodePosterData(data, maxPixelSize: maxPixelSize)
        } catch {
            shareCardLog.error("loadRemotePoster failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// ImageIO decode + EXIF bake + downsample. Shared by local/remote loaders
    /// and unit tests (no network).
    static func decodePosterData(_ data: Data, maxPixelSize: CGFloat = 1920) -> CGImage? {
        guard !data.isEmpty else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            shareCardLog.error("decodePosterData failed")
            return nil
        }
        return thumbnail
    }

    private static let maxRemotePosterBytes = 8 * 1024 * 1024

    private static let posterSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    /// Test hook exercising every drawing primitive's orientation on one canvas:
    /// a red-top/blue-bottom image and a bold black "T" glyph. The upright
    /// result has the red band above the blue band, and the "T"'s widest dark
    /// row (its crossbar) at the top of the glyph. Any coordinate-system
    /// regression (an extra flip) flips both.
    static func renderOrientationProbe() -> UIImage? {
        guard let ctx = makeBitmapContext(width: Int(canvasSize.width), height: Int(canvasSize.height)) else {
            return nil
        }
        // White background.
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: canvasSize))

        // Image primitive: 400×400, red top half / blue bottom half.
        // Drawn at y ∈ [1100, 1500] → final-image rows [420, 820].
        if let bandContext = makeBitmapContext(width: 400, height: 400) {
            bandContext.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
            bandContext.fill(CGRect(x: 0, y: 200, width: 400, height: 200))
            bandContext.setFillColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)
            bandContext.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
            if let band = bandContext.makeImage() {
                ctx.draw(band, in: CGRect(x: 340, y: 1100, width: 400, height: 400))
            }
        }

        // Text primitive: bold "T" at y ∈ [1560, ~1900] → final-image rows [24, ~360].
        let glyph = NSAttributedString(string: "T", attributes: [
            .font: UIFont.systemFont(ofSize: 280, weight: .black),
            .foregroundColor: UIColor.black,
        ])
        draw(glyph, in: ctx, origin: CGPoint(x: 120, y: 1560), maxWidth: 500)

        guard let cgImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    // MARK: - Composition

    private static func makeCGImage(payload: PostSharePayload, poster: CGImage?) -> CGImage? {
        let w = Int(canvasSize.width)
        let h = Int(canvasSize.height)
        guard let ctx = makeBitmapContext(width: w, height: h) else { return nil }

        let hasMedia = poster != nil
        if let poster {
            // Full-bleed media (aspect-fill) + bottom scrim for the footer.
            ctx.draw(
                poster,
                in: aspectFillRect(
                    imageSize: CGSize(width: poster.width, height: poster.height),
                    canvas: canvasSize
                )
            )
            drawScrim(in: ctx)
        } else {
            drawBrandGradient(in: ctx)
            drawCenteredBrand(in: ctx, payload: payload)
        }

        drawFooter(in: ctx, payload: payload, hasMedia: hasMedia)
        return ctx.makeImage()
    }

    private static func makeBitmapContext(width: Int, height: Int) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // `data: nil` → CoreGraphics allocates CPU memory (no Metal IOSurface).
        // NOTE: intentionally NO flip here — see the coordinate-model notes
        // in the type documentation. High y = top of the final image.
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

    /// Dark bottom scrim so footer text stays readable over media.
    private static func drawScrim(in ctx: CGContext) {
        let colors = [
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.78),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) else { return }
        // y = 0 is the bottom of the final image.
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: 1050),
            options: []
        )
    }

    private static func drawBrandGradient(in ctx: CGContext) {
        let colors = [
            CGColor(red: brandNavy.red, green: brandNavy.green, blue: brandNavy.blue, alpha: 1),
            CGColor(red: brandPurple.red, green: brandPurple.green, blue: brandPurple.blue, alpha: 1),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) else {
            ctx.setFillColor(
                red: brandNavy.red,
                green: brandNavy.green,
                blue: brandNavy.blue,
                alpha: 1
            )
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
            return
        }
        // High y = top of the final image: navy top → purple bottom.
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: canvasSize.height),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
    }

    /// No-media fallback: big centered wordmark + handle.
    private static func drawCenteredBrand(in ctx: CGContext, payload: PostSharePayload) {
        let wordmark = attributed(
            "Take",
            fontSize: 140,
            weight: .bold,
            color: .white,
            alignment: .center
        )
        let wordmarkHeight = measureHeight(wordmark, maxWidth: canvasSize.width)
        let centerY = canvasSize.height * 0.62
        let wordmarkBottom = centerY - wordmarkHeight / 2
        draw(wordmark, in: ctx, origin: CGPoint(x: 0, y: wordmarkBottom), maxWidth: canvasSize.width)

        guard let handle = normalizedHandle(payload.username) else { return }
        let handleAttr = attributed(
            handle,
            fontSize: 48,
            weight: .medium,
            color: UIColor.white.withAlphaComponent(0.8),
            alignment: .center
        )
        draw(handleAttr, in: ctx, origin: CGPoint(x: 0, y: wordmarkBottom - 28), maxWidth: canvasSize.width)
    }

    /// Footer over media: QR plate + wordmark + handle + excerpt.
    /// No-media: QR plate only — brand lives in the centered block (no duplicate).
    private static func drawFooter(in ctx: CGContext, payload: PostSharePayload, hasMedia: Bool) {
        let contentWidth = canvasSize.width - sidePadding * 2

        // White QR plate (above Instagram's bottom chrome zone).
        let plateSize: CGFloat = 168
        let plateRect = CGRect(x: sidePadding, y: footerBaseline, width: plateSize, height: plateSize)
        let plate = CGPath(roundedRect: plateRect, cornerWidth: 28, cornerHeight: 28, transform: nil)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(plate)
        ctx.fillPath()

        drawQRModules(
            for: payload.url.absoluteString,
            in: ctx,
            plateRect: plateRect,
            inset: 14
        )

        guard hasMedia else { return }

        // Text stack, anchored above the plate (media template only).
        var anchor = plateRect.maxY + 52
        let wordmark = attributed("Take", fontSize: 96, weight: .bold, color: .white)
        draw(wordmark, in: ctx, origin: CGPoint(x: sidePadding, y: anchor), maxWidth: contentWidth)
        anchor += measureHeight(wordmark, maxWidth: contentWidth) + 32

        if let handle = normalizedHandle(payload.username) {
            let handleAttr = attributed(
                handle,
                fontSize: 44,
                weight: .medium,
                color: UIColor.white.withAlphaComponent(0.86)
            )
            draw(handleAttr, in: ctx, origin: CGPoint(x: sidePadding, y: anchor), maxWidth: contentWidth)
            anchor += measureHeight(handleAttr, maxWidth: contentWidth) + 36
        }

        if let excerpt = excerptAttributed(payload.textExcerpt, maxWidth: contentWidth) {
            draw(
                excerpt,
                in: ctx,
                origin: CGPoint(x: sidePadding, y: anchor),
                maxWidth: contentWidth,
                maxHeight: excerptLineCap
            )
        }
    }

    // MARK: - Text helpers

    private static var excerptLineCap: CGFloat {
        ceil(40 * 1.45) * 3
    }

    private static func excerptAttributed(_ text: String?, maxWidth: CGFloat) -> NSAttributedString? {
        guard let trimmed = PostSharePayload.meaningfulExcerpt(text) else { return nil }

        func attr(for candidate: String) -> NSAttributedString {
            NSAttributedString(string: candidate, attributes: [
                .font: UIFont.systemFont(ofSize: 40, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            ])
        }

        var candidate = trimmed
        while candidate.count > 24 {
            let attributes = attr(for: candidate)
            if measureHeight(attributes, maxWidth: maxWidth) <= excerptLineCap {
                return attributes
            }
            candidate = String(candidate.dropLast(12)) + "…"
        }
        return attr(for: candidate)
    }

    private static func normalizedHandle(_ username: String?) -> String? {
        guard let username, !username.isEmpty else { return nil }
        let bare = username.hasPrefix("@") ? String(username.dropFirst()) : username
        return "@\(bare)"
    }

    private static func attributed(
        _ string: String,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        mono: Bool = false,
        alignment: NSTextAlignment = .natural
    ) -> NSAttributedString {
        let font = mono
            ? UIFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
            : UIFont.systemFont(ofSize: fontSize, weight: weight)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        if alignment != .natural {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            attributes[.paragraphStyle] = paragraph
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private static func measureHeight(_ attr: NSAttributedString, maxWidth: CGFloat) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxWidth, height: 400),
            nil
        )
        return ceil(size.height)
    }

    private static func draw(
        _ attr: NSAttributedString,
        in ctx: CGContext,
        origin: CGPoint,
        maxWidth: CGFloat,
        maxHeight: CGFloat? = nil
    ) {
        var height = measureHeight(attr, maxWidth: maxWidth)
        if let maxHeight {
            height = min(height, maxHeight)
        }
        let path = CGPath(
            rect: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: height),
            transform: nil
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
    }

    // MARK: - QR drawing (no CoreImage)

    /// Fills QR modules directly into `ctx` — never creates an intermediate
    /// CIImage / UIImage that could touch Metal.
    private static func drawQRModules(
        for string: String,
        in ctx: CGContext,
        plateRect: CGRect,
        inset: CGFloat
    ) {
        guard let matrix = QRCodeEncoder.encode(string) else {
            shareCardLog.error("drawQRModules: encode failed (oversized URL?)")
            return
        }
        let quiet = 2
        let modules = matrix.size + quiet * 2
        let available = min(plateRect.width, plateRect.height) - inset * 2
        let modulePx = max(1, floor(available / CGFloat(modules)))
        let drawn = CGFloat(modules) * modulePx
        let originX = plateRect.midX - drawn / 2
        let originY = plateRect.midY - drawn / 2
        ctx.setFillColor(gray: 0, alpha: 1)
        for my in 0..<matrix.size {
            for mx in 0..<matrix.size where matrix.isDark(x: mx, y: my) {
                // Raw y-up: matrix row 0 → top of the plate in the final image
                // → high Quartz y.
                let px = originX + CGFloat(mx + quiet) * modulePx
                let py = originY + CGFloat(matrix.size - 1 - my + quiet) * modulePx
                ctx.fill(CGRect(x: px, y: py, width: modulePx, height: modulePx))
            }
        }
    }

    // MARK: - Geometry & encoding

    private static func aspectFillRect(imageSize: CGSize, canvas: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let scale = max(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    }

    private static func encodeJPEG(cgImage: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}