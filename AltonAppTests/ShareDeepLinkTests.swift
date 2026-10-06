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
}
