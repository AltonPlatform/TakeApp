import XCTest
import UIKit
@testable import AltonApp

final class PhotoCropEditorTests: XCTestCase {
    func testStraightenCoverScaleIsIdentityAtZero() {
        let scale = PhotoCropEditorView.straightenCoverScale(
            degrees: 0,
            imageSize: CGSize(width: 400, height: 400),
            cropSize: CGSize(width: 200, height: 200)
        )
        XCTAssertEqual(scale, 1, accuracy: 0.001)
    }

    func testStraightenCoverScaleCoversSquareAt45() {
        let scale = PhotoCropEditorView.straightenCoverScale(
            degrees: 45,
            imageSize: CGSize(width: 400, height: 400),
            cropSize: CGSize(width: 200, height: 200)
        )
        XCTAssertEqual(scale, sqrt(2), accuracy: 0.02)
    }

    func testClampOffsetAtIdentityLeavesRoomOnlyWhenZoomed() {
        let crop = CGSize(width: 200, height: 200)
        let image = CGSize(width: 200, height: 200)
        let atRest = PhotoCropEditorView.clampOffset(
            CGSize(width: 80, height: 0),
            scale: 1,
            cropSize: crop,
            imageSize: image
        )
        XCTAssertEqual(atRest.width, 0, accuracy: 0.5)

        let zoomed = PhotoCropEditorView.clampOffset(
            CGSize(width: 80, height: 0),
            scale: 2,
            cropSize: crop,
            imageSize: image
        )
        XCTAssertEqual(zoomed.width, 80, accuracy: 0.5)
    }

    func testClampOffsetWithStraightenAtMinScaleRecenters() {
        let clamped = PhotoCropEditorView.clampOffset(
            CGSize(width: 40, height: 30),
            scale: 1,
            cropSize: CGSize(width: 200, height: 200),
            imageSize: CGSize(width: 400, height: 400),
            straightenDegrees: 25
        )
        XCTAssertEqual(clamped.width, 0, accuracy: 1)
        XCTAssertEqual(clamped.height, 0, accuracy: 1)
    }

    func testCropExportUsesSourceResolutionNotViewport() {
        let source = Self.solidImage(size: CGSize(width: 200, height: 100), color: .red)
        let cropped = PhotoCropEditorView.crop(
            image: source,
            cropSize: CGSize(width: 50, height: 50),
            scale: 1,
            offset: .zero
        )
        XCTAssertEqual(cropped.size.width, 100, accuracy: 1)
        XCTAssertEqual(cropped.size.height, 100, accuracy: 1)
        XCTAssertEqual(cropped.scale, 1, accuracy: 0.01)
    }

    func testCropExportHonorsLiveScaleAndOffset() throws {
        let source = Self.splitImage(size: CGSize(width: 200, height: 100))
        let centered = PhotoCropEditorView.crop(
            image: source,
            cropSize: CGSize(width: 50, height: 50),
            scale: 1,
            offset: .zero
        )
        let panned = PhotoCropEditorView.crop(
            image: source,
            cropSize: CGSize(width: 50, height: 50),
            scale: 1,
            offset: CGSize(width: 25, height: 0)
        )
        // Positive offset slides the photo right, so the right edge of the crop
        // moves from the blue half onto the red half.
        let centeredRight = try Self.pixel(centered, at: CGPoint(x: 90, y: 50))
        let pannedRight = try Self.pixel(panned, at: CGPoint(x: 90, y: 50))
        XCTAssertGreaterThan(centeredRight[2], 200)
        XCTAssertGreaterThan(pannedRight[0], 200)
        XCTAssertNotEqual(centeredRight[2], pannedRight[2])
    }

    func testCropExportWithStraightenDoesNotLeaveBlackCorners() throws {
        let source = Self.solidImage(size: CGSize(width: 300, height: 300), color: .red)
        let cropped = PhotoCropEditorView.crop(
            image: source,
            cropSize: CGSize(width: 120, height: 120),
            scale: 1,
            offset: .zero,
            straightenDegrees: 20
        )
        let cgImage = try XCTUnwrap(cropped.cgImage)
        let corners = [
            CGPoint(x: 1, y: 1),
            CGPoint(x: CGFloat(cgImage.width - 2), y: 1),
            CGPoint(x: 1, y: CGFloat(cgImage.height - 2)),
            CGPoint(x: CGFloat(cgImage.width - 2), y: CGFloat(cgImage.height - 2)),
        ]
        for point in corners {
            let pixel = try Self.pixel(cropped, at: point)
            XCTAssertGreaterThan(pixel[0], 200, "Expected red crop corner, got \(pixel)")
        }
    }

    func testCropFrameSizeChangesHeightWhenAspectChangesAtFullWidth() {
        let available = CGSize(width: 350, height: 500)
        let image = CGSize(width: 400, height: 400)
        let portrait = PhotoCropEditorView.cropFrameSize(
            in: available,
            imageSize: image,
            aspect: .portrait,
            mask: .rectangle
        )
        let landscape = PhotoCropEditorView.cropFrameSize(
            in: available,
            imageSize: image,
            aspect: .landscape,
            mask: .rectangle
        )
        XCTAssertEqual(portrait.width, landscape.width, accuracy: 0.5)
        XCTAssertGreaterThan(portrait.height, landscape.height + 10)
    }

    private static func solidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Left half red, right half blue.
    private static func splitImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            UIColor.blue.setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
    }

    private static func pixel(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(
            cgImage,
            in: CGRect(
                x: -point.x,
                y: -point.y,
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        )
        return pixel
    }
}
