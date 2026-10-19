import UIKit

/// Drives dismiss from a downward pan on the card, or from the list's own pan once it is scrolled to the top.
/// The wrapper tracks the finger. Transition progress only scrubs the dissolve.
@MainActor
final class GrokPanelInteractionController: UIPercentDrivenInteractiveTransition, UIGestureRecognizerDelegate {
    private(set) var isInteracting = false

    private weak var presentationController: GrokPanelPresentationController?
    private weak var scrollView: UIScrollView?
    private var panelPan: UIPanGestureRecognizer?
    private var fingerOffset: CGFloat = 0
    private var scrollOriginY: CGFloat = 0
    private var scrollLocked = false
    private var isReversing = false

    override init() {
        super.init()
        wantsInteractiveStart = true
    }

    func attach(to presentationController: GrokPanelPresentationController) {
        self.presentationController = presentationController
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanelPan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        presentationController.panelWrapper.addGestureRecognizer(pan)
        panelPan = pan
        DispatchQueue.main.async { [weak self, weak presentationController] in
            guard let self, let presentationController else { return }
            self.attachScrollIfNeeded(in: presentationController.panelWrapper)
            // SwiftUI may mount the list a beat after the transition ends.
            guard self.scrollView == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak presentationController] in
                guard let self, let presentationController else { return }
                self.attachScrollIfNeeded(in: presentationController.panelWrapper)
            }
        }
    }

    func detach() {
        if let panelPan {
            panelPan.view?.removeGestureRecognizer(panelPan)
            self.panelPan = nil
        }
        if let scrollView {
            scrollView.panGestureRecognizer.removeTarget(self, action: #selector(handleScrollPan(_:)))
            self.scrollView = nil
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan === panelPan else { return true }
        let velocity = pan.velocity(in: pan.view)
        guard velocity.y > 0, abs(velocity.y) > abs(velocity.x) else { return false }
        guard let presented = presentationController?.presentedViewController else { return false }
        // A non-interactive transition owns the card until it finishes.
        if isReversing { return false }
        if presented.isBeingPresented { return false }
        if presented.isBeingDismissed && !isInteracting { return false }
        if let scrollView {
            let point = pan.location(in: scrollView)
            if scrollView.bounds.contains(point) {
                return false
            }
        }
        return true
    }

    @objc private func handlePanelPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view?.superview)
        let velocity = gesture.velocity(in: gesture.view?.superview)
        switch gesture.state {
        case .began:
            beginInteractiveDismiss()
        case .changed:
            guard isInteracting else { return }
            followFinger(translationY: translation.y)
        case .ended:
            finishInteractive(velocityY: velocity.y, translationY: translation.y)
        case .cancelled, .failed:
            cancelInteractive()
        default:
            break
        }
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        guard let scrollView else { return }
        let translation = gesture.translation(in: gesture.view)
        let velocity = gesture.velocity(in: gesture.view)
        switch gesture.state {
        case .began:
            scrollLocked = false
        case .changed:
            if !scrollLocked {
                guard scrollView.contentOffset.y <= 0 else { return }
                guard translation.y > 8, abs(velocity.y) >= abs(velocity.x) else { return }
                guard let presented = presentationController?.presentedViewController else { return }
                if presented.isBeingPresented || presented.isBeingDismissed { return }
                scrollLocked = true
                scrollOriginY = translation.y
                beginInteractiveDismiss()
            }
            guard isInteracting, scrollLocked else { return }
            scrollView.contentOffset = .zero
            followFinger(translationY: translation.y - scrollOriginY)
        case .ended:
            guard scrollLocked else { return }
            finishInteractive(velocityY: velocity.y, translationY: translation.y - scrollOriginY)
            scrollLocked = false
        case .cancelled, .failed:
            guard scrollLocked else { return }
            cancelInteractive()
            scrollLocked = false
        default:
            break
        }
    }

    private func attachScrollIfNeeded(in root: UIView) {
        guard scrollView == nil else { return }
        guard let scrollView = tallestScrollView(in: root) else { return }
        scrollView.alwaysBounceVertical = true
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handleScrollPan(_:)))
        self.scrollView = scrollView
    }

    private func tallestScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.bounds.height > (best?.bounds.height ?? 0) {
                best = scroll
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    private func beginInteractiveDismiss() {
        guard !isInteracting else { return }
        guard let presented = presentationController?.presentedViewController else { return }
        guard !presented.isBeingPresented, !presented.isBeingDismissed else { return }
        isInteracting = true
        presented.dismiss(animated: true)
    }

    private func followFinger(translationY: CGFloat) {
        guard let chrome = presentationController else { return }
        let offset = translationY >= 0 ? translationY : GrokPanelMotion.rubberBand(translationY)
        fingerOffset = offset
        chrome.panelWrapper.transform = CGAffineTransform(translationX: 0, y: offset)
        let height = chrome.frameOfPresentedViewInContainerView.height
        update(GrokPanelMotion.interactiveProgress(translationY: translationY, panelHeight: height))
    }

    private func finishInteractive(velocityY: CGFloat, translationY: CGFloat) {
        guard isInteracting else { return }
        let height = presentationController?.frameOfPresentedViewInContainerView.height ?? 1
        let progress = GrokPanelMotion.interactiveProgress(translationY: translationY, panelHeight: height)
        if GrokPanelMotion.shouldFinish(progress: progress, velocityY: velocityY) {
            // Leave the wrapper where the finger released. The card finishes dissolving there.
            isInteracting = false
            completionCurve = .easeInOut
            completionSpeed = 1
            finish()
        } else {
            cancelInteractive()
        }
    }

    /// Plays the dismiss backwards ourselves. `cancel()` only completes the interactive
    /// transition; its own reverse is too short to see, and layout used to wipe the transform.
    private func cancelInteractive() {
        guard isInteracting, let chrome = presentationController else { return }
        isInteracting = false
        scrollLocked = false
        isReversing = true

        let snapshot = ReturnSnapshot(
            wrapper: chrome.panelWrapper.transform,
            panel: chrome.panelView.transform,
            panelAlpha: chrome.panelView.alpha,
            dimmingAlpha: chrome.dimmingView.alpha,
            blurAlpha: chrome.backdropBlurView.alpha,
            blurEffect: chrome.backdropBlurView.effect
        )

        chrome.deferRestingSnap = true
        completionSpeed = 10_000
        cancel()
        // cancel() may have already restored the resting model values. Put the finger state
        // back before the next frame, then spring to rest — the reverse of the drag.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chrome.panelWrapper.transform = snapshot.wrapper
        chrome.panelView.transform = snapshot.panel
        chrome.panelView.alpha = snapshot.panelAlpha
        chrome.dimmingView.alpha = snapshot.dimmingAlpha
        chrome.backdropBlurView.alpha = snapshot.blurAlpha
        chrome.backdropBlurView.effect = snapshot.blurEffect
        CATransaction.commit()

        let returning = UIViewPropertyAnimator(
            duration: GrokPanelMotion.dismissDuration,
            dampingRatio: GrokPanelMotion.springDamping
        )
        returning.addAnimations {
            chrome.panelWrapper.transform = .identity
            chrome.panelView.transform = .identity
            chrome.panelView.alpha = 1
            chrome.dimmingView.alpha = GrokPanelMotion.dimmingAlpha
            chrome.backdropBlurView.alpha = UIAccessibility.isReduceTransparencyEnabled
                ? 0
                : GrokPanelMotion.restingBlurAlpha
            chrome.backdropBlurView.effect = UIBlurEffect(style: GrokPanelMotion.restingBlurStyle)
        }
        returning.addCompletion { [weak self, weak chrome] _ in
            self?.fingerOffset = 0
            self?.isReversing = false
            chrome?.deferRestingSnap = false
        }
        returning.startAnimation()
    }
}

private struct ReturnSnapshot {
    var wrapper: CGAffineTransform
    var panel: CGAffineTransform
    var panelAlpha: CGFloat
    var dimmingAlpha: CGFloat
    var blurAlpha: CGFloat
    var blurEffect: UIVisualEffect?
}
