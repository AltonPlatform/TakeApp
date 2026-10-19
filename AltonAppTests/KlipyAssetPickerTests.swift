import XCTest
@testable import AltonApp

final class KlipyAssetPickerTests: XCTestCase {
    func testPrefersHDWebPUnder4MB() {
        let picked = KlipyAssetPicker.preferred(from: [
            .init(url: "https://cdn.example/hd.webp", size: 900_000, width: 720, height: 720, contentType: "image/webp"),
            .init(url: "https://cdn.example/md.webp", size: 400_000, width: 480, height: 480, contentType: "image/webp"),
            .init(url: "https://cdn.example/md.gif", size: 1_200_000, width: 480, height: 480, contentType: "image/gif"),
            .init(url: "https://cdn.example/sm.webp", size: 150_000, width: 360, height: 360, contentType: "image/webp"),
            .init(url: "https://cdn.example/xs.webp", size: 40_000, width: 220, height: 220, contentType: "image/webp"),
        ])
        XCTAssertEqual(picked?.url.absoluteString, "https://cdn.example/hd.webp")
        XCTAssertEqual(picked?.contentType, "image/webp")
        XCTAssertEqual(picked?.size, 900_000)
    }

    func testFallsBackToMDWhenHDIsOver4MB() {
        let picked = KlipyAssetPicker.preferred(from: [
            .init(url: "https://cdn.example/hd.webp", size: 5_000_000, width: 720, height: 720, contentType: "image/webp"),
            .init(url: "https://cdn.example/md.webp", size: 400_000, width: 480, height: 480, contentType: "image/webp"),
            .init(url: "https://cdn.example/sm.webp", size: 150_000, width: 360, height: 360, contentType: "image/webp"),
        ])
        XCTAssertEqual(picked?.url.absoluteString, "https://cdn.example/md.webp")
        XCTAssertEqual(picked?.contentType, "image/webp")
    }

    func testFallsBackToSMWhenMDIsOver4MB() {
        let picked = KlipyAssetPicker.preferred(from: [
            .init(url: "https://cdn.example/md.webp", size: 5_000_000, width: 480, height: 480, contentType: "image/webp"),
            .init(url: "https://cdn.example/md.gif", size: 6_000_000, width: 480, height: 480, contentType: "image/gif"),
            .init(url: "https://cdn.example/sm.webp", size: 800_000, width: 360, height: 360, contentType: "image/webp"),
            .init(url: "https://cdn.example/xs.webp", size: 40_000, width: 220, height: 220, contentType: "image/webp"),
        ])
        XCTAssertEqual(picked?.url.absoluteString, "https://cdn.example/sm.webp")
        XCTAssertEqual(picked?.contentType, "image/webp")
    }

    func testFallsBackToGIFWhenWebPIsOversized() {
        let picked = KlipyAssetPicker.preferred(from: [
            .init(url: "https://cdn.example/md.webp", size: 200_000, width: 4000, height: 4000, contentType: "image/webp"),
            .init(url: "https://cdn.example/sm.webp", size: 120_000, width: 3000, height: 3000, contentType: "image/webp"),
            .init(url: "https://cdn.example/xs.webp", size: 80_000, width: 2500, height: 2500, contentType: "image/webp"),
            .init(url: "https://cdn.example/sm.gif", size: 250_000, width: 360, height: 360, contentType: "image/gif"),
            .init(url: "https://cdn.example/xs.gif", size: 90_000, width: 220, height: 220, contentType: "image/gif"),
        ])
        XCTAssertEqual(picked?.url.absoluteString, "https://cdn.example/sm.gif")
        XCTAssertEqual(picked?.contentType, "image/gif")
    }

    func testKeepsMDWhenSizeIsUnknown() {
        let picked = KlipyAssetPicker.preferred(from: [
            .init(url: "https://cdn.example/md.webp", size: 0, width: 480, height: 480, contentType: "image/webp"),
            .init(url: "https://cdn.example/sm.webp", size: 150_000, width: 360, height: 360, contentType: "image/webp"),
        ])
        XCTAssertEqual(picked?.url.absoluteString, "https://cdn.example/md.webp")
    }

    func testPreviewPrefersSmallKnownSizeWhenDownloadSizeUnknown() {
        let candidates: [KlipyAssetPicker.Candidate] = [
            .init(url: "https://cdn.example/md.webp", size: 0, width: 480, height: 480, contentType: "image/webp"),
            .init(url: "https://cdn.example/sm.webp", size: 150_000, width: 360, height: 360, contentType: "image/webp"),
            .init(url: "https://cdn.example/xs.webp", size: 40_000, width: 220, height: 220, contentType: "image/webp"),
        ]
        XCTAssertEqual(
            KlipyAssetPicker.preferred(from: candidates)?.url.absoluteString,
            "https://cdn.example/md.webp"
        )
        XCTAssertEqual(
            KlipyAssetPicker.preview(from: candidates)?.url.absoluteString,
            "https://cdn.example/sm.webp"
        )
    }

    func testGridStillUsesJPEGAndDownloadStaysAnimated() {
        let candidates: [KlipyAssetPicker.Candidate] = [
            .init(url: "https://cdn.example/sm.jpg", size: 8_000, width: 220, height: 220, contentType: "image/jpeg"),
            .init(url: "https://cdn.example/xs.jpg", size: 2_000, width: 90, height: 90, contentType: "image/jpeg"),
            .init(url: "https://cdn.example/md.webp", size: 200_000, width: 480, height: 480, contentType: "image/webp"),
            .init(url: "https://cdn.example/xs.webp", size: 20_000, width: 90, height: 90, contentType: "image/webp"),
        ]
        XCTAssertEqual(
            KlipyAssetPicker.gridStill(from: candidates)?.url.absoluteString,
            "https://cdn.example/sm.jpg"
        )
        XCTAssertEqual(KlipyAssetPicker.preferred(from: candidates)?.contentType, "image/webp")
        XCTAssertEqual(
            KlipyAssetPicker.gridThumb(from: candidates)?.url.absoluteString,
            "https://cdn.example/xs.webp"
        )
    }

    func testGridVideoPrefersLightCellSizedMP4AndStaysOutOfDownload() {
        let candidates: [KlipyAssetPicker.Candidate] = [
            .init(url: "https://cdn.example/sm.jpg", size: 8_000, width: 220, height: 220, contentType: "image/jpeg"),
            .init(url: "https://cdn.example/xs.mp4", size: 30_000, width: 150, height: 150, contentType: "video/mp4"),
            .init(url: "https://cdn.example/sm.mp4", size: 90_000, width: 320, height: 320, contentType: "video/mp4"),
            .init(url: "https://cdn.example/sm-light.mp4", size: 40_000, width: 300, height: 300, contentType: "video/mp4"),
            .init(url: "https://cdn.example/md.mp4", size: 70_000, width: 480, height: 480, contentType: "video/mp4"),
            .init(url: "https://cdn.example/hd.mp4", size: 900_000, width: 720, height: 720, contentType: "video/mp4"),
            .init(url: "https://cdn.example/md.webp", size: 200_000, width: 480, height: 480, contentType: "image/webp"),
        ]
        // Grid cells are ~140pt; skip heavy md/hd and pick the lightest ≥200px.
        XCTAssertEqual(
            KlipyAssetPicker.gridVideo(from: candidates)?.url.absoluteString,
            "https://cdn.example/sm-light.mp4"
        )
        XCTAssertEqual(KlipyAssetPicker.preferred(from: candidates)?.contentType, "image/webp")
        XCTAssertEqual(
            KlipyAssetPicker.preferred(from: candidates)?.url.absoluteString,
            "https://cdn.example/md.webp"
        )
        XCTAssertNotEqual(
            KlipyAssetPicker.gridThumb(from: candidates)?.contentType,
            "video/mp4"
        )
        XCTAssertNotEqual(
            KlipyAssetPicker.preview(from: candidates)?.contentType,
            "video/mp4"
        )
    }

    func testGridVideoFallsBackToLargestUnder400WhenNoneIdeal() {
        let candidates: [KlipyAssetPicker.Candidate] = [
            .init(url: "https://cdn.example/xs.mp4", size: 20_000, width: 150, height: 150, contentType: "video/mp4"),
            .init(url: "https://cdn.example/tiny.mp4", size: 10_000, width: 120, height: 120, contentType: "video/mp4"),
        ]
        XCTAssertEqual(
            KlipyAssetPicker.gridVideo(from: candidates)?.url.absoluteString,
            "https://cdn.example/xs.mp4"
        )
    }

    func testShareURLEncodesSlugPathCharacters() {
        let url = KlipyShareURL.make(apiKey: "key", slug: "funny cat/extra")
        XCTAssertEqual(
            url?.absoluteString,
            "https://api.klipy.com/api/v1/key/gifs/share/funny%20cat%2Fextra"
        )
    }

    func testAttachmentPlaysWebPAsAnimation() {
        let webp = PostAttachment(
            data: Data([0x52, 0x49, 0x46, 0x46]),
            contentType: "image/webp",
            filename: "klipy-123.webp"
        )
        XCTAssertTrue(webp.playsAsAnimation)
        XCTAssertFalse(webp.isGIF)

        let photo = PostAttachment(
            data: Data(),
            contentType: "image/jpeg",
            filename: "comment.jpg"
        )
        XCTAssertFalse(photo.playsAsAnimation)
    }
}
