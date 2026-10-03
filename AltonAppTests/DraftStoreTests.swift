import XCTest
import SwiftData
@testable import AltonApp

@MainActor
final class DraftStoreTests: XCTestCase {
    private var store: DraftStore!

    override func setUp() async throws {
        store = try DraftStore(inMemory: true)
    }

    func testSaveAndFetchPreservesContentAndAttachments() throws {
        let data = Data([0x01, 0x02, 0x03])
        let id = try store.upsert(
            id: nil,
            content: "Hello **world**",
            attachments: [
                ComposerDraftAttachmentPayload(
                    data: data,
                    contentType: "image/jpeg",
                    filename: "attachment.jpg"
                )
            ]
        )
        XCTAssertNotNil(id)

        let loaded = try store.load(id: id!)
        XCTAssertEqual(loaded?.content, "Hello **world**")
        XCTAssertEqual(loaded?.attachments.count, 1)
        XCTAssertEqual(loaded?.attachments.first?.data, data)
        XCTAssertEqual(loaded?.attachments.first?.contentType, "image/jpeg")
    }

    func testUpdateTouchesUpdatedAt() throws {
        let id = try store.upsert(id: nil, content: "first", attachments: [])!
        let first = try store.fetchAll().first!
        // Ensure clock moves enough for Date comparison on some platforms.
        Thread.sleep(forTimeInterval: 0.02)
        _ = try store.upsert(id: id, content: "second", attachments: [])
        let second = try store.fetchAll().first!
        XCTAssertEqual(second.contentPreview, "second")
        XCTAssertGreaterThanOrEqual(second.updatedAt, first.updatedAt)
    }

    func testDeleteRemovesDraft() throws {
        let id = try store.upsert(id: nil, content: "gone", attachments: [])!
        try store.delete(id: id)
        XCTAssertNil(try store.load(id: id))
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testEmptyContentAndAttachmentsDeletesExisting() throws {
        let id = try store.upsert(id: nil, content: "temp", attachments: [])!
        let result = try store.upsert(id: id, content: "   ", attachments: [])
        XCTAssertNil(result)
        XCTAssertNil(try store.load(id: id))
    }

    func testEmptyUpsertDoesNotCreate() throws {
        let result = try store.upsert(id: nil, content: "", attachments: [])
        XCTAssertNil(result)
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testDeleteOlderThanRemovesStaleDrafts() throws {
        let staleID = UUID()
        // Insert via upsert then manually backdate using a second context isn't exposed;
        // use deleteOlderThan with a future cutoff after creating a draft, then verify
        // a past cutoff keeps recent drafts.
        let id = try store.upsert(id: nil, content: "recent", attachments: [])!
        try store.deleteOlderThan(Date.distantPast)
        XCTAssertNotNil(try store.load(id: id))

        try store.deleteOlderThan(Date().addingTimeInterval(60))
        XCTAssertNil(try store.load(id: id))
        _ = staleID
    }

    func testLegacyVideoDraftMigratesToShotDraft() throws {
        let id = UUID()
        let videoURL = FileManager.default.temporaryDirectory.appendingPathComponent("legacy.mp4")
        try Data([0x00]).write(to: videoURL)
        store.insertLegacyVideoDraftForTesting(
            id: id,
            content: "old take",
            videoPath: videoURL.path
        )
        store.migrateLegacyVideoDraftsForTesting()

        let loaded = try store.loadShotDraft(id: id)
        XCTAssertEqual(loaded?.content, "old take")
        XCTAssertEqual(loaded?.videoURL.path, videoURL.path)
        XCTAssertTrue(try store.fetchLegacyVideoDraftsForTesting().isEmpty)
    }

    func testEnforceDraftLimitKeepsNewest() throws {
        var ids: [UUID] = []
        for i in 0..<22 {
            Thread.sleep(forTimeInterval: 0.01)
            let id = try store.upsert(id: nil, content: "draft \(i)", attachments: [])!
            ids.append(id)
        }
        let all = try store.fetchAll()
        XCTAssertLessThanOrEqual(all.count, DraftStore.maxDraftCount)
        // Newest should remain.
        XCTAssertTrue(all.contains(where: { $0.id == ids.last }))
        // Oldest should be dropped.
        XCTAssertFalse(all.contains(where: { $0.id == ids.first }))
    }
}
