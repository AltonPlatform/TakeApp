import XCTest
@testable import AltonApp

@MainActor
final class MessageCacheStoreTests: XCTestCase {
    func testSwitchingUserDropsPreviousMessagesAndStaleWrites() throws {
        let store = try MessageCacheStore(inMemory: true)
        store.beginSession(userID: "user-a")
        let generationA = store.cacheGeneration
        store.upsert(messages: [sample(id: "a1", body: "from a")], generation: generationA)
        XCTAssertEqual(store.messages(conversationID: "c1").map(\.body), ["from a"])

        store.beginSession(userID: "user-b")
        store.upsert(messages: [sample(id: "late", body: "late from a")], generation: generationA)
        XCTAssertTrue(store.messages(conversationID: "c1").isEmpty)

        store.upsert(messages: [sample(id: "b1", body: "from b")], generation: store.cacheGeneration)
        XCTAssertEqual(store.messages(conversationID: "c1").map(\.body), ["from b"])
    }

    func testSameUserBeginSessionKeepsCache() throws {
        let store = try MessageCacheStore(inMemory: true)
        store.beginSession(userID: "user-a")
        store.upsert(messages: [sample(id: "a1", body: "kept")], generation: store.cacheGeneration)
        store.beginSession(userID: "user-a")
        XCTAssertEqual(store.messages(conversationID: "c1").map(\.body), ["kept"])
    }

    func testPostCardRoundTripsAndDoesNotReplaceHydratedPost() throws {
        let store = try MessageCacheStore(inMemory: true)
        let thumb = URL(string: "https://cdn.example/thumb.jpg")!
        let card = DMPostCard(
            postID: "p1",
            postType: "take",
            creatorID: "u1",
            creatorUsername: "neo",
            contentPreview: "preview",
            thumbnailURL: thumb,
            unavailable: false,
            creatorAvatarURL: nil
        )
        store.upsertPostCards([card], generation: store.cacheGeneration)
        let preview = store.shares(postIDs: ["p1"])
        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview[0].card.contentPreview, "preview")
        XCTAssertNil(preview[0].post)

        let image = URL(string: "https://cdn.example/full.jpg")!
        let post = Post(
            id: "p1",
            creatorID: "u1",
            creatorUsername: "neo",
            creatorDisplayName: "Neo",
            creatorAvatarURL: nil,
            postType: .take,
            status: .published,
            content: "full take body",
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: thumb,
            imageURLs: [image],
            viewCount: 3,
            likeCount: 1,
            commentCount: 2,
            saveCount: 0,
            shareCount: 4,
            repostCount: 5,
            isLiked: false,
            isBookmarked: false,
            isReposted: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            ageGated: false
        )
        store.upsertSharedPost(post, generation: store.cacheGeneration)
        store.upsertPostCards([card], generation: store.cacheGeneration)

        let hydrated = store.shares(postIDs: ["p1"])
        XCTAssertEqual(hydrated.first?.post?.content, "full take body")
        XCTAssertEqual(hydrated.first?.post?.imageURLs, [image])
        XCTAssertEqual(hydrated.first?.post?.commentCount, 2)
        XCTAssertEqual(hydrated.first?.card.contentPreview, "full take body")
    }

    func testUnavailableCardClearsHydratedShare() throws {
        let store = try MessageCacheStore(inMemory: true)
        let post = Post(
            id: "gone",
            creatorID: "u1",
            creatorUsername: "neo",
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .shot,
            status: .published,
            content: "shot",
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: nil,
            imageURLs: [],
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: nil
        )
        store.upsertSharedPost(post, generation: store.cacheGeneration)
        store.upsertPostCards([
            DMPostCard(
                postID: "gone",
                postType: "shot",
                creatorID: "u1",
                creatorUsername: "neo",
                contentPreview: "",
                thumbnailURL: nil,
                unavailable: true,
                creatorAvatarURL: nil
            )
        ], generation: store.cacheGeneration)
        let share = store.shares(postIDs: ["gone"]).first
        XCTAssertEqual(share?.card.unavailable, true)
        XCTAssertNil(share?.post)
    }

    func testFirstAdoptKeepsRowsWrittenBeforeOwner() throws {
        let store = try MessageCacheStore(inMemory: true)
        store.upsert(messages: [sample(id: "a1", body: "restored")], generation: store.cacheGeneration)
        store.beginSession(userID: "user-a")
        XCTAssertEqual(store.messages(conversationID: "c1").map(\.body), ["restored"])
    }

    func testReplyAndMediaRoundTrip() throws {
        let store = try MessageCacheStore(inMemory: true)
        var message = sample(id: "reply", body: "answer")
        message = DMMessage(
            id: message.id,
            conversationID: message.conversationID,
            seq: 8,
            senderID: message.senderID,
            kind: .image,
            body: message.body,
            postID: nil,
            postType: nil,
            replyToSeq: 3,
            clientMsgID: message.clientMsgID,
            createdAt: message.createdAt,
            editedAt: nil,
            deletedAt: nil,
            mediaURL: URL(string: "https://cdn.example/full.jpg"),
            mediaThumbURL: URL(string: "https://cdn.example/thumb.jpg"),
            mediaWidth: 300,
            mediaHeight: 400,
            mediaStatus: "ready",
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: nil,
            isPending: false,
            isFailed: false
        )
        store.upsert(messages: [message], generation: store.cacheGeneration)
        let loaded = store.messages(conversationID: "c1").first
        XCTAssertEqual(loaded?.replyToSeq, 3)
        XCTAssertEqual(loaded?.mediaURL?.absoluteString, "https://cdn.example/full.jpg")
        XCTAssertEqual(loaded?.mediaWidth, 300)
        XCTAssertEqual(store.latestSeq(conversationID: "c1"), 8)
    }

    private func sample(id: String, body: String) -> DMMessage {
        DMMessage(
            id: id,
            conversationID: "c1",
            seq: 1,
            senderID: "peer",
            kind: .text,
            body: body,
            postID: nil,
            postType: nil,
            replyToSeq: nil,
            clientMsgID: id,
            createdAt: "2026-10-16T10:00:00Z",
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
