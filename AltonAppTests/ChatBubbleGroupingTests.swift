import XCTest
@testable import AltonApp

final class ChatBubbleGroupingTests: XCTestCase {
    private func message(
        id: String,
        sender: String,
        at iso: String
    ) -> DMMessage {
        DMMessage(
            id: id,
            conversationID: "c1",
            seq: Int64(id.hashValue),
            senderID: sender,
            kind: .text,
            body: "hi",
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: id,
            createdAt: iso,
            editedAt: nil,
            deletedAt: nil,
            mediaURL: nil,
            mediaThumbURL: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            reactions: [],
            localImageData: nil,
            isPending: false,
            isFailed: false
        )
    }

    func testGroupedWithPreviousWithinWindow() {
        let messages = [
            message(id: "1", sender: "a", at: "2026-10-15T10:00:00Z"),
            message(id: "2", sender: "a", at: "2026-10-15T10:02:00Z"),
        ]
        XCTAssertFalse(ChatBubbleGrouping.isGroupedWithPrevious(messages: messages, at: 0))
        XCTAssertTrue(ChatBubbleGrouping.isGroupedWithPrevious(messages: messages, at: 1))
        XCTAssertFalse(ChatBubbleGrouping.shouldShowTail(messages: messages, at: 0))
        XCTAssertTrue(ChatBubbleGrouping.shouldShowTail(messages: messages, at: 1))
    }

    func testSenderChangeBreaksGroup() {
        let messages = [
            message(id: "1", sender: "a", at: "2026-10-15T10:00:00Z"),
            message(id: "2", sender: "b", at: "2026-10-15T10:00:30Z"),
        ]
        XCTAssertFalse(ChatBubbleGrouping.isGroupedWithPrevious(messages: messages, at: 1))
        XCTAssertTrue(ChatBubbleGrouping.shouldShowTail(messages: messages, at: 0))
        XCTAssertTrue(ChatBubbleGrouping.shouldShowTail(messages: messages, at: 1))
    }

    func testOutsideWindowBreaksGroup() {
        let messages = [
            message(id: "1", sender: "a", at: "2026-10-15T10:00:00Z"),
            message(id: "2", sender: "a", at: "2026-10-15T10:06:00Z"),
        ]
        XCTAssertFalse(ChatBubbleGrouping.isGroupedWithPrevious(messages: messages, at: 1))
        XCTAssertTrue(ChatBubbleGrouping.shouldShowTail(messages: messages, at: 0))
    }
}
