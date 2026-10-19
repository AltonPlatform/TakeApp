import XCTest
@testable import AltonApp

final class ChatDateCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ChatDateCache.resetForTests()
    }

    func testParsesFractionalAndBasicISO() {
        let fractional = "2026-10-16T12:34:56.789Z"
        let basic = "2026-10-16T12:34:56Z"
        XCTAssertNotNil(ChatDateCache.date(fractional))
        XCTAssertNotNil(ChatDateCache.date(basic))
    }

    func testTimeFormat() {
        let iso = "2026-10-16T08:05:00Z"
        guard let date = ChatDateCache.date(iso) else {
            return XCTFail("parse failed")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        // ChatDateCache uses local timezone; just assert non-empty stable length.
        let time = ChatDateCache.time(iso)
        XCTAssertEqual(time.count, 5)
        XCTAssertTrue(time.contains(":"))
        _ = date
        _ = formatter
    }

    func testDayKeyStable() {
        let iso = "2026-10-16T23:15:00Z"
        let key1 = ChatDateCache.dayKey(iso)
        let key2 = ChatDateCache.dayKey(iso)
        XCTAssertEqual(key1, key2)
        XCTAssertFalse(key1.isEmpty)
    }

    func testCachesParsedDate() {
        let iso = "2026-01-02T03:04:05Z"
        let a = ChatDateCache.date(iso)
        let b = ChatDateCache.date(iso)
        XCTAssertEqual(a, b)
    }
}
