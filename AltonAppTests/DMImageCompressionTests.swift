import UIKit
import XCTest
@testable import AltonApp

final class DMImageCompressionTests: XCTestCase {
    func testCompressPreservesAspectForRightOrientation() {
        // Camera stills often arrive as landscape CGImage + .right (displayed as portrait).
        let cg = solidCGImage(width: 400, height: 300)
        let image = UIImage(cgImage: cg, scale: 1, orientation: .right)
        XCTAssertEqual(image.size.width, 300, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 400, accuracy: 0.5)

        guard let compressed = DirectUseCase.compressImageForDM(image) else {
            return XCTFail("expected compressed image")
        }
        let ratio = CGFloat(compressed.width) / CGFloat(compressed.height)
        XCTAssertEqual(ratio, 300.0 / 400.0, accuracy: 0.02)
        XCTAssertGreaterThan(compressed.height, compressed.width)
    }

    func testCompressPreservesAspectForUpOrientation() {
        let cg = solidCGImage(width: 300, height: 400)
        let image = UIImage(cgImage: cg, scale: 1, orientation: .up)
        guard let compressed = DirectUseCase.compressImageForDM(image) else {
            return XCTFail("expected compressed image")
        }
        let ratio = CGFloat(compressed.width) / CGFloat(compressed.height)
        XCTAssertEqual(ratio, 300.0 / 400.0, accuracy: 0.02)
    }

    private func solidCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 255, count: height * bytesPerRow)
        let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
