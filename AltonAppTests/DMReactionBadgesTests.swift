import XCTest
@testable import AltonApp

final class DMReactionBadgesTests: XCTestCase {
    private func message(reactions: [DMMessageReaction]) -> DMMessage {
        DMMessage(
            id: "m1",
            conversationID: "c1",
            seq: 1,
            senderID: "u1",
            kind: .text,
            body: "hi",
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: "client",
            createdAt: "2026-10-15T10:00:00Z",
            editedAt: nil,
            deletedAt: nil,
            mediaURL: nil,
            mediaThumbURL: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            reactions: reactions,
            localImageData: nil,
            isPending: false,
            isFailed: false
        )
    }

    func testBadgesSortByCountThenFirstSeen() {
        let msg = message(reactions: [
            DMMessageReaction(userID: "a", emoji: "🔥"),
            DMMessageReaction(userID: "b", emoji: "❤️"),
            DMMessageReaction(userID: "c", emoji: "🔥"),
            DMMessageReaction(userID: "d", emoji: "🦄"),
            DMMessageReaction(userID: "e", emoji: "❤️"),
            DMMessageReaction(userID: "f", emoji: "❤️"),
        ])
        let badges = msg.reactionBadges
        XCTAssertEqual(badges.map(\.emoji), ["❤️", "🔥", "🦄"])
        XCTAssertEqual(badges.map(\.count), [3, 2, 1])
    }

    func testArbitraryEmojiAppearsInBadges() {
        let msg = message(reactions: [
            DMMessageReaction(userID: "a", emoji: "🦄"),
            DMMessageReaction(userID: "b", emoji: "🙏"),
        ])
        let emojis = Set(msg.reactionBadges.map(\.emoji))
        XCTAssertEqual(emojis, ["🦄", "🙏"])
    }

    func testMyReaction() {
        let msg = message(reactions: [
            DMMessageReaction(userID: "peer", emoji: "😂"),
            DMMessageReaction(userID: "me", emoji: "🔥"),
        ])
        XCTAssertEqual(msg.myReaction(currentUserID: "me"), "🔥")
        XCTAssertNil(msg.myReaction(currentUserID: "nobody"))
    }

    func testCatalogQuickIsSubsetOfAll() {
        for emoji in DMReactionCatalog.quick {
            XCTAssertTrue(DMReactionCatalog.contains(emoji), "\(emoji) missing from all")
        }
        XCTAssertGreaterThanOrEqual(DMReactionCatalog.all.count, 60)
    }
}
