import XCTest
import UIKit
@testable import AltonApp

final class ShareChannelMapperTests: XCTestCase {
    func testMessageMapsToMessages() {
        XCTAssertEqual(ShareChannelMapper.channel(for: .message), "messages")
    }

    func testCopyMapsToCopy() {
        XCTAssertEqual(ShareChannelMapper.channel(for: .copyToPasteboard), "copy")
    }

    func testUnknownMapsToOther() {
        XCTAssertEqual(
            ShareChannelMapper.channel(for: UIActivity.ActivityType("com.example.unknown")),
            "other"
        )
        XCTAssertEqual(ShareChannelMapper.channel(for: nil), "other")
    }

    func testTelegramAndInstagramHeuristics() {
        XCTAssertEqual(
            ShareChannelMapper.channel(for: UIActivity.ActivityType("ph.telegra.Telegraph.Share")),
            "telegram"
        )
        XCTAssertEqual(
            ShareChannelMapper.channel(for: UIActivity.ActivityType("com.burbn.instagram.shareextension")),
            "instagram"
        )
    }

    func testShareMessageIncludesUsername() {
        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01ABC")!,
            textExcerpt: "Hello world",
            username: "alice"
        )
        XCTAssertEqual(payload.shareMessage, "Hello world — @alice in Take")
        XCTAssertEqual(payload.linkTitle, "@alice on Take")
    }
}
