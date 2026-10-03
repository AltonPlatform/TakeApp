import Foundation
import XCTest

final class NotificationMediaPolicyTests: XCTestCase {
    func testCommunicationEventsAreCommentsRepliesAndMentions() {
        XCTAssertTrue(NotificationMediaPolicy.isCommunicationEvent("comment"))
        XCTAssertTrue(NotificationMediaPolicy.isCommunicationEvent("reply"))
        XCTAssertTrue(NotificationMediaPolicy.isCommunicationEvent("mention"))
        XCTAssertTrue(NotificationMediaPolicy.isCommunicationEvent("like"))
        XCTAssertTrue(NotificationMediaPolicy.isCommunicationEvent("follow"))
        XCTAssertTrue(NotificationMediaPolicy.isCommunicationEvent("profile_view"))
        XCTAssertTrue(NotificationMediaPolicy.isCommunicationEvent("repost"))
        XCTAssertFalse(NotificationMediaPolicy.isCommunicationEvent(nil))
        XCTAssertFalse(NotificationMediaPolicy.isCommunicationEvent(""))
    }

    func testDownloadAllowlistAcceptsTrustedMediaAndLoopback() {
        XCTAssertTrue(isAllowed("https://altons.trade/avatars/a.jpg"))
        XCTAssertTrue(isAllowed("https://media.altons.trade/avatars/a.jpg"))
        XCTAssertTrue(isAllowed("https://dev-media.altons.trade/objects/x.png"))
        XCTAssertTrue(isAllowed("http://127.0.0.1:8086/avatars/a.jpg"))
        XCTAssertTrue(isAllowed("http://localhost/avatars/a.jpg"))
        XCTAssertTrue(isAllowed("https://127.0.0.1/avatars/a.jpg"))
    }

    func testDownloadAllowlistRejectsTrackersPrivateIPsAndCleartextCDN() {
        XCTAssertFalse(isAllowed("https://tracker.example/pixel"))
        XCTAssertFalse(isAllowed("http://media.altons.trade/avatars/a.jpg"))
        XCTAssertFalse(isAllowed("https://192.168.1.1/secret"))
        XCTAssertFalse(isAllowed("https://169.254.169.254/latest/meta-data"))
        XCTAssertFalse(isAllowed("https://10.0.0.5/img.jpg"))
        XCTAssertFalse(isAllowed("file:///tmp/a.jpg"))
        XCTAssertFalse(isAllowed("https://notaltons.trade/a.jpg"))
        XCTAssertFalse(isAllowed("https://altons.trade.evil.com/a.jpg"))
    }

    private func isAllowed(_ raw: String) -> Bool {
        NotificationMediaPolicy.isAllowedDownloadURL(URL(string: raw)!)
    }
}
