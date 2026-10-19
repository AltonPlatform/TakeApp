import XCTest
@testable import AltonApp

final class ChatRowsBuilderTests: XCTestCase {
    func testDateSeparatorOnDayChange() {
        let a = makeMessage(id: "1", seq: 1, sender: "u1", body: "a", createdAt: "2026-10-15T10:00:00Z")
        let b = makeMessage(id: "2", seq: 2, sender: "u1", body: "b", createdAt: "2026-10-16T10:00:00Z")
        let rows = ChatRowsBuilder.build(messages: [a, b], members: [])
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].showDate)
        XCTAssertTrue(rows[1].showDate)
    }

    func testGroupingAndTail() {
        let t0 = "2026-10-16T10:00:00Z"
        let t1 = "2026-10-16T10:01:00Z"
        let t2 = "2026-10-16T10:02:00Z"
        let a = makeMessage(id: "1", seq: 1, sender: "me", body: "a", createdAt: t0)
        let b = makeMessage(id: "2", seq: 2, sender: "me", body: "b", createdAt: t1)
        let c = makeMessage(id: "3", seq: 3, sender: "me", body: "c", createdAt: t2)
        let rows = ChatRowsBuilder.build(messages: [a, b, c], members: [])
        XCTAssertFalse(rows[0].grouped)
        XCTAssertTrue(rows[1].grouped)
        XCTAssertTrue(rows[2].grouped)
        XCTAssertFalse(rows[0].showTail)
        XCTAssertFalse(rows[1].showTail)
        XCTAssertTrue(rows[2].showTail)
    }

    func testReplyPreviewBySeq() {
        let parent = makeMessage(id: "1", seq: 1, sender: "u1", body: "hello", createdAt: "2026-10-16T10:00:00Z")
        var reply = makeMessage(id: "2", seq: 2, sender: "me", body: "hi", createdAt: "2026-10-16T10:01:00Z")
        reply = DMMessage(
            id: reply.id,
            conversationID: reply.conversationID,
            seq: reply.seq,
            senderID: reply.senderID,
            kind: reply.kind,
            body: reply.body,
            postID: nil,
            postType: nil,
            replyToSeq: 1,
            clientMsgID: reply.clientMsgID,
            createdAt: reply.createdAt,
            editedAt: nil,
            deletedAt: nil,
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
        let rows = ChatRowsBuilder.build(messages: [parent, reply], members: [])
        XCTAssertEqual(rows[1].replyPreview?.id, "1")
        XCTAssertEqual(rows[1].replyPreview?.body, "hello")
    }

    func testRowIDStaysOnClientMsgIDAfterConfirm() {
        let pending = makeMessage(id: "client-1", seq: 1, sender: "me", body: "hi", createdAt: "2026-10-16T10:00:00Z")
        var confirmed = makeMessage(id: "server-9", seq: 1, sender: "me", body: "hi", createdAt: "2026-10-16T10:00:00Z")
        confirmed = DMMessage(
            id: "server-9",
            conversationID: confirmed.conversationID,
            seq: confirmed.seq,
            senderID: confirmed.senderID,
            kind: confirmed.kind,
            body: confirmed.body,
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: "client-1",
            createdAt: confirmed.createdAt,
            editedAt: nil,
            deletedAt: nil,
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
        let pendingID = ChatRowsBuilder.build(messages: [pending], members: []).first?.id
        let confirmedID = ChatRowsBuilder.build(messages: [confirmed], members: []).first?.id
        XCTAssertEqual(pendingID, "client-1")
        XCTAssertEqual(confirmedID, "client-1")
    }

    func testSenderNameFromMembers() {
        let member = DMConversationMember(
            userID: "u9",
            username: "neo",
            displayName: "Neo",
            avatarURL: nil,
            role: "member"
        )
        let msg = makeMessage(id: "1", seq: 1, sender: "u9", body: "x", createdAt: "2026-10-16T10:00:00Z")
        let rows = ChatRowsBuilder.build(messages: [msg], members: [member])
        XCTAssertEqual(rows[0].senderName, "Neo")
    }

    func testReplacingKeepsGrouping() {
        let t0 = "2026-10-16T10:00:00Z"
        let t1 = "2026-10-16T10:01:00Z"
        let a = makeMessage(id: "1", seq: 1, sender: "me", body: "a", createdAt: t0)
        let b = makeMessage(id: "2", seq: 2, sender: "me", body: "b", createdAt: t1)
        let rows = ChatRowsBuilder.build(messages: [a, b], members: [])
        var edited = b
        edited = DMMessage(
            id: b.id,
            conversationID: b.conversationID,
            seq: b.seq,
            senderID: b.senderID,
            kind: b.kind,
            body: "edited",
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: b.clientMsgID,
            createdAt: b.createdAt,
            editedAt: nil,
            deletedAt: nil,
            mediaURL: nil,
            mediaThumbURL: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: Data([1, 2, 3]),
            isPending: false,
            isFailed: false
        )
        let next = ChatRowsBuilder.replacing(rows, message: edited)
        XCTAssertEqual(next[1].message.body, "edited")
        XCTAssertEqual(next[1].grouped, rows[1].grouped)
        XCTAssertEqual(next[1].showTail, rows[1].showTail)
        XCTAssertEqual(next[0].showTail, rows[0].showTail)
    }

    func testAppendingUpdatesPreviousTail() {
        let t0 = "2026-10-16T10:00:00Z"
        let t1 = "2026-10-16T10:01:00Z"
        let a = makeMessage(id: "1", seq: 1, sender: "me", body: "a", createdAt: t0)
        let rows = ChatRowsBuilder.build(messages: [a], members: [])
        XCTAssertTrue(rows[0].showTail)
        let b = makeMessage(id: "2", seq: 2, sender: "me", body: "b", createdAt: t1)
        let next = ChatRowsBuilder.appending(b, onto: rows, messages: [a, b], members: [])
        XCTAssertEqual(next.count, 2)
        XCTAssertFalse(next[0].showTail)
        XCTAssertTrue(next[1].showTail)
        XCTAssertTrue(next[1].grouped)
    }

    private func makeMessage(
        id: String,
        seq: Int64,
        sender: String,
        body: String,
        createdAt: String
    ) -> DMMessage {
        DMMessage(
            id: id,
            conversationID: "c1",
            seq: seq,
            senderID: sender,
            kind: .text,
            body: body,
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: id,
            createdAt: createdAt,
            editedAt: nil,
            deletedAt: nil,
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
