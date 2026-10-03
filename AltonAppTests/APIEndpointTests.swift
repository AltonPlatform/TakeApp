import XCTest
@testable import AltonApp

final class APIEndpointTests: XCTestCase {
    private let baseURL = URL(string: "https://api.altons.trade/v1")!

    func testValidateResourceIDAcceptsUlids() throws {
        XCTAssertNoThrow(try APIEndpoint.validateResourceID("01JABCDEFGHJKMNPQRSTVWXYZ0"))
    }

    func testValidateResourceIDRejectsInvalidCharacters() {
        XCTAssertThrowsError(try APIEndpoint.validateResourceID("../etc/passwd"))
        XCTAssertThrowsError(try APIEndpoint.validateResourceID(""))
    }

    func testFeedURLBuildsCursorAndModeQuery() throws {
        let url = try APIEndpoint.feed(cursor: "abc123", limit: 25, mode: "following").url(baseURL: baseURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["limit"], "25")
        XCTAssertEqual(items["cursor"], "abc123")
        XCTAssertEqual(items["mode"], "following")
        XCTAssertEqual(url.path, "/v1/feed")
    }

    func testDeletePostRequiresValidID() throws {
        let url = try APIEndpoint.deletePost(id: "01JABCDEFGHJKMNPQRSTVWXYZ0").url(baseURL: baseURL)
        XCTAssertEqual(url.path, "/v1/posts/01JABCDEFGHJKMNPQRSTVWXYZ0")
        XCTAssertEqual(APIEndpoint.deletePost(id: "01JABCDEFGHJKMNPQRSTVWXYZ0").method, .delete)
    }

    func testUserTakePostsUsesNewPathAndLegacyFallback() throws {
        let id = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        let modern = try APIEndpoint.userTakePosts(id: id, cursor: nil, limit: 20).url(baseURL: baseURL)
        XCTAssertEqual(modern.path, "/v1/users/\(id)/posts/takes")
        let legacy = try APIEndpoint.userTakePosts(id: id, cursor: nil, limit: 20, legacy: true).url(baseURL: baseURL)
        XCTAssertEqual(legacy.path, "/v1/users/\(id)/posts/threads")
    }

    func testUserShotPostsUsesNewPathAndLegacyFallback() throws {
        let id = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        let modern = try APIEndpoint.userShotPosts(id: id, cursor: nil, limit: 20).url(baseURL: baseURL)
        XCTAssertEqual(modern.path, "/v1/users/\(id)/posts/shots")
        let legacy = try APIEndpoint.userShotPosts(id: id, cursor: nil, limit: 20, legacy: true).url(baseURL: baseURL)
        XCTAssertEqual(legacy.path, "/v1/users/\(id)/posts/videos")
    }

    func testCommentLikeURLAndMethod() throws {
        let id = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        let url = try APIEndpoint.commentLike(id: id).url(baseURL: baseURL)
        XCTAssertEqual(url.path, "/v1/comments/\(id)/like")
        XCTAssertEqual(APIEndpoint.commentLike(id: id).method, .post)
    }

    func testStickerPackEndpointsAreGet() throws {
        let packs = try APIEndpoint.stickerPacks.url(baseURL: baseURL)
        XCTAssertEqual(packs.path, "/v1/stickers/packs")
        XCTAssertEqual(APIEndpoint.stickerPacks.method, .get)

        let id = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        let pack = try APIEndpoint.stickerPack(id: id).url(baseURL: baseURL)
        XCTAssertEqual(pack.path, "/v1/stickers/packs/\(id)")
        XCTAssertEqual(APIEndpoint.stickerPack(id: id).method, .get)
    }

    func testReportCommentAndReportReasonsEndpoints() throws {
        let id = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        let reportComment = try APIEndpoint.reportComment(commentID: id).url(baseURL: baseURL)
        XCTAssertEqual(reportComment.path, "/v1/comments/\(id)/report")
        XCTAssertEqual(APIEndpoint.reportComment(commentID: id).method, .post)

        let reasons = try APIEndpoint.reportReasons.url(baseURL: baseURL)
        XCTAssertEqual(reasons.path, "/v1/moderation/report-reasons")
        XCTAssertEqual(APIEndpoint.reportReasons.method, .get)
    }

    func testCommentDTODecodesNestedSticker() throws {
        let json = """
        {
          "id": "01JCOMMENT0000000000000000",
          "post_id": "01JPOST0000000000000000000",
          "author_id": "01JUSER0000000000000000000",
          "content": "",
          "sticker": {
            "id": "01JSTICKER000000000000000",
            "url": "https://cdn.example/stickers/a.webp",
            "thumb_url": "https://cdn.example/stickers/a_thumb.webp",
            "pack_id": "01JPACK0000000000000000000",
            "width": 120,
            "height": 120
          }
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(CommentDTO.self, from: json)
        let comment = dto.toDomain()
        XCTAssertEqual(comment.sticker?.stickerID, "01JSTICKER000000000000000")
        XCTAssertEqual(comment.sticker?.url.absoluteString, "https://cdn.example/stickers/a.webp")
        XCTAssertTrue(comment.content.isEmpty)
        XCTAssertTrue(comment.imageURLs.isEmpty)
        XCTAssertNil(comment.gif)
    }

    func testCommentDTODecodesNestedGif() throws {
        let json = """
        {
          "id": "01JCOMMENT0000000000000000",
          "post_id": "01JPOST0000000000000000000",
          "author_id": "01JUSER0000000000000000000",
          "content": "",
          "gif": {
            "id": "01JGIF00000000000000000000",
            "url": "https://cdn.example/gifs/a.webp",
            "thumb_url": "https://cdn.example/gifs/a_thumb.webp",
            "width": 220,
            "height": 180
          }
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(CommentDTO.self, from: json)
        let comment = dto.toDomain()
        XCTAssertEqual(comment.gif?.id, "01JGIF00000000000000000000")
        XCTAssertEqual(comment.gif?.url.absoluteString, "https://cdn.example/gifs/a.webp")
        XCTAssertNil(comment.sticker)
        XCTAssertTrue(comment.imageURLs.isEmpty)
    }

    func testAddCommentEncodesKlipyGifWithoutPendingMedia() throws {
        let dto = AddCommentRequestDTO(
            content: "",
            showInFeed: true,
            parentCommentID: nil,
            pendingGif: PendingCommentGif(
                klipyGifID: "42",
                sourceURL: URL(string: "https://media.klipy.com/xs/cat.webp")!,
                contentType: "image/webp",
                width: 220,
                height: 180
            )
        )
        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["klipy_gif_id"] as? String, "42")
        XCTAssertEqual(json["gif_source_url"] as? String, "https://media.klipy.com/xs/cat.webp")
        XCTAssertEqual(json["gif_content_type"] as? String, "image/webp")
        XCTAssertEqual(json["gif_width"] as? Int, 220)
        XCTAssertEqual(json["gif_height"] as? Int, 180)
        XCTAssertNil(json["pending_media"])
        XCTAssertNil(json["sticker_id"])
    }

    func testAddCommentEncodesPendingMediaForGIFOnly() throws {
        let dto = AddCommentRequestDTO(
            content: "",
            showInFeed: true,
            parentCommentID: nil,
            pendingMedia: true
        )
        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["pending_media"] as? Bool, true)
        XCTAssertEqual(json["content"] as? String, "")
        XCTAssertNil(json["sticker_id"])
    }
}
