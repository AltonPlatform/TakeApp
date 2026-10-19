import XCTest
@testable import AltonApp

final class GrokPanelMotionTests: XCTestCase {
    func testDismissConstantsStayInsideSpec() {
        XCTAssertGreaterThanOrEqual(GrokPanelMotion.dismissedScale, 0.96)
        XCTAssertLessThanOrEqual(GrokPanelMotion.dismissedScale, 0.98)
        XCTAssertGreaterThanOrEqual(GrokPanelMotion.dismissedTranslationY, 8)
        XCTAssertLessThanOrEqual(GrokPanelMotion.dismissedTranslationY, 14)
        XCTAssertGreaterThanOrEqual(GrokPanelMotion.presentDuration, 0.32)
        XCTAssertLessThanOrEqual(GrokPanelMotion.presentDuration, 0.38)
        XCTAssertGreaterThanOrEqual(GrokPanelMotion.dismissDuration, 0.32)
        XCTAssertLessThanOrEqual(GrokPanelMotion.dismissDuration, 0.38)
        XCTAssertGreaterThanOrEqual(GrokPanelMotion.dimmingAlpha, 0.2)
        XCTAssertLessThanOrEqual(GrokPanelMotion.dimmingAlpha, 0.3)
        XCTAssertGreaterThanOrEqual(GrokPanelMotion.springDamping, 0.85)
        XCTAssertLessThanOrEqual(GrokPanelMotion.springDamping, 0.9)
    }

    func testInteractiveDistanceClampsToComfortableThumbTravel() {
        // 400 * 0.58 = 232 → clamped to 320
        XCTAssertEqual(GrokPanelMotion.interactiveDistance(panelHeight: 400), 320, accuracy: 0.001)
        // 600 * 0.58 = 348 → inside the range
        XCTAssertEqual(GrokPanelMotion.interactiveDistance(panelHeight: 600), 348, accuracy: 0.001)
        // 1200 * 0.58 = 696 → clamped to 400
        XCTAssertEqual(GrokPanelMotion.interactiveDistance(panelHeight: 1200), 400, accuracy: 0.001)
    }

    func testInteractiveProgressClampsAndStaysLinear() {
        let distance = GrokPanelMotion.interactiveDistance(panelHeight: 600)
        XCTAssertEqual(
            GrokPanelMotion.interactiveProgress(translationY: -20, panelHeight: 600),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            GrokPanelMotion.interactiveProgress(translationY: 0, panelHeight: 600),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            GrokPanelMotion.interactiveProgress(translationY: distance * 0.5, panelHeight: 600),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            GrokPanelMotion.interactiveProgress(translationY: 1_000, panelHeight: 600),
            1,
            accuracy: 0.0001
        )
    }

    func testBlurTimelineOrder() {
        XCTAssertLessThanOrEqual(GrokPanelMotion.blurStyleBoostEnd, GrokPanelMotion.blurRampEnd)
        XCTAssertLessThanOrEqual(GrokPanelMotion.blurRampEnd, GrokPanelMotion.blurFadeStart)
        XCTAssertLessThan(GrokPanelMotion.blurFadeStart, 1)
        XCTAssertLessThan(GrokPanelMotion.restingBlurAlpha, GrokPanelMotion.peakBlurAlpha)
    }

    func testShouldFinishOnDistanceOrFlickButNotOnUpwardSwipe() {
        XCTAssertTrue(GrokPanelMotion.shouldFinish(progress: 0.52, velocityY: 0))
        XCTAssertFalse(GrokPanelMotion.shouldFinish(progress: 0.51, velocityY: 0))
        XCTAssertTrue(GrokPanelMotion.shouldFinish(progress: 0.1, velocityY: 1_400))
        XCTAssertFalse(GrokPanelMotion.shouldFinish(progress: 0.1, velocityY: 1_399))
        XCTAssertFalse(GrokPanelMotion.shouldFinish(progress: 0.9, velocityY: -120))
    }

    func testRubberBandIsMonotonicAndBounded() {
        XCTAssertEqual(GrokPanelMotion.rubberBand(0), 0, accuracy: 0.0001)
        let small = GrokPanelMotion.rubberBand(10)
        let mid = GrokPanelMotion.rubberBand(40)
        let large = GrokPanelMotion.rubberBand(100)
        XCTAssertGreaterThan(mid, small)
        XCTAssertGreaterThan(large, mid)
        XCTAssertLessThan(GrokPanelMotion.rubberBand(10_000), 80)
        XCTAssertEqual(GrokPanelMotion.rubberBand(-40), -mid, accuracy: 0.0001)
    }
}
