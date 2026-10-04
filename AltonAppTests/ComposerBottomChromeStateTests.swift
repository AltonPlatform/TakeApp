import XCTest
@testable import AltonApp

final class ComposerBottomChromeStateTests: XCTestCase {
    func testCanPublishFalseWhenSubmittingOrEmpty() {
        XCTAssertFalse(ComposerPublishState(canSubmitContent: false, isSubmitting: false).canPublish)
        XCTAssertFalse(ComposerPublishState(canSubmitContent: true, isSubmitting: true).canPublish)
        XCTAssertTrue(ComposerPublishState(canSubmitContent: true, isSubmitting: false).canPublish)
    }

    func testFormatToggleFlipsShowFormatTools() {
        var state = ComposerChromeState(showFormatTools: false)
        state.toggleFormat()
        XCTAssertTrue(state.showFormatTools)
        state.toggleFormat()
        XCTAssertFalse(state.showFormatTools)
    }

    func testEveryFormatActionMapsToIconWithAccessibilityLabel() {
        for action in RichTextFormatAction.allCases {
            XCTAssertFalse(ComposerIcon(action).accessibilityLabel.isEmpty, "\(action)")
        }
        XCTAssertEqual(Set(ComposerIcon.allCases.map(\.accessibilityLabel)).count, ComposerIcon.allCases.count)
    }
}
