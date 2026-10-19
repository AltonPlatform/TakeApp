import XCTest
@testable import AltonApp

final class DMEditRulesTests: XCTestCase {
    private let userID = "user-1"

    func testAllowsOwnRecentText() {
        let msg = makeMessage(kind: .text, senderID: userID, createdAt: Date())
        XCTAssertTrue(DMEditRules.canEdit(msg, currentUserID: userID))
    }

    func testRejectsExpiredWindow() {
        let created = Date().addingTimeInterval(-(DMEditRules.windowMinutes + 60))
        let msg = makeMessage(kind: .text, senderID: userID, createdAt: created)
        XCTAssertFalse(DMEditRules.canEdit(msg, currentUserID: userID))
    }

    func testRejectsOtherUser() {
        let msg = makeMessage(kind: .text, senderID: "other", createdAt: Date())
        XCTAssertFalse(DMEditRules.canEdit(msg, currentUserID: userID))
    }

    func testRejectsNonText() {
        let msg = makeMessage(kind: .image, senderID: userID, createdAt: Date())
        XCTAssertFalse(DMEditRules.canEdit(msg, currentUserID: userID))
    }

    func testRejectsDeleted() {
        var msg = makeMessage(kind: .text, senderID: userID, createdAt: Date())
        msg.deletedAt = ISO8601DateFormatter().string(from: Date())
        XCTAssertFalse(DMEditRules.canEdit(msg, currentUserID: userID))
    }

    func testRejectsPending() {
        var msg = makeMessage(kind: .text, senderID: "me", createdAt: Date())
        msg.isPending = true
        XCTAssertFalse(DMEditRules.canEdit(msg, currentUserID: userID))
    }

    func testAllowsOptimisticMeSender() {
        let msg = makeMessage(kind: .text, senderID: "me", createdAt: Date())
        XCTAssertTrue(DMEditRules.canEdit(msg, currentUserID: userID))
    }

    private func makeMessage(
        kind: DMMessageKind,
        senderID: String,
        createdAt: Date
    ) -> DMMessage {
        DMMessage(
            id: "m1",
            conversationID: "c1",
            seq: 1,
            senderID: senderID,
            kind: kind,
            body: "Hello",
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: "c1",
            createdAt: ISO8601DateFormatter().string(from: createdAt),
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
