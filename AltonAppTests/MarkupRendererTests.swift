import CoreGraphics
import XCTest
@testable import AltonApp

final class MarkupRendererTests: XCTestCase {
    func testStrokeLandsAtNormalizedPointNotCorner() throws {
        let size = 1000
        guard let ctx = CPUImageIO.makeBitmapContext(width: size, height: size) else {
            return XCTFail("context")
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let stroke = MarkupStroke(
            brush: .pen,
            widthNorm: 0.04,
            colorHex: "#FF0000",
            points: [MarkupPoint(x: 0.75, y: 0.25)]
        )
        var doc = MarkupDocument()
        doc.strokes = [stroke]
        MarkupRenderer.draw(document: doc, in: ctx, size: CGSize(width: size, height: size))
        guard let image = ctx.makeImage() else {
            return XCTFail("image")
        }

        // Normalized (0.75, 0.25) → pixel (~750, ~250) in top-left image space.
        let sample = try pixel(image, x: 750, y: 250)
        XCTAssertGreaterThan(sample.r, 200, "expected red ink near (750,250), got \(sample)")
        XCTAssertLessThan(sample.g, 80)
        XCTAssertLessThan(sample.b, 80)

        // Corner should stay black (not misplaced ink).
        let corner = try pixel(image, x: 20, y: 20)
        XCTAssertLessThan(corner.r, 40, "ink leaked to corner: \(corner)")
    }

    func testWhiteStrokeStaysWhite() throws {
        let size = 400
        guard let ctx = CPUImageIO.makeBitmapContext(width: size, height: size) else {
            return XCTFail("context")
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let stroke = MarkupStroke(
            brush: .pen,
            widthNorm: 0.08,
            colorHex: "#FFFFFF",
            points: [
                MarkupPoint(x: 0.2, y: 0.5),
                MarkupPoint(x: 0.8, y: 0.5)
            ]
        )
        var doc = MarkupDocument()
        doc.strokes = [stroke]
        MarkupRenderer.draw(document: doc, in: ctx, size: CGSize(width: size, height: size))
        guard let image = ctx.makeImage() else {
            return XCTFail("image")
        }
        let mid = try pixel(image, x: 200, y: 200)
        XCTAssertGreaterThan(mid.r, 200)
        XCTAssertGreaterThan(mid.g, 200)
        XCTAssertGreaterThan(mid.b, 200)
    }

    func testTextOrientationUpright() throws {
        let size = 500
        guard let ctx = CPUImageIO.makeBitmapContext(width: size, height: size) else {
            return XCTFail("context")
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        var doc = MarkupDocument()
        doc.texts = [
            MarkupTextItem(
                text: "T",
                center: MarkupPoint(x: 0.5, y: 0.5),
                colorHex: "#00FF00",
                fontSizeNorm: 0.35
            )
        ]
        MarkupRenderer.draw(document: doc, in: ctx, size: CGSize(width: size, height: size))
        guard let image = ctx.makeImage() else {
            return XCTFail("image")
        }
        // Center should have green-ish pixels from the glyph.
        let center = try pixel(image, x: 250, y: 250)
        XCTAssertGreaterThan(center.g, 40, "expected text pigment near center, got \(center)")
    }

    func testExportMeasure200Strokes() throws {
        guard let base = CPUImageIO.makeBitmapContext(width: 2048, height: 2048)?.makeImage() else {
            return XCTFail("base")
        }
        var doc = MarkupDocument()
        let brushes = MarkupBrush.allCases
        for i in 0..<200 {
            let brush = brushes[i % brushes.count]
            doc.strokes.append(
                MarkupStroke(
                    brush: brush,
                    widthNorm: 0.01,
                    colorHex: MarkupPalette.swatches[i % MarkupPalette.swatches.count],
                    points: [
                        MarkupPoint(x: CGFloat(i % 50) / 50, y: CGFloat(i / 50) / 50),
                        MarkupPoint(x: CGFloat(i % 50) / 50 + 0.02, y: CGFloat(i / 50) / 50 + 0.02)
                    ]
                )
            )
        }
        for i in 0..<5 {
            doc.texts.append(
                MarkupTextItem(
                    text: "Tx\(i)",
                    center: MarkupPoint(x: 0.2 + CGFloat(i) * 0.15, y: 0.8),
                    colorHex: "#FFFFFF"
                )
            )
        }

        measure {
            _ = MarkupRenderer.renderExport(base: base, document: doc)
        }
    }

    // MARK: - Pixel helper

    private struct RGBA {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> RGBA {
        // Sample in top-left image coordinates by drawing into a 1×1 bitmap with a crop.
        guard let ctx = CPUImageIO.makeBitmapContext(width: 1, height: 1) else {
            throw NSError(domain: "MarkupRendererTests", code: 1)
        }
        // CGImage coordinates: origin top-left for cropping.
        let rect = CGRect(x: x, y: y, width: 1, height: 1)
        guard let cropped = image.cropping(to: rect) else {
            throw NSError(domain: "MarkupRendererTests", code: 2)
        }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data else {
            throw NSError(domain: "MarkupRendererTests", code: 3)
        }
        let ptr = data.bindMemory(to: UInt8.self, capacity: 4)
        return RGBA(r: ptr[0], g: ptr[1], b: ptr[2], a: ptr[3])
    }
}
