import XCTest
@testable import AltonApp

final class ChatContextMotionTests: XCTestCase {
    func testPressMinScaleWideBubble() {
        let scale = ChatContextMotion.pressMinScale(width: 300)
        XCTAssertEqual(scale, (300 - 15) / 300, accuracy: 0.0001)
        XCTAssertEqual(scale, 0.95, accuracy: 0.001)
    }

    func testPressMinScaleClampsAtPointSeven() {
        let scale = ChatContextMotion.pressMinScale(width: 40)
        XCTAssertEqual(scale, 0.7, accuracy: 0.0001)
    }

    func testItemDelayAtAnchor() {
        let delay = ChatContextMotion.itemDelay(itemCenterX: 100, anchorX: 100, width: 280)
        XCTAssertEqual(delay, 0.01, accuracy: 0.0001)
    }

    func testItemDelayAtFarEdge() {
        let delay = ChatContextMotion.itemDelay(itemCenterX: 0, anchorX: 280, width: 280)
        XCTAssertEqual(delay, 0.31, accuracy: 0.0001)
    }

    func testSpringSpeedCompressesBounce() {
        let speed = ChatContextMotion.springSpeed(
            mass: 5,
            stiffness: 900,
            damping: 104,
            duration: ChatContextMotion.presentDuration
        )
        XCTAssertGreaterThan(speed, 1)
    }

    func testGridSpringSpeedCompresses() {
        let speed = ChatContextMotion.springSpeed(
            mass: 3,
            stiffness: 1000,
            damping: 500,
            duration: ChatContextMotion.gridDuration
        )
        XCTAssertGreaterThan(speed, 1)
    }
}
