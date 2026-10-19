import SwiftUI
import XCTest
@testable import AltonApp

@MainActor
final class GrokPanelTransitionTests: XCTestCase {
    func testPresentThenDismissSettlesAndRemovesChrome() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()

        let presented = expectation(description: "presented")
        let dismissed = expectation(description: "dismissed")
        let panel = GrokPanelHostingController(rootView: Text("Panel"))
        panel.onDismiss = { dismissed.fulfill() }
        let started = Date()
        let midFlight = expectation(description: "mid-flight")
        var midOpacity: Float = -1
        root.present(panel, animated: true) {
            presented.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let panelView = (panel.presentationController as? GrokPanelPresentationController)?.panelView
            midOpacity = panelView?.layer.presentation()?.opacity ?? -1
            midFlight.fulfill()
        }

        wait(for: [midFlight], timeout: 1)
        XCTAssertGreaterThan(midOpacity, 0.02, "panel should be fading in, not waiting to snap")
        XCTAssertLessThan(midOpacity, 0.98, "panel should still be in flight at 80ms")

        wait(for: [presented], timeout: 2)
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 0.25)

        let chrome = panel.presentationController as? GrokPanelPresentationController
        XCTAssertNotNil(chrome)
        XCTAssertEqual(chrome?.panelView.alpha ?? 0, 1, accuracy: 0.05)
        XCTAssertEqual(chrome?.panelView.transform ?? .identity, .identity)
        XCTAssertEqual(chrome?.dimmingView.alpha ?? 0, GrokPanelMotion.dimmingAlpha, accuracy: 0.05)
        XCTAssertNotNil(chrome?.backdropBlurView.effect)
        XCTAssertGreaterThan(chrome?.backdropBlurView.alpha ?? 0, 0)
        XCTAssertNotNil(chrome?.panelView.layer.mask as? CAGradientLayer)
        XCTAssertEqual(chrome?.panelWrapper.frame.height ?? 0, 844 * GrokPanelMotion.heightRatio, accuracy: 1)

        root.dismiss(animated: true)
        wait(for: [dismissed], timeout: 2)
        XCTAssertNil(root.presentedViewController)
        XCTAssertNil(chrome?.dimmingView.superview)
        XCTAssertNil(chrome?.backdropBlurView.superview)

        window.isHidden = true
    }
}
