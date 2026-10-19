import XCTest
@testable import AltonApp
import SwiftUI

final class ChatBubbleShapeTests: XCTestCase {
    func testBoundingRectStaysInsideForMineTail() {
        let shape = ChatBubbleShape(isMine: true, showTail: true, groupedWithPrevious: false)
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.5)
    }

    func testBoundingRectStaysInsideForPeerTail() {
        let shape = ChatBubbleShape(isMine: false, showTail: true, groupedWithPrevious: false)
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.5)
    }

    func testMineTailTipAtBottomTrailing() {
        let shape = ChatBubbleShape(isMine: true, showTail: true, groupedWithPrevious: false)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let bounds = shape.path(in: rect).boundingRect
        XCTAssertEqual(bounds.maxX, rect.maxX, accuracy: 1)
        XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 1)
    }

    func testPeerTailTipAtBottomLeading() {
        let shape = ChatBubbleShape(isMine: false, showTail: true, groupedWithPrevious: false)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let bounds = shape.path(in: rect).boundingRect
        XCTAssertEqual(bounds.minX, rect.minX, accuracy: 1)
        XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 1)
    }

    func testTailWidthConstant() {
        XCTAssertEqual(ChatBubbleShape.tailWidth, 9)
    }

    func testTailProgressZeroMatchesNoTail() {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 48)
        let noTail = ChatBubbleShape(isMine: true, showTail: false, groupedWithPrevious: false)
        let zero = ChatBubbleShape(isMine: true, groupedWithPrevious: false, tailProgress: 0)
        let a = noTail.path(in: rect).boundingRect
        let b = zero.path(in: rect).boundingRect
        XCTAssertEqual(a.minX, b.minX, accuracy: 0.5)
        XCTAssertEqual(a.maxX, b.maxX, accuracy: 0.5)
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.5)
        XCTAssertEqual(a.maxY, b.maxY, accuracy: 0.5)
    }

    func testMidTailProgressStaysInside() {
        let shape = ChatBubbleShape(isMine: true, groupedWithPrevious: false, tailProgress: 0.5)
        let rect = CGRect(x: 0, y: 0, width: 140, height: 56)
        let bounds = shape.path(in: rect).boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.5)
    }

    func testTopEdgeTouchesBubbleTop() {
        let shape = ChatBubbleShape(isMine: true, showTail: false, groupedWithPrevious: false)
        let rect = CGRect(x: 0, y: 0, width: 120, height: 48)
        let path = shape.path(in: rect)
        XCTAssertEqual(path.boundingRect.minY, rect.minY, accuracy: 0.5)
        let probe = CGPoint(x: rect.minX + ChatBubbleShape.outerRadius + 2, y: rect.minY)
        XCTAssertTrue(
            path.contains(probe) || path.boundingRect.minY <= rect.minY + 0.5,
            "top edge should touch the bubble's top"
        )
    }

    func testSingleLineBubbleStaysInside() {
        let shape = ChatBubbleShape(isMine: true, showTail: true, groupedWithPrevious: false)
        let rect = CGRect(x: 0, y: 0, width: 90, height: 34)
        let bounds = shape.path(in: rect).boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.5)
    }
}
