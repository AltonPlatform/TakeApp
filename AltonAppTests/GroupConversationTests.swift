import XCTest
@testable import AltonApp

final class GroupConversationTests: XCTestCase {
    func testConversationDTODecodesGroupFields() throws {
        let json = """
        {
          "id": "01GROUP",
          "kind": "group",
          "title": "Weekend",
          "visibility": "private",
          "group_avatar_url": "https://cdn.example/groups/01GROUP/avatar.jpg",
          "member_count": 2,
          "members": [
            {
              "user_id": "owner",
              "username": "ada",
              "display_name": "Ada",
              "role": "owner"
            },
            {
              "user_id": "admin",
              "username": "bea",
              "display_name": "Bea",
              "role": "admin",
              "rights": ["change_info", "ban_members"]
            }
          ]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(DMConversationDTO.self, from: json)
        let conversation = dto.toDomain()
        XCTAssertEqual(conversation.visibility, "private")
        XCTAssertEqual(conversation.groupAvatarURL?.absoluteString, "https://cdn.example/groups/01GROUP/avatar.jpg")
        XCTAssertEqual(conversation.members.first?.role, "owner")
        XCTAssertTrue(conversation.members.first?.canChangeInfo == true)
        let admin = conversation.members[1]
        XCTAssertEqual(admin.rights, Set(["ban_members", "change_info"]))
        XCTAssertTrue(admin.canBanMembers)
        XCTAssertFalse(admin.canAssignAdmins)
    }

    func testConversationUpdatedMergesTitleAvatarAndMembers() {
        var conversation = DMConversation(
            id: "01GROUP",
            kind: "group",
            peerUserID: "",
            peerUsername: "",
            peerDisplayName: "",
            peerAvatarURL: nil,
            folder: "primary",
            memberState: "active",
            lastSeq: 4,
            lastReadSeq: 4,
            peerLastReadSeq: 0,
            lastMessageID: "m",
            previewText: "hi",
            previewKind: "text",
            updatedAt: "",
            unreadCount: 0,
            title: "Old",
            memberCount: 1,
            members: [],
            groupAvatarURL: nil,
            visibility: "private"
        )
        let update = RealtimeClient.groupUpdate(from: [
            "conversation_id": "01GROUP",
            "title": "Renamed",
            "group_avatar_url": "https://cdn.example/a.jpg",
            "visibility": "private",
            "member_count": 2,
            "members": [
                [
                    "user_id": "u1",
                    "username": "ada",
                    "display_name": "Ada",
                    "role": "owner"
                ],
                [
                    "user_id": "u2",
                    "username": "bea",
                    "display_name": "Bea",
                    "role": "admin",
                    "rights": ["delete_messages", "assign_admins"]
                ]
            ]
        ])
        conversation = conversation.applying(update)
        XCTAssertEqual(conversation.title, "Renamed")
        XCTAssertEqual(conversation.displayTitle, "Renamed")
        XCTAssertEqual(conversation.memberCount, 2)
        XCTAssertEqual(conversation.members.map(\.role), ["owner", "admin"])
        XCTAssertEqual(conversation.members[1].rights, Set(["assign_admins", "delete_messages"]))
        XCTAssertTrue(conversation.members[1].canDeleteMessages)
        XCTAssertEqual(conversation.groupAvatarURL?.absoluteString, "https://cdn.example/a.jpg")
        XCTAssertEqual(conversation.lastSeq, 4)
    }
}
