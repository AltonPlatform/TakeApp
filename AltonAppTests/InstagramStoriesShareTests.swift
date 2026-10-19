import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import AltonApp

/// Samples pixels from a 32-bpp RGBA bitmap produced by the renderer's
/// `CGBitmapContext` (premultipliedLast → memory layout R,G,B,A).
private struct PixelSampler {
    let bytes: [UInt8]
    let bytesPerRow: Int
    let width: Int
    let height: Int

    init?(cgImage: CGImage) {
        guard cgImage.bitsPerPixel == 32,
              let data = cgImage.dataProvider?.data as Data? else { return nil }
        self.bytes = [UInt8](data)
        self.bytesPerRow = cgImage.bytesPerRow
        self.width = cgImage.width
        self.height = cgImage.height
    }

    func rgba(x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let idx = y * bytesPerRow + x * 4
        guard idx + 3 < bytes.count else { return (0, 0, 0, 0) }
        let channel = { (offset: Int) -> CGFloat in CGFloat(bytes[idx + offset]) / 255 }
        return (channel(0), channel(1), channel(2), channel(3))
    }

    func luminance(x: Int, y: Int) -> CGFloat {
        let p = rgba(x: x, y: y)
        return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
    }

    /// Count of dark pixels in a horizontal run.
    func darkPixelCount(row: Int, xRange: ClosedRange<Int>, threshold: CGFloat = 0.35) -> Int {
        guard row >= 0, row < height else { return 0 }
        var count = 0
        for x in xRange where x < width {
            if luminance(x: x, y: row) < threshold { count += 1 }
        }
        return count
    }

    /// Count of bright pixels in a box.
    func brightPixelCount(rows: ClosedRange<Int>, xRange: ClosedRange<Int>, threshold: CGFloat = 0.85) -> Int {
        var count = 0
        for y in rows where y < height {
            for x in xRange where x < width {
                if luminance(x: x, y: y) > threshold { count += 1 }
            }
        }
        return count
    }
}

/// Re-renders a CGImage (e.g. one decoded by ImageIO with an unknown byte
/// layout) into the renderer's known 32-bpp RGBA format before sampling.
private func resampleThroughRGBA(_ image: CGImage) -> PixelSampler? {
    guard let ctx = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let redrawn = ctx.makeImage() else { return nil }
    return PixelSampler(cgImage: redrawn)
}

final class InstagramStoriesShareTests: XCTestCase {
    func testMetaAppIDComesFromConfigNotHardcodedCaller() {
        XCTAssertFalse(MetaAppConfig.appID.isEmpty)
        XCTAssertTrue(MetaAppConfig.appID.allSatisfy(\.isNumber))
    }

    func testShareCardRendersImageWithoutImageRenderer() {
        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HABCDEFGHJKMNPQRSTVWXYZ0")!,
            textExcerpt: "Hello from Take",
            username: "alice"
        )
        let image = PostShareCardRenderer.render(payload: payload)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width ?? 0, 1080, accuracy: 1)
        XCTAssertEqual(image?.size.height ?? 0, 1920, accuracy: 1)
        XCTAssertNotNil(image?.cgImage, "Card must be a CPU bitmap (cgImage)")
        let jpeg = PostShareCardRenderer.makeJPEG(payload: payload)
        XCTAssertNotNil(jpeg)
        XCTAssertGreaterThan(jpeg?.count ?? 0, 1_000)
        XCTAssertNotNil(PostShareCardRenderer.solidBackgroundJPEG())
    }

    func testShareChannelMapsInstagram() {
        let type = UIActivity.ActivityType("com.burbn.instagram.shareextension")
        XCTAssertEqual(ShareChannelMapper.channel(for: type), "instagram")
    }

    // MARK: - Pasteboard payload

    func testPasteboardPayloadIncludesContentURLAndMedia() {
        let url = URL(string: "https://alton.social/p/01HTEST")!
        let background = Data([0xFF, 0xD8, 0xFF])
        let payload = InstagramStoriesShare.pasteboardPayload(
            backgroundImageData: background,
            contentURL: url,
            appID: "1993576677971360"
        )
        XCTAssertNotNil(payload)
        XCTAssertEqual(
            payload?["com.instagram.sharedSticker.contentURL"] as? String,
            url.absoluteString
        )
        XCTAssertEqual(
            payload?["com.instagram.sharedSticker.backgroundImage"] as? Data,
            background
        )
        XCTAssertEqual(
            payload?["com.instagram.sharedSticker.appID"] as? String,
            "1993576677971360"
        )
    }

    func testPasteboardPayloadRequiresMedia() {
        let payload = InstagramStoriesShare.pasteboardPayload(
            backgroundImageData: nil,
            stickerImageData: nil,
            backgroundVideoURL: nil,
            contentURL: URL(string: "https://alton.social/p/01HTEST")!
        )
        XCTAssertNil(payload, "A story without media would open blank in Instagram")
    }

    // MARK: - QR (pure-Swift encoder; CIDetector only in tests)

    func testQRCodeDecodesToSourceString() {
        let input = "https://alton.social/p/01HABCDEFGHJKMNPQRSTVWXYZ0"
        assertQRImageDecodes(PostShareCardRenderer.qrCode(for: input, dimension: 200), to: input)
    }

    func testQRCodeDecodesLongerShareURL() {
        let input = "https://alton.social/p/01HABCDEFGHJKMNPQRSTVWXYZ0?utm_source=stories&ref=take"
        assertQRImageDecodes(PostShareCardRenderer.qrCode(for: input, dimension: 220), to: input)
    }

    func testQRCodeUsesCrispIntegerScaling() {
        let qr = PostShareCardRenderer.qrCode(for: "https://alton.social/p/01HTEST", dimension: 128)
        XCTAssertNotNil(qr)
        XCTAssertGreaterThanOrEqual(qr?.size.width ?? 0, 128 * 0.5)
        XCTAssertLessThanOrEqual(qr?.size.width ?? 0, 128 * 2)
    }

    func testQREncoderReturnsNilWhenOverCapacity() {
        let oversized = String(repeating: "a", count: 300)
        XCTAssertNil(QRCodeEncoder.encode(oversized))
        XCTAssertNil(PostShareCardRenderer.qrCode(for: oversized, dimension: 128))
    }

    func testQREncoderPlacesThreeFinderPatterns() {
        let matrix = QRCodeEncoder.encode("https://alton.social/p/01HTEST")
        XCTAssertNotNil(matrix)
        guard let matrix else { return }
        // Top-left, top-right, bottom-left 7×7 finders: center module is dark,
        // and the ring around the 3×3 core is dark on the outer border.
        XCTAssertTrue(matrix.isDark(x: 3, y: 3), "top-left finder center")
        XCTAssertTrue(matrix.isDark(x: matrix.size - 4, y: 3), "top-right finder center")
        XCTAssertTrue(matrix.isDark(x: 3, y: matrix.size - 4), "bottom-left finder center")
        XCTAssertTrue(matrix.isDark(x: 0, y: 0))
        XCTAssertTrue(matrix.isDark(x: 6, y: 0))
        XCTAssertFalse(matrix.isDark(x: 1, y: 1), "finder ring should be light")
    }

    /// Simulator never hits the A13 AGX crash — this source scan is the
    /// regression gate that keeps GPU APIs out of the Stories render path.
    /// Comments/docs may mention the forbidden names; only code tokens count.
    func testSharePathSourcesForbidGPUAPIs() throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let appRoot = testsDir.deletingLastPathComponent().appendingPathComponent("AltonApp")
        let files = [
            "Presentation/Common/PostShareCardView.swift",
            "Presentation/Common/QRCodeEncoder.swift",
            "Presentation/Common/InstagramStoriesShare.swift",
            "Presentation/Common/PostShareSheet.swift",
        ]
        let forbidden = [
            "import CoreImage",
            "CIContext",
            "CIFilter",
            "ImageRenderer",
            "UIGraphicsImageRenderer",
            ".jpegData(",
            ".pngData(",
        ]
        for relative in files {
            let url = appRoot.appendingPathComponent(relative)
            let source = try String(contentsOf: url, encoding: .utf8)
            let codeOnly = Self.stripSwiftComments(source)
            for token in forbidden {
                XCTAssertFalse(
                    codeOnly.contains(token),
                    "\(relative) must not contain \(token) (AGX crash regression)"
                )
            }
        }
    }

    /// Drops `//`, `///`, and `/* */` so doc mentions of forbidden APIs don't fail the gate.
    private static func stripSwiftComments(_ source: String) -> String {
        var result = ""
        var i = source.startIndex
        while i < source.endIndex {
            if source[i] == "\"" {
                result.append("\"")
                i = source.index(after: i)
                while i < source.endIndex {
                    let ch = source[i]
                    result.append(ch)
                    i = source.index(after: i)
                    if ch == "\\" && i < source.endIndex {
                        result.append(source[i])
                        i = source.index(after: i)
                    } else if ch == "\"" {
                        break
                    }
                }
                continue
            }
            if source[i] == "/", source.index(after: i) < source.endIndex {
                let next = source[source.index(after: i)]
                if next == "/" {
                    while i < source.endIndex, source[i] != "\n" {
                        i = source.index(after: i)
                    }
                    continue
                }
                if next == "*" {
                    i = source.index(i, offsetBy: 2)
                    while i < source.endIndex {
                        if source[i] == "*",
                           source.index(after: i) < source.endIndex,
                           source[source.index(after: i)] == "/" {
                            i = source.index(i, offsetBy: 2)
                            break
                        }
                        i = source.index(after: i)
                    }
                    continue
                }
            }
            result.append(source[i])
            i = source.index(after: i)
        }
        return result
    }

    private func assertQRImageDecodes(_ image: UIImage?, to expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(image?.cgImage, file: file, line: line)
        guard let cgImage = image?.cgImage else { return }
        // CIDetector is allowed in tests only — production share path forbids CoreImage.
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: context,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = (detector?.features(in: CIImage(cgImage: cgImage)) as? [CIQRCodeFeature]) ?? []
        XCTAssertEqual(features.first?.messageString, expected, "QR must be scannable", file: file, line: line)
    }
}

/// Orientation regression suite — pins the single-coordinate-system contract
/// that once broke and shipped an upside-down Stories card.
final class PostShareCardOrientationTests: XCTestCase {
    // MARK: - Orientation probe (all primitives at once)

    func testProbeImagePrimitiveUpright() {
        guard let probe = PostShareCardRenderer.renderOrientationProbe()?.cgImage,
              let sampler = PixelSampler(cgImage: probe) else {
            return XCTFail("probe must render")
        }
        // Band drawn at y ∈ [1100, 1500] → final rows [420, 820].
        // Red half is high-y → final rows [420, 620]; blue half → [620, 820].
        let red = sampler.rgba(x: 540, y: 500)
        let blue = sampler.rgba(x: 540, y: 700)
        XCTAssertGreaterThan(red.r, 0.7, "red half must be on top — image draw flipped")
        XCTAssertLessThan(red.b, 0.4)
        XCTAssertGreaterThan(blue.b, 0.6, "blue half must be below — image draw flipped")
        XCTAssertLessThan(blue.r, 0.4)
    }

    func testProbeTextPrimitiveUpright() {
        guard let probe = PostShareCardRenderer.renderOrientationProbe()?.cgImage,
              let sampler = PixelSampler(cgImage: probe) else {
            return XCTFail("probe must render")
        }
        // "T" glyph rect → final rows [24, 360]; its crossbar is the widest
        // dark row and must sit in the top part of the glyph's span.
        let xRange = 120...620
        var rowsWithDarkPixels: [Int] = []
        var counts: [Int: Int] = [:]
        for y in 0...400 {
            let count = sampler.darkPixelCount(row: y, xRange: xRange)
            if count > 8 {
                rowsWithDarkPixels.append(y)
                counts[y] = count
            }
        }
        guard let first = rowsWithDarkPixels.first,
              let last = rowsWithDarkPixels.last,
              let widestRow = counts.max(by: { $0.value < $1.value })?.key else {
            return XCTFail("T glyph must render dark pixels")
        }
        XCTAssertGreaterThan(last - first, 60, "glyph should be tall")
        let span = CGFloat(last - first)
        XCTAssertLessThanOrEqual(
            CGFloat(widestRow - first),
            span * 0.45,
            "the T crossbar must be near the TOP of the glyph — Core Text flipped"
        )
    }

    func testProbeBackgroundUntouchedAboveBand() {
        guard let probe = PostShareCardRenderer.renderOrientationProbe()?.cgImage,
              let sampler = PixelSampler(cgImage: probe) else {
            return XCTFail("probe must render")
        }
        let corner = sampler.rgba(x: 10, y: 10)
        XCTAssertGreaterThan(corner.r, 0.9, "white background must stay on top of the canvas")
    }

    // MARK: - Full card

    func testCardGradientTopNavyBottomPurple() {
        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HTEST")!,
            textExcerpt: "Gradient direction probe",
            username: "alice"
        )
        guard let card = PostShareCardRenderer.render(payload: payload)?.cgImage,
              let sampler = PixelSampler(cgImage: card) else {
            return XCTFail("card must render")
        }
        let top = sampler.rgba(x: 10, y: 10)
        let bottom = sampler.rgba(x: 10, y: 1910)
        XCTAssertLessThan(top.b, 0.25, "top-left corner should be brand navy")
        XCTAssertGreaterThan(bottom.b, top.b + 0.08, "bottom should trend purple — gradient inverted")
        XCTAssertGreaterThan(bottom.r, top.r + 0.06)
    }

    func testPosterFullBleedUprightWithScrim() {
        // 200×300 poster: red top half (high y), blue bottom half.
        guard let posterCtx = CGContext(
            data: nil,
            width: 200,
            height: 300,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return XCTFail("poster context") }
        posterCtx.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        posterCtx.fill(CGRect(x: 0, y: 150, width: 200, height: 150))
        posterCtx.setFillColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        posterCtx.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
        guard let poster = posterCtx.makeImage() else { return XCTFail("poster image") }

        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HTEST")!,
            textExcerpt: "Poster orientation probe",
            username: "alice"
        )
        guard let card = PostShareCardRenderer.render(payload: payload, poster: poster)?.cgImage,
              let sampler = PixelSampler(cgImage: card) else {
            return XCTFail("card must render")
        }

        // Aspect-fill 200×300 → scale 6.4 → 1280×1920, full height.
        // Red half lands in final rows [0, 960], blue in [960, 1920].
        let upper = sampler.rgba(x: 540, y: 300)
        XCTAssertGreaterThan(upper.r, 0.7, "poster's red (top) half must be at the top of the card")

        // Lower area: blue + scrim (~0.54 alpha at final row 1600).
        let lower = sampler.rgba(x: 540, y: 1600)
        XCTAssertGreaterThan(lower.b, 0.25, "poster's blue half must be at the bottom (darkened by scrim)")
        XCTAssertGreaterThan(lower.b - lower.r, 0.2)

        // Scrim direction: bottom edge must be much darker than raw blue.
        let bottomEdge = sampler.rgba(x: 540, y: 1900)
        let lum = 0.299 * bottomEdge.r + 0.587 * bottomEdge.g + 0.114 * bottomEdge.b
        XCTAssertLessThan(lum, 0.3, "bottom scrim missing or inverted")
    }

    func testNoMediaTemplateHasQRPlateAndCenteredBrandOnly() {
        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HTEST")!,
            textExcerpt: "Footer probe",
            username: "alice"
        )
        guard let card = PostShareCardRenderer.render(payload: payload)?.cgImage,
              let sampler = PixelSampler(cgImage: card) else {
            return XCTFail("card must render")
        }
        // QR plate occupies final rows [1432, 1600].
        let plate = sampler.rgba(x: 150, y: 1440)
        XCTAssertGreaterThan(plate.r, 0.85, "white QR plate missing or misplaced")

        // Centered brand wordmark (no-media only).
        let centerPixels = sampler.brightPixelCount(rows: 620...830, xRange: 340...740)
        XCTAssertGreaterThan(centerPixels, 100, "centered brand wordmark missing")

        // Footer wordmark zone must stay empty — brand is not duplicated.
        let footerWordmarkPixels = sampler.brightPixelCount(rows: 1250...1390, xRange: 96...600)
        XCTAssertLessThan(
            footerWordmarkPixels,
            40,
            "no-media footer must not repeat the Take wordmark"
        )
    }

    func testMediaTemplateHasFooterWordmarkOverPoster() {
        guard let posterCtx = CGContext(
            data: nil,
            width: 200,
            height: 300,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return XCTFail("poster context") }
        posterCtx.setFillColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1)
        posterCtx.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        guard let poster = posterCtx.makeImage() else { return XCTFail("poster") }

        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HTEST")!,
            textExcerpt: "Hello from Take",
            username: "alice"
        )
        guard let card = PostShareCardRenderer.render(payload: payload, poster: poster)?.cgImage,
              let sampler = PixelSampler(cgImage: card) else {
            return XCTFail("card must render")
        }
        let plate = sampler.rgba(x: 150, y: 1440)
        XCTAssertGreaterThan(plate.r, 0.85, "QR plate missing on media card")
        let wordmarkPixels = sampler.brightPixelCount(rows: 1250...1390, xRange: 96...600)
        XCTAssertGreaterThan(wordmarkPixels, 100, "media footer wordmark missing")
    }

    func testDotExcerptIsDroppedFromShareMessageAndCard() {
        XCTAssertNil(PostSharePayload.meaningfulExcerpt("."))
        XCTAssertNil(PostSharePayload.meaningfulExcerpt("…"))
        XCTAssertNil(PostSharePayload.meaningfulExcerpt(" · "))
        XCTAssertEqual(PostSharePayload.meaningfulExcerpt("Hello"), "Hello")

        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HTEST")!,
            textExcerpt: ".",
            username: "alice"
        )
        XCTAssertEqual(payload.shareMessage, "@alice in Take")

        guard let posterCtx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return XCTFail("poster context") }
        posterCtx.setFillColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1)
        posterCtx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        guard let poster = posterCtx.makeImage() else { return XCTFail("poster") }

        // With a real excerpt there are bright glyphs above the handle;
        // with "." that band stays dark (scrim only).
        let withDot = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HTEST")!,
            textExcerpt: ".",
            username: "alice"
        )
        let withText = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HTEST")!,
            textExcerpt: "Hello from Take share card",
            username: "alice"
        )
        guard let dotCard = PostShareCardRenderer.render(payload: withDot, poster: poster)?.cgImage,
              let textCard = PostShareCardRenderer.render(payload: withText, poster: poster)?.cgImage,
              let dotSampler = PixelSampler(cgImage: dotCard),
              let textSampler = PixelSampler(cgImage: textCard) else {
            return XCTFail("cards must render")
        }
        // Excerpt sits above handle/wordmark (~ final rows 1050…1200).
        let excerptRows = 1050...1200
        let xRange = 96...900
        let dotBright = dotSampler.brightPixelCount(rows: excerptRows, xRange: xRange)
        let textBright = textSampler.brightPixelCount(rows: excerptRows, xRange: xRange)
        XCTAssertGreaterThan(textBright, 80, "control: real excerpt must paint glyphs")
        XCTAssertLessThan(dotBright, textBright / 2, "dot excerpt must not paint footer text")
    }

    func testDecodePosterDataBakesEXIFAndDownsamples() throws {
        let jpeg = try makeEXIF6JPEG()
        guard let oriented = PostShareCardRenderer.decodePosterData(jpeg, maxPixelSize: 1920) else {
            return XCTFail("decodePosterData must succeed")
        }
        XCTAssertEqual(oriented.width, 100)
        XCTAssertEqual(oriented.height, 200)
        guard let sampler = resampleThroughRGBA(oriented) else { return XCTFail("resample") }
        XCTAssertLessThan(sampler.rgba(x: 50, y: 20).r, 0.3)
        XCTAssertGreaterThan(sampler.rgba(x: 50, y: 180).r, 0.6)
    }

    func testLoadRemotePosterRejectsNonHTTPS() async {
        let http = URL(string: "http://example.com/a.jpg")!
        let file = URL(fileURLWithPath: "/tmp/a.jpg")
        let none = await PostShareCardRenderer.loadRemotePoster(from: http)
        let noneFile = await PostShareCardRenderer.loadRemotePoster(from: file)
        XCTAssertNil(none)
        XCTAssertNil(noneFile)
    }

    // MARK: - EXIF-orientation poster loading

    func testLoadOrientedPosterBakesEXIFOrientation() throws {
        let jpeg = try makeEXIF6JPEG()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("exif-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try jpeg.write(to: fileURL)

        guard let oriented = PostShareCardRenderer.loadOrientedPoster(from: fileURL) else {
            return XCTFail("poster must load")
        }
        XCTAssertEqual(oriented.width, 100, "orientation must be baked in (200×100 → 100×200)")
        XCTAssertEqual(oriented.height, 200)
        guard let sampler = resampleThroughRGBA(oriented) else {
            return XCTFail("resample")
        }
        XCTAssertEqual(sampler.width, 100)
        XCTAssertEqual(sampler.height, 200)
        let top = sampler.rgba(x: 50, y: 20)
        let bottom = sampler.rgba(x: 50, y: 180)
        XCTAssertLessThan(top.r, 0.3, "dark half must be rotated to the top")
        XCTAssertGreaterThan(bottom.r, 0.6, "red half must be rotated to the bottom")
    }

    /// Raw 200×100: dark left / red right, tagged EXIF 6 (90° CW → 100×200).
    private func makeEXIF6JPEG() throws -> Data {
        guard let ctx = CGContext(
            data: nil,
            width: 200,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "test", code: 1) }
        ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        ctx.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        guard let raw = ctx.makeImage() else { throw NSError(domain: "test", code: 2) }
        let jpegData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            jpegData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw NSError(domain: "test", code: 3) }
        CGImageDestinationAddImage(dest, raw, [kCGImagePropertyOrientation: 6] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "test", code: 4) }
        return jpegData as Data
    }
}