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

    func testTelegramURLEncodesSharePayload() {
        let shareURL = URL(string: "https://alton.social/p/01ABC")!
        let url = PostShareChannelAvailability.telegramURL(
            shareURL: shareURL,
            text: "Hello — @alice in Take"
        )
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "tg")
        XCTAssertEqual(url?.host, "msg_url")
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let pairs: [(String, String)] = (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        }
        let items = Dictionary(uniqueKeysWithValues: pairs)
        XCTAssertEqual(items["url"], shareURL.absoluteString)
        XCTAssertEqual(items["text"], "Hello — @alice in Take")
    }

    func testCopyChannelConstant() {
        // Custom share sheet reports this channel after UIPasteboard write.
        XCTAssertEqual(ShareChannelMapper.channel(for: .copyToPasteboard), "copy")
    }
}
