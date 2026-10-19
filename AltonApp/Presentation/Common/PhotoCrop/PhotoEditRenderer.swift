import UIKit

struct PhotoAdjustments: Equatable {
    var brightness: Double = 0      // -0.5 ... 0.5
    var contrast: Double = 1       // 0.5 ... 1.5
    var saturation: Double = 1     // 0 ... 2
    var exposure: Double = 0       // -1.5 ... 1.5
    var warmth: Double = 0         // -1 ... 1

    var isIdentity: Bool {
        abs(brightness) < 0.001
            && abs(contrast - 1) < 0.001
            && abs(saturation - 1) < 0.001
            && abs(exposure) < 0.001
            && abs(warmth) < 0.001
    }
}

/// Color adjustments without Core Image / Metal.
/// A13 devices crash in CI/Metal with `-[AGXA13FamilyFunctionHandle resourceIndex]`
/// (same class of bug documented for Stories share).
enum PhotoEditRenderer {
    static func apply(
        to image: UIImage,
        adjustments: PhotoAdjustments,
        maxPixelSize: CGFloat? = nil
    ) -> UIImage {
        guard !adjustments.isIdentity else {
            if let maxPixelSize {
                return downscale(image, maxPixelSize: maxPixelSize) ?? image
            }
            return image
        }
        let source = maxPixelSize.flatMap { downscale(image, maxPixelSize: $0) } ?? image
        guard let cgImage = source.cgImage ?? source.photoCropFlattenedCGImage() else {
            return image
        }
        guard let adjusted = applyCPU(to: cgImage, adjustments: adjustments) else {
            return source
        }
        return UIImage(cgImage: adjusted, scale: source.scale, orientation: .up)
    }

    /// Preview / export path used by the crop canvas — CPU only.
    static func applyCPU(to cgImage: CGImage, adjustments: PhotoAdjustments) -> CGImage? {
        guard !adjustments.isIdentity else { return cgImage }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let count = width * height * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: count)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let brightness = adjustments.brightness
        let contrast = adjustments.contrast
        let saturation = adjustments.saturation
        let exposureMul = pow(2.0, adjustments.exposure)
        let warmth = adjustments.warmth

        var i = 0
        while i < count {
            let a = Double(pixels[i + 3]) / 255.0
            if a < 0.001 {
                i += 4
                continue
            }
            // Un-premultiply
            var r = Double(pixels[i]) / 255.0 / a
            var g = Double(pixels[i + 1]) / 255.0 / a
            var b = Double(pixels[i + 2]) / 255.0 / a

            // Exposure
            r *= exposureMul
            g *= exposureMul
            b *= exposureMul

            // Brightness + contrast (around mid-gray)
            r = ((r - 0.5) * contrast + 0.5) + brightness
            g = ((g - 0.5) * contrast + 0.5) + brightness
            b = ((b - 0.5) * contrast + 0.5) + brightness

            // Saturation
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            r = luma + (r - luma) * saturation
            g = luma + (g - luma) * saturation
            b = luma + (b - luma) * saturation

            // Warmth: nudge red/blue (approx temperature)
            if abs(warmth) > 0.001 {
                r += warmth * 0.08
                b -= warmth * 0.08
            }

            r = min(max(r, 0), 1)
            g = min(max(g, 0), 1)
            b = min(max(b, 0), 1)

            pixels[i] = UInt8(min(max(r * a * 255.0, 0), 255))
            pixels[i + 1] = UInt8(min(max(g * a * 255.0, 0), 255))
            pixels[i + 2] = UInt8(min(max(b * a * 255.0, 0), 255))
            i += 4
        }

        guard let out = context.makeImage() else { return nil }
        return out
    }

    static func rotate90Clockwise(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    static func flipHorizontal(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: image.size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func flipVertical(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: 0, y: image.size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func downscale(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxPixelSize else { return image }
        let scale = maxPixelSize / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension UIImage {
    func photoCropFlattenedCGImage() -> CGImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let flat = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return flat.cgImage
    }
}
