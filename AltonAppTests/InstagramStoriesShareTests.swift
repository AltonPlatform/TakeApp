import XCTest
@testable import AltonApp

final class InstagramStoriesShareTests: XCTestCase {
    func testMetaAppIDComesFromConfigNotHardcodedCaller() {
        XCTAssertFalse(MetaAppConfig.appID.isEmpty)
        XCTAssertTrue(MetaAppConfig.appID.allSatisfy(\.isNumber))
    }

    func testShareCardQRGeneration() {
        let url = URL(string: "https://alton.social/p/01HABCDEFGHJKMNPQRSTVWXYZ0")!
        let qr = PostShareCardRenderer.qrCode(for: url.absoluteString, dimension: 128)
        XCTAssertNotNil(qr)
        XCTAssertEqual(qr?.size.width ?? 0, 128, accuracy: 1)
    }

    @MainActor
    func testShareCardRendersImage() {
        let payload = PostSharePayload(
            url: URL(string: "https://alton.social/p/01HABCDEFGHJKMNPQRSTVWXYZ0")!,
            textExcerpt: "Hello from Take",
            username: "alice"
        )
        let image = PostShareCardRenderer.render(payload: payload)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width ?? 0, 1080, accuracy: 1)
        XCTAssertEqual(image?.size.height ?? 0, 1920, accuracy: 1)
    }

    func testShareChannelMapsInstagram() {
        let type = UIActivity.ActivityType("com.burbn.instagram.shareextension")
        XCTAssertEqual(ShareChannelMapper.channel(for: type), "instagram")
    }
}
