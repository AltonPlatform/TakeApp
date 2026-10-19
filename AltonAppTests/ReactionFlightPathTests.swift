import XCTest
@testable import AltonApp

final class ReactionFlightPathTests: XCTestCase {
    func testEndpointsMatch() {
        let from = CGPoint(x: 100, y: 200)
        let to = CGPoint(x: 300, y: 400)
        let start = ReactionFlightPath.point(from: from, to: to, t: 0)
        let end = ReactionFlightPath.point(from: from, to: to, t: 1)
        XCTAssertEqual(start.x, from.x, accuracy: 0.5)
        XCTAssertEqual(start.y, from.y, accuracy: 0.5)
        XCTAssertEqual(end.x, to.x, accuracy: 0.5)
        XCTAssertEqual(end.y, to.y, accuracy: 0.5)
    }

    func testPeakIsAboveMidline() {
        let from = CGPoint(x: 100, y: 300)
        let to = CGPoint(x: 300, y: 300)
        let midY = ReactionFlightPath.peakY(from: from, to: to)
        // Midpoint of the parabola sits at source.y - elevation.
        XCTAssertEqual(midY, from.y - ReactionFlightPath.elevation, accuracy: 1)
    }

    func testNearPointsLerp() {
        let from = CGPoint(x: 10, y: 10)
        let to = CGPoint(x: 12, y: 12)
        let mid = ReactionFlightPath.point(from: from, to: to, t: 0.5)
        XCTAssertEqual(mid.x, 11, accuracy: 0.5)
        XCTAssertEqual(mid.y, 11, accuracy: 0.5)
    }
}
