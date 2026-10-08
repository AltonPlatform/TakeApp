import XCTest
@testable import AltonApp

final class ShareDeepLinkTests: XCTestCase {
    func testPostIDFromSharePath() {
        XCTAssertEqual(
            ShareDeepLinkParser.postID(fromPath: "/p/01HABCDEFGHJKMNPQRSTVWXYZ0"),
            "01HABCDEFGHJKMNPQRSTVWXYZ0"
        )
        XCTAssertEqual(
            ShareDeepLinkParser.postID(fromPath: "/p/01HABCDEFGHJKMNPQRSTVWXYZ0/"),
            "01HABCDEFGHJKMNPQRSTVWXYZ0"
        )
        XCTAssertNil(ShareDeepLinkParser.postID(fromPath: "/u/alice"))
        XCTAssertNil(ShareDeepLinkParser.postID(fromPath: "/p/"))
        XCTAssertNil(ShareDeepLinkParser.postID(fromPath: "/p/not valid"))
    }

    func testProfileUsernameFromSharePath() {
        XCTAssertEqual(ShareDeepLinkParser.profileUsername(fromPath: "/u/alice"), "alice")
        XCTAssertEqual(ShareDeepLinkParser.profileUsername(fromPath: "/u/Alice/"), "alice")
        XCTAssertNil(ShareDeepLinkParser.profileUsername(fromPath: "/p/alice"))
        XCTAssertNil(ShareDeepLinkParser.profileUsername(fromPath: "/u/ab"))
        XCTAssertNil(ShareDeepLinkParser.profileUsername(fromPath: "/u/bad-name"))
    }

    func testInviteCodeFromSharePath() {
        let code = "Ab12Cd34.0123456789abcdef"
        XCTAssertEqual(ShareDeepLinkParser.inviteCode(fromPath: "/i/\(code)"), code)
        XCTAssertEqual(ShareDeepLinkParser.inviteCode(fromPath: "/i/\(code)/"), code)
        XCTAssertNil(ShareDeepLinkParser.inviteCode(fromPath: "/i/"))
        XCTAssertTrue(ShareDeepLinkParser.isValidInviteCode(code))
        XCTAssertFalse(ShareDeepLinkParser.isValidInviteCode("short.bad"))
    }

    func testCommentShareURLIncludesQueryParameter() {
        let postID = "01HABCDEFGHJKMNPQRSTVWXYZ0"
        let commentID = "01HBBBBBBBBBBBBBBBBBBBBBBB0"
        let url = PostShareURL.make(postID: postID, commentID: commentID, domain: "share.example")
        XCTAssertEqual(url?.absoluteString, "https://share.example/p/\(postID)?c=\(commentID)")
    }

    func testPostShareURLUsesConfiguredDomain() {
        let postID = "01HABCDEFGHJKMNPQRSTVWXYZ0"
        let url = PostShareURL.make(postID: postID, domain: "alton.social")
        XCTAssertEqual(url?.absoluteString, "https://alton.social/p/\(postID)")
    }
}
