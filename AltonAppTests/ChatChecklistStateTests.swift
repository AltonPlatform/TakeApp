import XCTest
@testable import AltonApp

final class ChatChecklistStateTests: XCTestCase {
    private func checklist(mark: Bool, add: Bool) -> DMChecklist {
        DMChecklist(
            title: "List",
            items: [DMChecklistItem(id: 1, text: "A"), DMChecklistItem(id: 2, text: "B")],
            nextID: 3,
            othersCanMark: mark,
            othersCanAdd: add
        )
    }

    func testAuthorCanAlwaysMarkAndAdd() {
        let locked = checklist(mark: false, add: false)
        XCTAssertTrue(ChatChecklistState.canMark(locked, isAuthor: true))
        XCTAssertTrue(ChatChecklistState.canAdd(locked, isAuthor: true))
        XCTAssertFalse(ChatChecklistState.canMark(locked, isAuthor: false))
        XCTAssertFalse(ChatChecklistState.canAdd(locked, isAuthor: false))
    }

    func testPeerRightsFollowFlags() {
        let open = checklist(mark: true, add: true)
        XCTAssertTrue(ChatChecklistState.canMark(open, isAuthor: false))
        XCTAssertTrue(ChatChecklistState.canAdd(open, isAuthor: false))
    }

    func testToggleAddsAndRemovesOneMarkPerItem() {
        let marked = ChatChecklistState.toggled(marks: [], itemID: 2, userID: "u1", done: true)
        XCTAssertEqual(marked, [DMChecklistMark(itemID: 2, userID: "u1")])
        let cleared = ChatChecklistState.toggled(marks: marked, itemID: 2, userID: "u2", done: false)
        XCTAssertTrue(cleared.isEmpty)
    }

    func testToggleReplacesTheMarkerForTheSameItem() {
        let first = ChatChecklistState.toggled(marks: [], itemID: 1, userID: "u1", done: true)
        let replaced = ChatChecklistState.toggled(marks: first, itemID: 1, userID: "u2", done: true)
        XCTAssertEqual(replaced, [DMChecklistMark(itemID: 1, userID: "u2")])
    }
}

final class ChatPollStateTests: XCTestCase {
    private func poll(quiz: Bool = false, closed: Bool = false, multiple: Bool = false) -> DMPoll {
        DMPoll(
            question: "Q",
            options: [DMPollOption(id: 1, text: "A"), DMPollOption(id: 2, text: "B")],
            nextID: 3,
            anonymous: true,
            multiple: multiple,
            quiz: quiz,
            othersCanAdd: !quiz,
            closed: closed,
            correctOptionID: quiz ? 2 : nil,
            explanation: nil
        )
    }

    func testPercentagesSumToOneHundred() {
        let even = ChatPollState.percentages(counts: [1: 1, 2: 1])
        XCTAssertEqual(even[1], 50)
        XCTAssertEqual(even[2], 50)
        let uneven = ChatPollState.percentages(counts: [1: 1, 2: 2])
        XCTAssertEqual((uneven[1] ?? 0) + (uneven[2] ?? 0), 100)
        XCTAssertEqual(ChatPollState.percentages(counts: [1: 0, 2: 0]), [1: 0, 2: 0])
    }

    func testQuizCannotChangeOrAdd() {
        let quiz = poll(quiz: true)
        XCTAssertFalse(ChatPollState.canRetract(quiz, hasVoted: true))
        XCTAssertFalse(ChatPollState.canAddOption(quiz, isAuthor: true))
        XCTAssertFalse(ChatPollState.canVote(quiz, hasVoted: true, isPending: false))
        XCTAssertTrue(ChatPollState.canVote(quiz, hasVoted: false, isPending: false))
        XCTAssertTrue(ChatPollState.isRevealed(quiz, hasVoted: true))
        XCTAssertFalse(ChatPollState.isRevealed(quiz, hasVoted: false))
        XCTAssertTrue(ChatPollState.isRevealed(poll(closed: true), hasVoted: false))
    }

    func testOptimisticVoteAndRetract() {
        let voted = ChatPollState.optimisticVote(
            votes: [],
            tallies: [],
            totalVoters: 0,
            userID: "me",
            optionIDs: [1]
        )
        XCTAssertEqual(voted.totalVoters, 1)
        XCTAssertEqual(voted.tallies, [DMPollTally(optionID: 1, count: 1)])
        let cleared = ChatPollState.optimisticVote(
            votes: voted.votes,
            tallies: voted.tallies,
            totalVoters: voted.totalVoters,
            userID: "me",
            optionIDs: []
        )
        XCTAssertEqual(cleared.totalVoters, 0)
        XCTAssertTrue(cleared.votes.isEmpty)
        XCTAssertTrue(cleared.tallies.isEmpty)
    }
}
