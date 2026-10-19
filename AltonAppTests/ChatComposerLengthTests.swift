import XCTest
@testable import AltonApp

final class ChatComposerLengthTests: XCTestCase {
    func testAllowsNormalKeystroke() {
        XCTAssertTrue(
            ChatComposerLimits.allowsReplacement(
                currentUTF16Length: 10,
                rangeLength: 0,
                replacement: "a"
            )
        )
    }

    func testAllowsAtExactUTF16Limit() {
        XCTAssertTrue(
            ChatComposerLimits.allowsReplacement(
                currentUTF16Length: ChatComposerLimits.maxBodyLen - 1,
                rangeLength: 0,
                replacement: "x"
            )
        )
        XCTAssertTrue(
            ChatComposerLimits.allowsReplacement(
                currentUTF16Length: ChatComposerLimits.maxBodyLen,
                rangeLength: 0,
                replacement: ""
            )
        )
    }

    func testRejectsOverUTF16LimitGate() {
        XCTAssertFalse(
            ChatComposerLimits.allowsReplacement(
                currentUTF16Length: ChatComposerLimits.maxBodyLen,
                rangeLength: 0,
                replacement: "a"
            )
        )
    }

    func testReplacementWithinRangeAllowed() {
        // Replace 5 chars with 5 chars at the limit.
        XCTAssertTrue(
            ChatComposerLimits.allowsReplacement(
                currentUTF16Length: ChatComposerLimits.maxBodyLen,
                rangeLength: 5,
                replacement: "hello"
            )
        )
    }

    func testExactAllowsEmojiNearLimit() {
        // One emoji is one Character but often 2 UTF-16 units.
        let emoji = "😀"
        let prefix = String(repeating: "a", count: ChatComposerLimits.maxBodyLen - 1)
        let range = NSRange(location: prefix.utf16.count, length: 0)
        // UTF-16 gate may reject; Character count should allow (4000 chars).
        let exact = ChatComposerLimits.allowsReplacementExact(
            current: prefix,
            range: range,
            replacement: emoji
        )
        XCTAssertTrue(exact)
    }

    func testExactRejectsHugePaste() {
        let current = String(repeating: "a", count: 100)
        let paste = String(repeating: "b", count: ChatComposerLimits.maxBodyLen)
        let range = NSRange(location: 0, length: 0)
        XCTAssertFalse(
            ChatComposerLimits.allowsReplacementExact(
                current: current,
                range: range,
                replacement: paste
            )
        )
    }

    func testExactRejectsInvalidRange() {
        XCTAssertFalse(
            ChatComposerLimits.allowsReplacementExact(
                current: "hi",
                range: NSRange(location: 0, length: 10),
                replacement: "x"
            )
        )
    }

    func testHasNonWhitespaceContent() {
        XCTAssertFalse(ChatComposerLimits.hasNonWhitespaceContent(""))
        XCTAssertFalse(ChatComposerLimits.hasNonWhitespaceContent("   \n\t"))
        XCTAssertTrue(ChatComposerLimits.hasNonWhitespaceContent(" a"))
        XCTAssertTrue(ChatComposerLimits.hasNonWhitespaceContent("hello"))
    }
}
