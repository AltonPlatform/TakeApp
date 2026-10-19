import XCTest
@testable import AltonApp

final class MarkupTextLayoutTests: XCTestCase {
    func testPaddingAndMaxWidthScaleWithCanvas() {
        let item = MarkupTextItem(
            text: "Hello world",
            background: .solid,
            fontSizeNorm: 0.07
        )
        let small = MarkupTextLayout.measure(item: item, canvasSize: CGSize(width: 390, height: 844))
        let large = MarkupTextLayout.measure(item: item, canvasSize: CGSize(width: 2048, height: 2048))

        XCTAssertEqual(small.maxWidth / 390, 0.85, accuracy: 0.001)
        XCTAssertEqual(large.maxWidth / 2048, 0.85, accuracy: 0.001)

        let smallPadRatio = small.padX / small.fontSize
        let largePadRatio = large.padX / large.fontSize
        XCTAssertEqual(smallPadRatio, 0.3, accuracy: 0.001)
        XCTAssertEqual(largePadRatio, 0.3, accuracy: 0.001)
        XCTAssertEqual(small.corner / small.fontSize, 0.25, accuracy: 0.001)
        XCTAssertEqual(large.corner / large.fontSize, 0.25, accuracy: 0.001)
        XCTAssertLessThan(small.boxSize.width, small.maxWidth)
        XCTAssertEqual(
            MarkupTextLayout.backgroundCorner(metrics: small),
            small.boxSize.height / 2,
            accuracy: 0.001
        )
    }

    func testHitTestRotatedText() {
        var item = MarkupTextItem(text: "Hit me", center: MarkupPoint(x: 0.5, y: 0.5))
        item.rotation = .pi / 2
        let size = CGSize(width: 400, height: 400)
        let center = CGPoint(x: 200, y: 200)
        XCTAssertTrue(MarkupTextLayout.contains(point: center, item: item, canvasSize: size))
        XCTAssertFalse(
            MarkupTextLayout.contains(point: CGPoint(x: 10, y: 10), item: item, canvasSize: size)
        )
    }
}

final class MarkupTextSnapTests: XCTestCase {
    func testCenterSnap() {
        let size = CGSize(width: 400, height: 800)
        let near = MarkupPoint(x: 0.5 + 3 / 400, y: 0.5)
        let result = MarkupTextSnap.apply(
            center: near,
            rotation: 0.01,
            canvasSize: size,
            previouslySnapped: false
        )
        XCTAssertTrue(result.showVerticalGuide)
        XCTAssertEqual(result.center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.rotation, 0, accuracy: 0.0001)
        XCTAssertTrue(result.didSnap)
    }

    func testNoSnapOutsideThreshold() {
        let size = CGSize(width: 400, height: 800)
        let far = MarkupPoint(x: 0.3, y: 0.3)
        let result = MarkupTextSnap.apply(
            center: far,
            rotation: 0.2,
            canvasSize: size,
            previouslySnapped: false
        )
        XCTAssertFalse(result.showVerticalGuide)
        XCTAssertFalse(result.showHorizontalGuide)
        XCTAssertEqual(result.center.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(result.rotation, 0.2, accuracy: 0.0001)
    }
}

final class MarkupTextPreferencesTests: XCTestCase {
    func testSaveAndLoad() {
        let suite = "dm.markup.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let item = MarkupTextItem(
            text: "x",
            colorHex: "#FF0000",
            font: .strong,
            background: .translucent,
            alignment: .left,
            fontSizeNorm: 0.11
        )
        MarkupTextPreferences.save(from: item, defaults: defaults)
        var loaded = MarkupTextItem(text: "")
        MarkupTextPreferences.apply(to: &loaded, defaults: defaults)
        XCTAssertEqual(loaded.colorHex, "#FF0000")
        XCTAssertEqual(loaded.font, .strong)
        XCTAssertEqual(loaded.background, .translucent)
        XCTAssertEqual(loaded.alignment, .left)
        XCTAssertEqual(loaded.fontSizeNorm, 0.11, accuracy: 0.0001)
    }
}
