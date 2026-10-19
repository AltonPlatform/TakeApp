import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AltonApp

final class PhotoFinisherTests: XCTestCase {
    func testCropRectForSquare() {
        let rect = PhotoFinisher.cropRect(for: CGSize(width: 300, height: 400), aspect: .square)
        XCTAssertEqual(rect.width, 300, accuracy: 0.5)
        XCTAssertEqual(rect.height, 300, accuracy: 0.5)
        XCTAssertEqual(rect.minY, 50, accuracy: 0.5)
    }

    func testCropRectForSixteenByNinePortrait() {
        let rect = PhotoFinisher.cropRect(for: CGSize(width: 300, height: 400), aspect: .sixteenByNine)
        // Portrait 9:16 → width/height = 0.5625; 300/400 = 0.75 so crop width.
        XCTAssertEqual(rect.width, 400 * (9.0 / 16.0), accuracy: 1)
        XCTAssertEqual(rect.height, 400, accuracy: 0.5)
    }

    func testPreferredPhotoDimensionsPicksSmallestAbove2048() {
        let dims: [CMVideoDimensions] = [
            CMVideoDimensions(width: 1280, height: 960),
            CMVideoDimensions(width: 1920, height: 1440),
            CMVideoDimensions(width: 4032, height: 3024),
            CMVideoDimensions(width: 8064, height: 6048)
        ]
        let picked = PhotoFinisher.preferredPhotoDimensions(from: dims, minLongEdge: 2048)
        XCTAssertEqual(picked?.width, 4032)
        XCTAssertEqual(picked?.height, 3024)
    }

    func testPreferredPhotoDimensionsFallsBackToLargest() {
        let dims: [CMVideoDimensions] = [
            CMVideoDimensions(width: 1280, height: 960),
            CMVideoDimensions(width: 1920, height: 1440)
        ]
        let picked = PhotoFinisher.preferredPhotoDimensions(from: dims, minLongEdge: 2048)
        XCTAssertEqual(picked?.width, 1920)
    }

    /// Round-trip finish without Core Image — guards the A13 AGX crash path.
    func testFinishCPUPathProducesJPEG() throws {
        let source = try writeSolidTestJPEG(width: 600, height: 800)
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try PhotoFinisher.finish(
            sourceURL: source,
            options: .init(
                filterID: "vivid",
                beautyIntensity: 0.3,
                aspect: .square,
                mirror: true,
                maxLongEdge: 512,
                previewLongEdge: 120
            )
        )
        defer { try? FileManager.default.removeItem(at: result.fileURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(result.width, result.height)
        XCTAssertLessThanOrEqual(max(result.width, result.height), 512)
        XCTAssertNotNil(result.preview.cgImage)
    }

    private func writeSolidTestJPEG(width: Int, height: Int) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "PhotoFinisherTests", code: 1)
        }
        ctx.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = ctx.makeImage() else {
            throw NSError(domain: "PhotoFinisherTests", code: 2)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-finisher-test-\(UUID().uuidString).jpg")
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "PhotoFinisherTests", code: 3)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "PhotoFinisherTests", code: 4)
        }
        try (data as Data).write(to: url)
        return url
    }
}

final class LevelMathTests: XCTestCase {
    func testLevelWhenUpright() {
        let reading = LevelMath.reading(x: 0, y: -1)
        XCTAssertEqual(reading.degrees, 0, accuracy: 0.01)
        XCTAssertTrue(reading.isLevel)
    }

    func testTiltedNotLevel() {
        let reading = LevelMath.reading(x: 0.2, y: -0.98)
        XCTAssertFalse(reading.isLevel)
        XCTAssertGreaterThan(abs(reading.degrees), 1)
    }

    func testPublishThrottle() {
        let a = LevelReading(degrees: 0, isLevel: true)
        let b = LevelReading(degrees: 0.3, isLevel: true)
        let c = LevelReading(degrees: 1.2, isLevel: false)
        XCTAssertFalse(LevelMath.shouldPublish(previous: a, next: b))
        XCTAssertTrue(LevelMath.shouldPublish(previous: a, next: c))
    }
}

