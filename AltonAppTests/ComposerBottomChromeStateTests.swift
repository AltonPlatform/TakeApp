import XCTest
@testable import AltonApp

final class ComposerBottomChromeStateTests: XCTestCase {
    func testCanPublishFalseWhenSubmittingOrEmpty() {
        XCTAssertFalse(ComposerPublishState(canSubmitContent: false, isSubmitting: false).canPublish)
        XCTAssertFalse(ComposerPublishState(canSubmitContent: true, isSubmitting: true).canPublish)
        XCTAssertTrue(ComposerPublishState(canSubmitContent: true, isSubmitting: false).canPublish)
    }
}
