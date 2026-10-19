import XCTest
@testable import AltonApp

final class ChatAttachSelectionTests: XCTestCase {
    func testToggleAddsAndNumbers() {
        var selection = ChatAttachSelection()
        selection.toggle("a", maxCount: 3)
        selection.toggle("b", maxCount: 3)
        XCTAssertEqual(selection.count, 2)
        XCTAssertEqual(selection.number(for: "a"), 1)
        XCTAssertEqual(selection.number(for: "b"), 2)
    }

    func testToggleRemovesAndRenumbers() {
        var selection = ChatAttachSelection()
        selection.toggle("a", maxCount: 5)
        selection.toggle("b", maxCount: 5)
        selection.toggle("c", maxCount: 5)
        selection.toggle("b", maxCount: 5)
        XCTAssertEqual(selection.orderedIDs, ["a", "c"])
        XCTAssertEqual(selection.number(for: "c"), 2)
        XCTAssertNil(selection.number(for: "b"))
    }

    func testCapturedIDsShareTheSameOrder() {
        var selection = ChatAttachSelection()
        selection.toggle("asset-1", maxCount: 10)
        selection.toggle(ChatCaptureID.make(), maxCount: 10)
        XCTAssertEqual(selection.count, 2)
        XCTAssertTrue(ChatCaptureID.isCapture(selection.orderedIDs[1]))
        XCTAssertFalse(ChatCaptureID.isCapture("asset-1"))
    }

    func testRespectsMaxCount() {
        var selection = ChatAttachSelection()
        selection.toggle("a", maxCount: 2)
        selection.toggle("b", maxCount: 2)
        selection.toggle("c", maxCount: 2)
        XCTAssertEqual(selection.orderedIDs, ["a", "b"])
        XCTAssertEqual(selection.count, 2)
    }
}
