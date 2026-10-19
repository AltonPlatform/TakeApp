import XCTest
@testable import AltonApp

final class DMPayloadParsingTests: XCTestCase {
    func testDecodesLocationAndChecklistMessages() throws {
        let json = """
        {
          "id": "m1",
          "conversation_id": "c1",
          "seq": 4,
          "sender_id": "u1",
          "kind": "location",
          "body": "",
          "client_msg_id": "cli",
          "created_at": "2026-10-16T00:00:00Z",
          "payload": {"lat": 50.45, "lng": 30.52, "name": "Kyiv", "address": "Center"},
          "checklist_marks": []
        }
        """.data(using: .utf8)!
        let location = try JSONDecoder().decode(DMMessageDTO.self, from: json).toDomain()
        XCTAssertEqual(location.kind, .location)
        XCTAssertEqual(location.location?.lat, 50.45)
        XCTAssertEqual(location.location?.name, "Kyiv")
        XCTAssertNil(location.checklist)

        let checklistJSON = """
        {
          "id": "m2",
          "conversation_id": "c1",
          "seq": 5,
          "sender_id": "u1",
          "kind": "checklist",
          "payload": {
            "title": "Shop",
            "items": [{"id": 1, "text": "Milk"}, {"id": 2, "text": "Bread"}],
            "next_id": 3,
            "others_can_mark": true,
            "others_can_add": false
          },
          "checklist_marks": [{"item_id": 1, "user_id": "u2"}]
        }
        """.data(using: .utf8)!
        let checklist = try JSONDecoder().decode(DMMessageDTO.self, from: checklistJSON).toDomain()
        XCTAssertEqual(checklist.checklist?.items.map(\.text), ["Milk", "Bread"])
        XCTAssertEqual(checklist.checklist?.nextID, 3)
        XCTAssertEqual(checklist.checklistMarks, [DMChecklistMark(itemID: 1, userID: "u2")])
    }

    func testRealtimeDictionaryParsing() {
        let location = DMPayloadCodec.location(from: ["lat": 1.5, "lng": NSNumber(value: 2), "name": "  "])
        XCTAssertEqual(location?.lat, 1.5)
        XCTAssertEqual(location?.lng, 2)
        XCTAssertNil(location?.name)

        let checklist = DMPayloadCodec.checklist(from: [
            "title": "Pack",
            "items": [["id": 1, "text": "Cable"]],
            "next_id": 2,
            "others_can_mark": false,
            "others_can_add": true,
        ])
        XCTAssertEqual(checklist?.items.first?.text, "Cable")
        XCTAssertEqual(checklist?.othersCanAdd, true)
        XCTAssertEqual(checklist?.othersCanMark, false)

        let marks = DMPayloadCodec.marks(from: [["item_id": 2, "user_id": "u9"]])
        XCTAssertEqual(marks, [DMChecklistMark(itemID: 2, userID: "u9")])
    }

    func testDecodesPollMessage() throws {
        let json = """
        {
          "id": "m3",
          "conversation_id": "c1",
          "seq": 6,
          "sender_id": "u1",
          "kind": "poll",
          "payload": {
            "question": "Lunch?",
            "options": [{"id": 1, "text": "Soup"}, {"id": 2, "text": "Salad"}],
            "next_id": 3,
            "anonymous": false,
            "multiple": false,
            "quiz": false,
            "others_can_add": true,
            "closed": false
          },
          "poll_votes": [{"option_id": 1, "user_id": "u2"}],
          "poll_tallies": [{"option_id": 1, "count": 1}],
          "poll_total_voters": 1
        }
        """.data(using: .utf8)!
        let message = try JSONDecoder().decode(DMMessageDTO.self, from: json).toDomain()
        XCTAssertEqual(message.poll?.question, "Lunch?")
        XCTAssertEqual(message.poll?.options.map(\.text), ["Soup", "Salad"])
        XCTAssertEqual(message.poll?.anonymous, false)
        XCTAssertEqual(message.pollVotes, [DMPollVote(optionID: 1, userID: "u2")])
        XCTAssertEqual(message.pollTallies, [DMPollTally(optionID: 1, count: 1)])
        XCTAssertEqual(message.pollTotalVoters, 1)

        let parsed = DMPayloadCodec.poll(from: [
            "question": "2+2",
            "options": [["id": 1, "text": "3"], ["id": 2, "text": "4"]],
            "quiz": true,
            "correct_option_id": 2,
            "explanation": "Four",
        ])
        XCTAssertEqual(parsed?.quiz, true)
        XCTAssertEqual(parsed?.correctOptionID, 2)
        XCTAssertEqual(parsed?.explanation, "Four")
    }
}
