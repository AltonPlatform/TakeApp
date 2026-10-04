import XCTest
@testable import AltonApp

final class AttachmentReorderTests: XCTestCase {
    func testMoveFromToReordersArray() {
        var items = ["a", "b", "c", "d"]
        items = AttachmentReorder.move(items, from: 0, to: 2)
        XCTAssertEqual(items, ["b", "c", "a", "d"])
    }

    func testMoveBackwardReordersArray() {
        let items = AttachmentReorder.move(["a", "b", "c", "d"], from: 3, to: 1)
        XCTAssertEqual(items, ["a", "d", "b", "c"])
    }

    func testMoveToSameIndexIsNoop() {
        let items = AttachmentReorder.move(["a", "b", "c"], from: 1, to: 1)
        XCTAssertEqual(items, ["a", "b", "c"])
    }

    func testMoveOutOfBoundsIsNoop() {
        var items = ["a", "b"]
        items = AttachmentReorder.move(items, from: 5, to: 0)
        XCTAssertEqual(items, ["a", "b"])
        items = AttachmentReorder.move(items, from: 0, to: 5)
        XCTAssertEqual(items, ["a", "b"])
        items = AttachmentReorder.move(items, from: -1, to: 1)
        XCTAssertEqual(items, ["a", "b"])
    }

    func testRemoveAtRemovesOne() {
        let items = ["a", "b", "c"]
        XCTAssertEqual(AttachmentReorder.remove(items, at: 1), ["a", "c"])
    }

    func testRemoveOutOfBoundsIsNoop() {
        let items = ["a", "b"]
        XCTAssertEqual(AttachmentReorder.remove(items, at: 2), ["a", "b"])
        XCTAssertEqual(AttachmentReorder.remove(items, at: -1), ["a", "b"])
    }

    func testDragPayloadRoundTripsAndRejectsForeignText() {
        XCTAssertEqual(AttachmentReorder.index(fromPayload: AttachmentReorder.payload(forIndex: 3)), 3)
        XCTAssertNil(AttachmentReorder.index(fromPayload: "3"))
        XCTAssertNil(AttachmentReorder.index(fromPayload: "hello"))
    }

    @MainActor
    func testStripDefaultsToLegacyStyle() {
        // Comment/reply screens rely on the default; they must keep the pre-redesign look.
        let strip = ComposerAttachmentStrip(attachments: [], onRemove: { _ in })
        XCTAssertEqual(strip.style, .legacy)
    }

    @MainActor
    func testStripBuildsForCounts0_1_4_10() {
        for style in [AttachmentStripStyle.legacy, .takeComposer] {
            for count in [0, 1, 4, 10] {
                let items = (0..<count).map {
                    PostAttachment(data: Data(), contentType: "image/jpeg", filename: "\($0).jpg")
                }
                let strip = ComposerAttachmentStrip(
                    attachments: items,
                    onRemove: { _ in },
                    onMove: { _, _ in },
                    style: style
                )
                // Smoke: the strip builds for each style/count; layout is verified manually.
                _ = strip.body
                XCTAssertEqual(strip.style, style)
                XCTAssertEqual(strip.attachments.count, count)
                if count > 0 {
                    XCTAssertEqual(AttachmentReorder.remove(strip.attachments, at: 0).count, count - 1)
                }
            }
        }
    }
}
