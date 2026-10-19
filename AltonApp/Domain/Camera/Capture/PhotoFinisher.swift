import AVFoundation
import ImageIO
import UIKit

enum DMCameraAspect: String, CaseIterable, Identifiable, Sendable {
    case fourByThree
    case sixteenByNine
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourByThree: return "4:3"
        case .sixteenByNine: return "16:9"
        case .square: return "1:1"
        }
    }

    /// Width / height of the final crop.
    var ratio: CGFloat {
        switch self {
        case .fourByThree: return 3.0 / 4.0
        case .sixteenByNine: return 9.0 / 16.0
        case .square: return 1
        }
    }
}

/// Still finish for Direct camera.
///
/// **No Core Image / Metal.** On A13, even `CIContext(options: [.useSoftwareRenderer: true])`
/// still touches AGX and crashes with `-[AGXA13FamilyFunctionHandle resourceIndex]`
/// (same class of bug as Stories share / `PostShareCardRenderer`).
/// Path: ImageIO decode → CGContext crop/mirror/scale → optional CPU color grade → ImageIO JPEG.
enum PhotoFinisher {
    struct Options: Sendable {
        var filterID: String = "original"
        var beautyIntensity: Double = 0
        var aspect: DMCameraAspect = .fourByThree
        var mirror: Bool = false
        var maxLongEdge: CGFloat = DMImageRules.maxLongEdge
        var previewLongEdge: CGFloat = 240
        var jpegQuality: CGFloat = 0.88
    }

    struct Result: Sendable {
        let fileURL: URL
        let preview: UIImage
        let width: Int
        let height: Int
    }

    /// Center-crop rect that matches `aspect` inside `size`.
    static func cropRect(for size: CGSize, aspect: DMCameraAspect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let target = aspect.ratio
        let current = size.width / size.height
        if abs(current - target) < 0.001 {
            return CGRect(origin: .zero, size: size)
        }
        if current > target {
            let width = size.height * target
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / target
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }

    /// Picks the smallest `CMVideoDimensions` whose long edge is at least `minLongEdge`.
    static func preferredPhotoDimensions(
        from supported: [CMVideoDimensions],
        minLongEdge: Int32 = Int32(DMImageRules.maxLongEdge)
    ) -> CMVideoDimensions? {
        let sorted = supported.sorted {
            max($0.width, $0.height) < max($1.width, $1.height)
        }
        return sorted.first { max($0.width, $0.height) >= minLongEdge } ?? sorted.last
    }

    static func finish(sourceURL: URL, options: Options) throws -> Result {
        let decoded = try decodeOrientedImage(at: sourceURL, maxLongEdge: options.maxLongEdge * 1.5)
        let sourceSize = CGSize(width: decoded.width, height: decoded.height)
        let crop = cropRect(for: sourceSize, aspect: options.aspect)
        let fitted = DMImageRules.fitLongEdge(
            width: crop.width,
            height: crop.height,
            maxEdge: options.maxLongEdge
        )
        let outW = max(1, Int(fitted.width.rounded()))
        let outH = max(1, Int(fitted.height.rounded()))

        guard var cg = renderCropped(
            source: decoded,
            crop: crop,
            outputWidth: outW,
            outputHeight: outH,
            mirror: options.mirror
        ) else {
            throw CaptureError.photoCaptureFailed
        }

        if let adjustments = colorAdjustments(
            filterID: options.filterID,
            beautyIntensity: options.beautyIntensity
        ), let graded = PhotoEditRenderer.applyCPU(to: cg, adjustments: adjustments) {
            cg = graded
        }

        guard let data = CPUImageIO.encodeJPEG(cgImage: cg, quality: options.jpegQuality) else {
            throw CaptureError.photoCaptureFailed
        }

        let fileURL = TemporaryCaptureStore.photoURL()
        try data.write(to: fileURL, options: .atomic)

        let previewCG = CPUImageIO.scaled(cg, maxLongEdge: options.previewLongEdge) ?? cg
        return Result(
            fileURL: fileURL,
            preview: CPUImageIO.uiImage(from: previewCG),
            width: cg.width,
            height: cg.height
        )
    }

    /// Fast path when no filter/beauty/mirror: crop + re-encode only.
    static func finishPlain(sourceURL: URL, options: Options) throws -> Result {
        var opts = options
        opts.filterID = "original"
        opts.beautyIntensity = 0
        opts.mirror = false
        return try finish(sourceURL: sourceURL, options: opts)
    }

    static func decodeOrientedImage(at url: URL, maxLongEdge: CGFloat) throws -> CGImage {
        guard let image = CPUImageIO.decodeOrientedImage(at: url, maxLongEdge: maxLongEdge) else {
            throw CaptureError.photoCaptureFailed
        }
        return image
    }

    static func loadFullImage(at url: URL) throws -> UIImage {
        let cg = try decodeOrientedImage(at: url, maxLongEdge: DMImageRules.maxLongEdge * 2)
        return CPUImageIO.uiImage(from: cg)
    }

    // MARK: - CPU pipeline (no CI / Metal)

    private static func renderCropped(
        source: CGImage,
        crop: CGRect,
        outputWidth: Int,
        outputHeight: Int,
        mirror: Bool
    ) -> CGImage? {
        guard let ctx = CPUImageIO.makeBitmapContext(width: outputWidth, height: outputHeight) else {
            return nil
        }
        // Raw Quartz (no CTM y-flip): `CGContext.draw` is upright in the final CGImage
        // (same invariant as PostShareCardRenderer). Only mirror flips X for front camera.
        if mirror {
            ctx.translateBy(x: CGFloat(outputWidth), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        let dest = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        let clamped = clampCrop(crop, in: CGSize(width: source.width, height: source.height))
        if let cropped = source.cropping(to: clamped) {
            ctx.draw(cropped, in: dest)
        } else {
            ctx.draw(source, in: dest)
        }
        return ctx.makeImage()
    }

    private static func clampCrop(_ crop: CGRect, in size: CGSize) -> CGRect {
        let integral = crop.integral
        let x = max(0, min(integral.origin.x, size.width - 1))
        let y = max(0, min(integral.origin.y, size.height - 1))
        let w = max(1, min(integral.width, size.width - x))
        let h = max(1, min(integral.height, size.height - y))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Maps live CI filters / beauty to CPU `PhotoAdjustments` (no Metal).
    private static func colorAdjustments(filterID: String, beautyIntensity: Double) -> PhotoAdjustments? {
        var adjustments = PhotoAdjustments()
        switch filterID {
        case "vivid":
            adjustments.saturation = 1.4
            adjustments.contrast = 1.2
        case "fade":
            adjustments.saturation = 0.85
            adjustments.contrast = 0.9
            adjustments.brightness = 0.03
        case "noir":
            adjustments.saturation = 0
            adjustments.contrast = 1.15
        case "warm":
            adjustments.warmth = 0.65
        case "cool":
            adjustments.warmth = -0.65
        case "vignette":
            // Approximate vignette with slight contrast lift; full radial darken skipped.
            adjustments.contrast = 1.1
            adjustments.brightness = -0.02
        default:
            break
        }

        let beauty = min(max(beautyIntensity, 0), 1)
        if beauty > 0.01 {
            adjustments.brightness += 0.05 * beauty
            adjustments.contrast *= (1 - 0.05 * beauty)
            adjustments.saturation = max(0, adjustments.saturation * (1 - 0.08 * beauty))
        }

        return adjustments.isIdentity ? nil : adjustments
    }
}
