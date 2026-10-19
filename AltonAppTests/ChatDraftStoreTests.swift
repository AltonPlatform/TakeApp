import XCTest
@testable import AltonApp

final class ChatDraftStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ChatDraftStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoad() {
        let store = ChatDraftStore(userID: "u1", defaults: defaults)
        store.save(conversationID: "c1", text: "hello draft")
        XCTAssertEqual(store.load(conversationID: "c1"), "hello draft")
    }

    func testEmptyTextRemovesEntry() {
        let store = ChatDraftStore(userID: "u1", defaults: defaults)
        store.save(conversationID: "c1", text: "keep me")
        store.save(conversationID: "c1", text: "   \n")
        XCTAssertNil(store.load(conversationID: "c1"))
    }

    func testClearRemovesEntry() {
        let store = ChatDraftStore(userID: "u1", defaults: defaults)
        store.save(conversationID: "c1", text: "bye")
        store.clear(conversationID: "c1")
        XCTAssertNil(store.load(conversationID: "c1"))
    }

    func testClearAllRemovesAccountDrafts() {
        let store = ChatDraftStore(userID: "u1", defaults: defaults)
        store.save(conversationID: "c1", text: "one")
        store.save(conversationID: "c2", text: "two")
        store.clearAll()
        XCTAssertNil(store.load(conversationID: "c1"))
        XCTAssertNil(store.load(conversationID: "c2"))
        XCTAssertNil(defaults.data(forKey: "dm.drafts.u1"))
    }

    func testSeparateKeysPerUser() {
        let a = ChatDraftStore(userID: "alice", defaults: defaults)
        let b = ChatDraftStore(userID: "bob", defaults: defaults)
        a.save(conversationID: "c1", text: "from alice")
        b.save(conversationID: "c1", text: "from bob")
        XCTAssertEqual(a.load(conversationID: "c1"), "from alice")
        XCTAssertEqual(b.load(conversationID: "c1"), "from bob")
    }

    func testEvictsOldestBeyondMaxCount() {
        let store = ChatDraftStore(userID: "u1", defaults: defaults)
        // Stay well inside the 30-day TTL so pruneExpired doesn't wipe the set.
        let base = Date().addingTimeInterval(-3_600)
        for i in 0..<ChatDraftStore.maxDraftCount {
            store.save(
                conversationID: "c\(i)",
                text: "draft \(i)",
                updatedAt: base.addingTimeInterval(TimeInterval(i))
            )
        }
        store.save(
            conversationID: "newest",
            text: "overflow",
            updatedAt: base.addingTimeInterval(TimeInterval(ChatDraftStore.maxDraftCount + 1))
        )
        XCTAssertNil(store.load(conversationID: "c0"))
        XCTAssertEqual(store.load(conversationID: "c1"), "draft 1")
        XCTAssertEqual(store.load(conversationID: "newest"), "overflow")
    }

    func testPrunesExpiredOnLoad() {
        let store = ChatDraftStore(userID: "u1", defaults: defaults)
        let expired = Calendar.current.date(
            byAdding: .day,
            value: -(ChatDraftStore.maxAgeDays + 1),
            to: Date()
        )!
        store.save(conversationID: "old", text: "stale", updatedAt: expired)
        store.save(conversationID: "fresh", text: "alive", updatedAt: Date())
        XCTAssertNil(store.load(conversationID: "old"))
        XCTAssertEqual(store.load(conversationID: "fresh"), "alive")
    }
}
