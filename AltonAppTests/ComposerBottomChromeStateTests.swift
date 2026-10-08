import XCTest
@testable import AltonApp

final class ComposerBottomChromeStateTests: XCTestCase {
    func testCanPublishFalseWhenSubmittingOrEmpty() {
        XCTAssertFalse(ComposerPublishState(canSubmitContent: false, isSubmitting: false).canPublish)
        XCTAssertFalse(ComposerPublishState(canSubmitContent: true, isSubmitting: true).canPublish)
        XCTAssertTrue(ComposerPublishState(canSubmitContent: true, isSubmitting: false).canPublish)
    }

    func testIsDimmedOnlyWhenCannotSubmitAndNotSubmitting() {
        XCTAssertFalse(ComposerPublishState(canSubmitContent: true, isSubmitting: false).isDimmed)
        XCTAssertTrue(ComposerPublishState(canSubmitContent: false, isSubmitting: false).isDimmed)
        // Spinner shows while submitting, so the pill is not dimmed.
        XCTAssertFalse(ComposerPublishState(canSubmitContent: false, isSubmitting: true).isDimmed)
    }

    func testMeterProgressIsClampedAndGuardsZeroLimit() {
        XCTAssertEqual(ComposerBottomChrome.meterProgress(used: 0, limit: 500), 0, accuracy: 0.0001)
        XCTAssertEqual(ComposerBottomChrome.meterProgress(used: 250, limit: 500), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ComposerBottomChrome.meterProgress(used: 500, limit: 500), 1, accuracy: 0.0001)
        XCTAssertEqual(ComposerBottomChrome.meterProgress(used: 750, limit: 500), 1, accuracy: 0.0001)
        XCTAssertEqual(ComposerBottomChrome.meterProgress(used: 10, limit: 0), 0, accuracy: 0.0001)
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
