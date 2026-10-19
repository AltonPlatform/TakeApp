import XCTest
@testable import AltonApp

final class ChatReplyJumpTests: XCTestCase {
    func testTargetRowIDReturnsClientMsgIDWhenPresent() {
        let parent = makeMessage(id: "server-1", seq: 1, clientMsgID: "client-1", deletedAt: nil)
        let rows = ChatRowsBuilder.build(messages: [parent], members: [])
        XCTAssertEqual(ChatReplyJump.targetRowID(reply: parent, rows: rows), "client-1")
    }

    func testTargetRowIDNilWhenReplyDeleted() {
        let parent = makeMessage(id: "1", seq: 1, clientMsgID: "1", deletedAt: "2026-10-16T11:00:00Z")
        let rows = ChatRowsBuilder.build(messages: [parent], members: [])
        XCTAssertNil(ChatReplyJump.targetRowID(reply: parent, rows: rows))
    }

    func testTargetRowIDNilWhenReplyMissing() {
        let orphan = makeMessage(id: "missing", seq: 99, clientMsgID: "missing", deletedAt: nil)
        let present = makeMessage(id: "1", seq: 1, clientMsgID: "1", deletedAt: nil)
        let rows = ChatRowsBuilder.build(messages: [present], members: [])
        XCTAssertNil(ChatReplyJump.targetRowID(reply: orphan, rows: rows))
    }

    func testTargetRowIDNilWhenReplyIsNil() {
        XCTAssertNil(ChatReplyJump.targetRowID(reply: nil, rows: []))
    }

    private func makeMessage(
        id: String,
        seq: Int64,
        clientMsgID: String,
        deletedAt: String?
    ) -> DMMessage {
        DMMessage(
            id: id,
            conversationID: "c1",
            seq: seq,
            senderID: "u1",
            kind: .text,
            body: "hi",
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: clientMsgID,
            createdAt: "2026-10-16T10:00:00Z",
            editedAt: nil,
            deletedAt: deletedAt,
            mediaURL: nil,
            mediaThumbURL: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: nil,
            isPending: false,
            isFailed: false
        )
    }
}
