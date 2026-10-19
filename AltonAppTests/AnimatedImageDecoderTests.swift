import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import AltonApp

final class AnimatedImageDecoderTests: XCTestCase {
    func testDecodesMultiFrameGIFAsAnimated() throws {
        let data = try makeTestGIF(delays: [0.1, 0.2, 0.1])
        let image = AnimatedImageDecoder.make(data: data, maxPixelSize: 64)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.images?.count, 4, "GCD expansion of 10+20+10 centiseconds should yield 4 slots")
        let duration = image?.duration ?? 0
        XCTAssertEqual(duration, 0.4, accuracy: 0.05)
    }

    func testSingleFrameIsNotAnimated() throws {
        let data = try makeTestGIF(delays: [0.1])
        let image = AnimatedImageDecoder.make(data: data, maxPixelSize: 64)
        XCTAssertNotNil(image)
        XCTAssertNil(image?.images)
    }

    func testExpandFramesUsesGCD() {
        let frames = (0..<3).map { _ in UIImage() }
        let expanded = AnimatedImageDecoder.expandFrames(
            frames: frames,
            delays: [0.1, 0.2, 0.1]
        )
        XCTAssertEqual(expanded?.count, 4)
    }

    private func makeTestGIF(delays: [TimeInterval]) throws -> Data {
        let out = NSMutableData()
        let type = UTType.gif.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(out, type, delays.count, nil) else {
            throw XCTSkip("Could not create GIF destination")
        }

        for delay in delays {
            let frame = try solidCGImage(color: .red, size: 8)
            let props: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ] as [CFString: Any]
            ]
            CGImageDestinationAddImage(destination, frame, props as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("Could not finalize GIF")
        }
        return out as Data
    }

    private func solidCGImage(color: UIColor, size: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Could not create CGContext")
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else {
            throw XCTSkip("Could not make CGImage")
        }
        return image
    }
}
