import XCTest
@testable import AltonApp

final class ChatSwipeToReplyTests: XCTestCase {
    func testOffsetClampsToMaxLeft() {
        XCTAssertEqual(ChatSwipeToReply.offset(translationX: -200), ChatSwipeToReply.maxOffset, accuracy: 0.01)
        XCTAssertEqual(ChatSwipeToReply.offset(translationX: -20), -20, accuracy: 0.01)
    }

    func testOffsetResistancePastThreshold() {
        // At threshold: no resistance yet.
        XCTAssertEqual(ChatSwipeToReply.offset(translationX: -45), -45, accuracy: 0.01)
        // Past threshold: threshold + (tx - threshold) * 0.35
        let expected = -45 + (-80 - (-45)) * ChatSwipeToReply.resistance
        XCTAssertEqual(ChatSwipeToReply.offset(translationX: -80), expected, accuracy: 0.01)
        XCTAssertGreaterThan(ChatSwipeToReply.offset(translationX: -80), ChatSwipeToReply.maxOffset)
    }

    func testOffsetIgnoresRightward() {
        XCTAssertEqual(ChatSwipeToReply.offset(translationX: 40), 0)
        XCTAssertEqual(ChatSwipeToReply.offset(translationX: 0), 0)
    }

    func testThreshold() {
        XCTAssertFalse(ChatSwipeToReply.shouldTrigger(offset: -20))
        XCTAssertTrue(ChatSwipeToReply.shouldTrigger(offset: -45))
        XCTAssertTrue(ChatSwipeToReply.shouldTrigger(offset: -80))
    }

    func testIconOpacityAndProgress() {
        XCTAssertEqual(ChatSwipeToReply.iconOpacity(offset: 0), 0, accuracy: 0.001)
        XCTAssertEqual(ChatSwipeToReply.iconOpacity(offset: -45), 1, accuracy: 0.001)
        XCTAssertEqual(ChatSwipeToReply.iconOpacity(offset: -22.5), 0.5, accuracy: 0.01)
        XCTAssertEqual(ChatSwipeToReply.progress(offset: -22.5), 0.5, accuracy: 0.01)
    }

    func testArrowRotation() {
        XCTAssertEqual(ChatSwipeToReply.arrowRotation(offset: 0).degrees, -30, accuracy: 0.1)
        XCTAssertEqual(ChatSwipeToReply.arrowRotation(offset: -45).degrees, 0, accuracy: 0.1)
    }
}
