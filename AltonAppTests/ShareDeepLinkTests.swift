import XCTest
@testable import AltonApp

final class ShareDeepLinkTests: XCTestCase {
    func testInviteCodeFromSharePath() {
        let code = "Ab12Cd34.0123456789abcdef"
        XCTAssertEqual(ShareDeepLinkParser.inviteCode(fromPath: "/i/\(code)"), code)
        XCTAssertEqual(ShareDeepLinkParser.inviteCode(fromPath: "/i/\(code)/"), code)
        XCTAssertNil(ShareDeepLinkParser.inviteCode(fromPath: "/i/"))
        XCTAssertTrue(ShareDeepLinkParser.isValidInviteCode(code))
        XCTAssertFalse(ShareDeepLinkParser.isValidInviteCode("short.bad"))
    }
}
