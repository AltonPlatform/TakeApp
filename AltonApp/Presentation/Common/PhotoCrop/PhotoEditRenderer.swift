import CoreImage
import CoreImage.CIFilterBuiltins
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

enum PhotoEditRenderer {
    private static let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
    ])
    private static let lock = NSLock()

    static func apply(
        to image: UIImage,
        adjustments: PhotoAdjustments,
        maxPixelSize: CGFloat? = nil
    ) -> UIImage {
        guard var ciImage = CIImage(image: image) else { return image }

        if let maxPixelSize {
            let longest = max(ciImage.extent.width, ciImage.extent.height)
            if longest > maxPixelSize {
                let scale = maxPixelSize / longest
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        ciImage = processedCIImage(
            from: ciImage,
            adjustments: adjustments
        )

        lock.lock()
        defer { lock.unlock() }
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    static func processedCIImage(
        from image: CIImage,
        adjustments: PhotoAdjustments
    ) -> CIImage {
        var ciImage = image

        if !adjustments.isIdentity {
            let controls = CIFilter.colorControls()
            controls.inputImage = ciImage
            controls.brightness = Float(adjustments.brightness)
            controls.contrast = Float(adjustments.contrast)
            controls.saturation = Float(adjustments.saturation)
            ciImage = controls.outputImage ?? ciImage

            if abs(adjustments.exposure) > 0.001 {
                let exposure = CIFilter.exposureAdjust()
                exposure.inputImage = ciImage
                exposure.ev = Float(adjustments.exposure)
                ciImage = exposure.outputImage ?? ciImage
            }

            if abs(adjustments.warmth) > 0.001 {
                let temp = CIFilter.temperatureAndTint()
                temp.inputImage = ciImage
                let kelvin = 6500 + adjustments.warmth * 2500
                temp.neutral = CIVector(x: CGFloat(kelvin), y: 0)
                temp.targetNeutral = CIVector(x: 6500, y: 0)
                ciImage = temp.outputImage ?? ciImage
            }
        }

        return ciImage
    }

    static func renderCGImage(_ image: CIImage) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return context.createCGImage(image, from: image.extent)
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
}
