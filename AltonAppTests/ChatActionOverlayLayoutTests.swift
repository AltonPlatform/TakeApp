import XCTest
@testable import AltonApp

final class ChatActionOverlayLayoutTests: XCTestCase {
    private let safe = CGRect(x: 0, y: 59, width: 390, height: 700)

    func testBubbleNearTopShiftsDownForReactionBar() {
        let bubble = CGRect(x: 40, y: 70, width: 180, height: 60)
        let place = ChatActionOverlayLayout.resolve(
            bubbleFrame: bubble,
            safeArea: safe,
            barHeight: 52,
            menuHeight: 200,
            barWidth: 300,
            menuWidth: 240,
            isMine: false
        )
        XCTAssertGreaterThan(place.bubbleOffsetY, 0)
        XCTAssertGreaterThanOrEqual(place.barFrame.minY, safe.minY)
        XCTAssertEqual(
            place.barFrame.maxY,
            place.bubbleFrame.minY - ChatActionOverlayLayout.barGap,
            accuracy: 0.5
        )
    }

    func testBubbleNearBottomShiftsUpForMenu() {
        let bubble = CGRect(x: 160, y: 680, width: 180, height: 60)
        let place = ChatActionOverlayLayout.resolve(
            bubbleFrame: bubble,
            safeArea: safe,
            barHeight: 52,
            menuHeight: 220,
            barWidth: 300,
            menuWidth: 240,
            isMine: true
        )
        XCTAssertLessThan(place.bubbleOffsetY, 0)
        XCTAssertLessThanOrEqual(place.menuFrame.maxY, safe.maxY)
        XCTAssertEqual(place.menuFrame.minY, place.bubbleFrame.maxY + ChatActionOverlayLayout.spacing, accuracy: 0.5)
    }

    func testTallBubbleIsClipped() {
        let bubble = CGRect(x: 40, y: 120, width: 200, height: 900)
        let place = ChatActionOverlayLayout.resolve(
            bubbleFrame: bubble,
            safeArea: safe,
            barHeight: 52,
            menuHeight: 180,
            barWidth: 280,
            menuWidth: 240,
            isMine: false
        )
        XCTAssertTrue(place.isClipped)
        XCTAssertLessThan(place.bubbleFrame.height, bubble.height)
        XCTAssertGreaterThanOrEqual(place.barFrame.minY, safe.minY - 1)
        XCTAssertLessThanOrEqual(place.menuFrame.maxY, safe.maxY + 1)
    }

    func testMineAlignsBarAndMenuToTrailing() {
        let bubble = CGRect(x: 180, y: 300, width: 160, height: 50)
        let place = ChatActionOverlayLayout.resolve(
            bubbleFrame: bubble,
            safeArea: safe,
            barHeight: 52,
            menuHeight: 160,
            barWidth: 280,
            menuWidth: 240,
            isMine: true
        )
        XCTAssertEqual(place.barFrame.maxX, bubble.maxX, accuracy: 1)
        XCTAssertEqual(place.menuFrame.maxX, bubble.maxX, accuracy: 1)
    }

    func testWideBarStaysInsideWhenAlignedToEitherEdge() {
        let wide: CGFloat = 420
        for isMine in [false, true] {
            let bubble = CGRect(
                x: isMine ? 280 : -20,
                y: 300,
                width: 160,
                height: 50
            )
            let place = ChatActionOverlayLayout.resolve(
                bubbleFrame: bubble,
                safeArea: safe,
                barHeight: 52,
                menuHeight: 160,
                barWidth: wide,
                menuWidth: 300,
                isMine: isMine
            )
            let usable = safe.insetBy(dx: ChatActionOverlayLayout.horizontalInset, dy: ChatActionOverlayLayout.spacing)
            XCTAssertGreaterThanOrEqual(place.barFrame.minX, usable.minX - 0.5)
            XCTAssertLessThanOrEqual(place.barFrame.maxX, usable.maxX + 0.5)
            XCTAssertLessThanOrEqual(place.barFrame.width, usable.width + 0.5)
            XCTAssertGreaterThanOrEqual(place.menuFrame.minX, usable.minX - 0.5)
            XCTAssertLessThanOrEqual(place.menuFrame.maxX, usable.maxX + 0.5)
        }
    }

    func testPeerAlignsBarAndMenuToLeading() {
        let bubble = CGRect(x: 20, y: 300, width: 160, height: 50)
        let place = ChatActionOverlayLayout.resolve(
            bubbleFrame: bubble,
            safeArea: safe,
            barHeight: 52,
            menuHeight: 160,
            barWidth: 280,
            menuWidth: 240,
            isMine: false
        )
        XCTAssertEqual(place.barFrame.minX, bubble.minX, accuracy: 1)
        XCTAssertEqual(place.menuFrame.minX, bubble.minX, accuracy: 1)
    }
}
