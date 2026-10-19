import XCTest
@testable import AltonApp

final class CameraZoomStopBuilderTests: XCTestCase {
    func testDualWideStopsUseDisplayValues() {
        // iPhone 11 Dual Wide: native 1.0 = ultra-wide, switch-over 2.0 = wide, multiplier 0.5.
        let stops = CameraZoomStopBuilder.stops(
            minZoom: 1.0,
            maxZoom: 10.0,
            switchOvers: [2.0],
            displayMultiplier: 0.5,
            isBackCamera: true
        )
        let labels = stops.map(\.label)
        XCTAssertTrue(labels.contains("0.5×"), labels.joined(separator: ","))
        XCTAssertTrue(labels.contains("1×"), labels.joined(separator: ","))
        XCTAssertTrue(labels.contains("2×"), labels.joined(separator: ","))
        // Primary 1× is native factor 2.0.
        XCTAssertEqual(stops.first(where: { $0.label == "1×" })?.factor ?? 0, 2.0, accuracy: 0.05)
        // Ultra-wide 0.5× is native factor 1.0.
        XCTAssertEqual(stops.first(where: { $0.label == "0.5×" })?.factor ?? 0, 1.0, accuracy: 0.05)
    }

    func testSingleWideHasOneAndTwo() {
        let stops = CameraZoomStopBuilder.stops(
            minZoom: 1.0,
            maxZoom: 5.0,
            switchOvers: [],
            displayMultiplier: 1.0,
            isBackCamera: true
        )
        let labels = stops.map(\.label)
        XCTAssertEqual(labels.first, "1×")
        XCTAssertTrue(labels.contains("2×"))
        XCTAssertFalse(labels.contains("0.5×"))
    }

    func testFrontCameraOnlyOneX() {
        let stops = CameraZoomStopBuilder.stops(
            minZoom: 1.0,
            maxZoom: 5.0,
            switchOvers: [2.0],
            displayMultiplier: 1.0,
            isBackCamera: false
        )
        XCTAssertEqual(stops.map(\.label), ["1×"])
    }

    func testDisplayLabelFormatting() {
        XCTAssertEqual(
            CameraZoomStopBuilder.displayLabel(nativeFactor: 1.0, displayMultiplier: 0.5),
            "0.5×"
        )
        XCTAssertEqual(
            CameraZoomStopBuilder.displayLabel(nativeFactor: 2.0, displayMultiplier: 0.5),
            "1×"
        )
        XCTAssertEqual(
            CameraZoomStopBuilder.displayLabel(nativeFactor: 2.8, displayMultiplier: 0.5),
            "1.4×"
        )
    }
}
