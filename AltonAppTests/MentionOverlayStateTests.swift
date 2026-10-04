import XCTest
@testable import AltonApp

final class MentionOverlayStateTests: XCTestCase {
    func testOverlayVisibleOnlyWhenCandidatesNonEmpty() {
        var state = MentionOverlayState(candidates: [])
        XCTAssertFalse(state.isVisible)
        state.candidates = [MentionCandidate.fixture(name: "alice"), MentionCandidate.fixture(name: "bob")]
        XCTAssertTrue(state.isVisible)
        state.candidates = []
        XCTAssertFalse(state.isVisible)
    }

    func testStateInitializesWithDefaultEmptyCandidates() {
        let state = MentionOverlayState()
        XCTAssertFalse(state.isVisible)
        XCTAssertTrue(state.candidates.isEmpty)
    }

    func testStateWithSingleCandidateIsVisible() {
        let state = MentionOverlayState(candidates: [MentionCandidate.fixture(name: "carol")])
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.candidates.count, 1)
        XCTAssertEqual(state.candidates.first?.username, "carol")
    }

    func testStateCandidatesCanBeReplaced() {
        var state = MentionOverlayState(candidates: [MentionCandidate.fixture(name: "carol")])
        XCTAssertTrue(state.isVisible)
        state.candidates = []
        XCTAssertFalse(state.isVisible)
        state.candidates = [MentionCandidate.fixture(name: "dave")]
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.candidates.first?.displayName, "dave")
    }

    func testFixtureConstructsValidMentionCandidate() {
        let candidate = MentionCandidate.fixture(name: "alice")
        XCTAssertEqual(candidate.id, "alice")
        XCTAssertEqual(candidate.username, "alice")
        XCTAssertEqual(candidate.displayName, "alice")
        XCTAssertNil(candidate.avatarURL)
        XCTAssertFalse(candidate.isFollowing)
    }

    func testOverlayHeightCalculations() {
        XCTAssertEqual(MentionOverlayView.overlayHeight(candidateCount: 0), 0)
        XCTAssertEqual(MentionOverlayView.overlayHeight(candidateCount: 1), 44)
        XCTAssertEqual(MentionOverlayView.overlayHeight(candidateCount: 2), 88)
        XCTAssertEqual(MentionOverlayView.overlayHeight(candidateCount: 4), 176)
        XCTAssertEqual(MentionOverlayView.overlayHeight(candidateCount: 5), 176)
        XCTAssertEqual(MentionOverlayView.overlayHeight(candidateCount: 10), 176)
    }
}

extension MentionCandidate {
    static func fixture(name: String) -> MentionCandidate {
        MentionCandidate(
            id: name.lowercased(),
            username: name,
            displayName: name,
            avatarURL: nil,
            isFollowing: false
        )
    }
}
