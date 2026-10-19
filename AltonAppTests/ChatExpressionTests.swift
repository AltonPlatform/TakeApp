import XCTest
@testable import AltonApp

final class ChatExpressionTests: XCTestCase {
    func testDecodesStickerKind() throws {
        let json = """
        {
          "id": "m1",
          "conversation_id": "c1",
          "seq": 4,
          "sender_id": "u1",
          "kind": "sticker",
          "client_msg_id": "client",
          "created_at": "2026-10-18T00:00:00Z",
          "payload": { "sticker_id": "01HZSTICKER", "pack_id": "pack", "emoji_hint": "😀" }
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(DMMessageDTO.self, from: json)
        let message = dto.toDomain()
        XCTAssertEqual(message.kind, .sticker)
        XCTAssertEqual(message.stickerID, "01HZSTICKER")
    }

    func testEmojiCatalogCategories() {
        let sections = EmojiCatalog.build()
        XCTAssertFalse(sections.isEmpty)
        for section in sections {
            XCTAssertFalse(section.symbols.isEmpty, section.title)
        }
        XCTAssertTrue(sections.contains { $0.id == "flags" })
    }
}
