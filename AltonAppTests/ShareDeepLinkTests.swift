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
