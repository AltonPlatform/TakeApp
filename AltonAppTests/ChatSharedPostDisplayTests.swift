import XCTest
@testable import AltonApp

final class ChatSharedPostDisplayTests: XCTestCase {
    func testPostWinsOverCardForAvatarAndName() {
        let postAvatar = URL(string: "https://cdn.example/post-avatar.jpg")!
        let cardAvatar = URL(string: "https://cdn.example/card-avatar.jpg")!
        let post = makePost(
            id: "p1",
            creatorID: "u1",
            username: "neo",
            displayName: "Neo",
            avatarURL: postAvatar,
            postType: .take,
            content: "Hello from post"
        )
        let card = DMPostCard(
            postID: "p1",
            postType: "take",
            creatorID: "u1",
            creatorUsername: "old_neo",
            contentPreview: "card preview",
            thumbnailURL: nil,
            unavailable: false,
            creatorAvatarURL: cardAvatar
        )
        let display = ChatSharedPostDisplay.merge(
            postID: "p1",
            postTypeHint: "take",
            post: post,
            card: card
        )
        XCTAssertEqual(display.avatarURL, postAvatar)
        XCTAssertEqual(display.displayName, "Neo")
        XCTAssertEqual(display.handle, "@neo")
        XCTAssertEqual(display.contentPreview, "Hello from post")
        XCTAssertTrue(display.hasHydratedPost)
        XCTAssertFalse(display.unavailable)
    }

    func testFallsBackToCardWhenPostMissing() {
        let cardAvatar = URL(string: "https://cdn.example/card-avatar.jpg")!
        let card = DMPostCard(
            postID: "p2",
            postType: "shot",
            creatorID: "u2",
            creatorUsername: "trinity",
            contentPreview: "shot preview",
            thumbnailURL: URL(string: "https://cdn.example/thumb.jpg"),
            unavailable: false,
            creatorAvatarURL: cardAvatar
        )
        let display = ChatSharedPostDisplay.merge(
            postID: "p2",
            postTypeHint: "shot",
            post: nil,
            card: card
        )
        XCTAssertEqual(display.avatarURL, cardAvatar)
        XCTAssertEqual(display.handle, "@trinity")
        XCTAssertTrue(display.isShot)
        XCTAssertFalse(display.hasHydratedPost)
        XCTAssertEqual(display.thumbnailURLs.count, 1)
    }

    func testUnavailableCardPropagates() {
        let card = DMPostCard(
            postID: "gone",
            postType: "take",
            creatorID: "",
            creatorUsername: "",
            contentPreview: "",
            thumbnailURL: nil,
            unavailable: true,
            creatorAvatarURL: nil
        )
        let display = ChatSharedPostDisplay.merge(
            postID: "gone",
            postTypeHint: nil,
            post: nil,
            card: card
        )
        XCTAssertTrue(display.unavailable)
        XCTAssertFalse(display.hasHydratedPost)
    }

    func testAvatarFallsBackToCardWhenPostHasNone() {
        let cardAvatar = URL(string: "https://cdn.example/card-only.jpg")!
        let post = makePost(
            id: "p3",
            creatorID: "u3",
            username: "morpheus",
            displayName: "Morpheus",
            avatarURL: nil,
            postType: .take,
            content: "hi"
        )
        let card = DMPostCard(
            postID: "p3",
            postType: "take",
            creatorID: "u3",
            creatorUsername: "morpheus",
            contentPreview: "hi",
            thumbnailURL: nil,
            unavailable: false,
            creatorAvatarURL: cardAvatar
        )
        let display = ChatSharedPostDisplay.merge(
            postID: "p3",
            postTypeHint: "take",
            post: post,
            card: card
        )
        XCTAssertEqual(display.avatarURL, cardAvatar)
        XCTAssertTrue(display.hasHydratedPost)
    }

    private func makePost(
        id: String,
        creatorID: String,
        username: String?,
        displayName: String?,
        avatarURL: URL?,
        postType: PostType,
        content: String?
    ) -> Post {
        Post(
            id: id,
            creatorID: creatorID,
            creatorUsername: username,
            creatorDisplayName: displayName,
            creatorAvatarURL: avatarURL,
            postType: postType,
            status: .published,
            content: content,
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: nil,
            imageURLs: [],
            viewCount: 42,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
