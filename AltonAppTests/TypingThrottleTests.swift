import XCTest
@testable import AltonApp

final class TypingThrottleTests: XCTestCase {
    func testAllowsFirstSend() {
        var throttle = TypingThrottle(interval: 3)
        XCTAssertTrue(throttle.shouldSend(now: Date(timeIntervalSince1970: 100)))
    }

    func testBlocksWithinInterval() {
        var throttle = TypingThrottle(interval: 3)
        let t0 = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(throttle.shouldSend(now: t0))
        XCTAssertFalse(throttle.shouldSend(now: t0.addingTimeInterval(1)))
        XCTAssertFalse(throttle.shouldSend(now: t0.addingTimeInterval(2.9)))
    }

    func testAllowsAfterInterval() {
        var throttle = TypingThrottle(interval: 3)
        let t0 = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(throttle.shouldSend(now: t0))
        XCTAssertTrue(throttle.shouldSend(now: t0.addingTimeInterval(3)))
    }
}
