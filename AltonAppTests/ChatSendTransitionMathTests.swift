import XCTest
@testable import AltonApp

final class ChatSendMorphMathTests: XCTestCase {
    func testStartOffsetAlignsLeftAndBottom() {
        let source = CGRect(x: 0, y: 100, width: 200, height: 40)
        let bubble = CGRect(x: 150, y: 40, width: 80, height: 30)
        let offset = ChatSendMorphMath.startOffset(source: source, bubble: bubble)
        XCTAssertEqual(bubble.minX + offset.width, source.minX, accuracy: 0.01)
        XCTAssertEqual(bubble.maxY + offset.height, source.maxY, accuracy: 0.01)
    }

    func testStartOffsetIsZeroWhenFramesMatch() {
        let frame = CGRect(x: 12, y: 40, width: 180, height: 36)
        let offset = ChatSendMorphMath.startOffset(source: frame, bubble: frame)
        XCTAssertEqual(offset.width, 0, accuracy: 0.01)
        XCTAssertEqual(offset.height, 0, accuracy: 0.01)
    }
}

final class ChatSendMotionTests: XCTestCase {
    func testEntranceSkipsAfterMorphIsPrepared() {
        XCTAssertFalse(ChatSendMotion.playsEntrance(isFresh: true, hasMorphSource: false, morphPrepared: true))
        XCTAssertFalse(ChatSendMotion.playsEntrance(isFresh: true, hasMorphSource: true, morphPrepared: false))
    }

    func testEntrancePlaysForFreshRowsWithoutMorph() {
        XCTAssertTrue(ChatSendMotion.playsEntrance(isFresh: true, hasMorphSource: false, morphPrepared: false))
        XCTAssertFalse(ChatSendMotion.playsEntrance(isFresh: false, hasMorphSource: false, morphPrepared: false))
    }
}

final class MessageSendMathTests: XCTestCase {
    func testTailStaysHiddenUntilTheLastStretch() {
        XCTAssertEqual(MessageSendMath.tailProgress(0), 0, accuracy: 0.001)
        XCTAssertEqual(MessageSendMath.tailProgress(0.7), 0, accuracy: 0.001)
        XCTAssertEqual(MessageSendMath.tailProgress(0.85), 0.5, accuracy: 0.001)
        XCTAssertEqual(MessageSendMath.tailProgress(1), 1, accuracy: 0.001)
    }

    func testFlightIsSkippedWhenScrolledOrReduced() {
        XCTAssertTrue(MessageSendTransition.shouldFly(reduceMotion: false, nearBottom: true, hasSource: true))
        XCTAssertFalse(MessageSendTransition.shouldFly(reduceMotion: true, nearBottom: true, hasSource: true))
        XCTAssertFalse(MessageSendTransition.shouldFly(reduceMotion: false, nearBottom: false, hasSource: true))
        XCTAssertFalse(MessageSendTransition.shouldFly(reduceMotion: false, nearBottom: true, hasSource: false))
    }

    func testRectLandsOnTheTarget() {
        let source = CGRect(x: 10, y: 400, width: 200, height: 40)
        let target = CGRect(x: 80, y: 120, width: 140, height: 64)
        let end = MessageSendMath.rect(from: source, to: target, progress: 1)
        XCTAssertEqual(end, target)
        let mid = MessageSendMath.rect(from: source, to: target, progress: 0.5)
        XCTAssertEqual(mid.minX, 45, accuracy: 0.01)
        XCTAssertEqual(mid.minY, 260, accuracy: 0.01)
    }
}

final class ChatRowRevealTests: XCTestCase {
    func testHeightScalesWithProgress() {
        XCTAssertEqual(ChatRowReveal.fittedHeight(natural: 100, progress: 0), 0, accuracy: 0.01)
        XCTAssertEqual(ChatRowReveal.fittedHeight(natural: 100, progress: 0.5), 50, accuracy: 0.01)
        XCTAssertEqual(ChatRowReveal.fittedHeight(natural: 100, progress: 1), 100, accuracy: 0.01)
        XCTAssertEqual(ChatRowReveal.fittedHeight(natural: 80, progress: 1.4), 80, accuracy: 0.01)
    }

    func testChildIsPinnedToTheBottom() {
        XCTAssertEqual(
            ChatRowReveal.childMinY(containerHeight: 50, childHeight: 100),
            -50,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ChatRowReveal.childMinY(containerHeight: 100, childHeight: 100),
            0,
            accuracy: 0.01
        )
    }
}
