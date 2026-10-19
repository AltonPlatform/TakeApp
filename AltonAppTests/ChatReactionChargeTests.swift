import XCTest
@testable import AltonApp

final class ChatReactionChargeTests: XCTestCase {
    func testProgressBeforeDelayIsZero() {
        XCTAssertEqual(ChatReactionCharge.progress(elapsed: 0.1), 0, accuracy: 0.001)
        XCTAssertEqual(ChatReactionCharge.progress(elapsed: 0.2), 0, accuracy: 0.001)
    }

    func testProgressDuringCharge() {
        let mid = ChatReactionCharge.progress(elapsed: 0.2 + 0.35)
        XCTAssertEqual(mid, 0.5, accuracy: 0.02)
        XCTAssertEqual(ChatReactionCharge.progress(elapsed: 0.2 + 0.7), 1, accuracy: 0.001)
        XCTAssertEqual(ChatReactionCharge.progress(elapsed: 2), 1, accuracy: 0.001)
    }

    func testScaleInterpolates() {
        XCTAssertEqual(ChatReactionCharge.scale(progress: 0), ChatReactionCharge.highlightScale, accuracy: 0.001)
        XCTAssertEqual(ChatReactionCharge.scale(progress: 1), ChatReactionCharge.maxScale, accuracy: 0.001)
        let mid = ChatReactionCharge.scale(progress: 0.5)
        XCTAssertGreaterThan(mid, ChatReactionCharge.highlightScale)
        XCTAssertLessThan(mid, ChatReactionCharge.maxScale)
    }

    func testShakeAmplitudeGrows() {
        let early = abs(ChatReactionCharge.rotationDegrees(progress: 0.2, elapsed: 0.25))
        let late = abs(ChatReactionCharge.rotationDegrees(progress: 0.9, elapsed: 0.25))
        // Same phase angle; amplitude should grow with progress.
        XCTAssertGreaterThan(late, early)
    }

    func testPulseTimesWithinChargeWindow() {
        let times = ChatReactionCharge.pulseTimes()
        XCTAssertFalse(times.isEmpty)
        XCTAssertGreaterThanOrEqual(times.first!, ChatContextMotion.chargeDelay)
        XCTAssertLessThan(times.last!, ChatContextMotion.chargeDelay + ChatContextMotion.chargeDuration)
    }

    func testPulseIntensityRises() {
        let early = ChatReactionCharge.pulseIntensity(at: 0.25)
        let late = ChatReactionCharge.pulseIntensity(at: 0.85)
        XCTAssertGreaterThan(late, early)
        XCTAssertGreaterThanOrEqual(early, 0.3)
        XCTAssertLessThanOrEqual(late, 1.0)
    }
}
