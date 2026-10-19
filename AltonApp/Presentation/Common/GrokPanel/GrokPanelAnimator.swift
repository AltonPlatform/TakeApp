import UIKit

/// Present and dismiss share one property animator so a pan can scrub the same timeline.
/// Blur strength comes from alpha. `effect` only moves between two non-nil styles, then the
/// view is removed with the chrome — it is never set to `nil` mid-animation.
@MainActor
final class GrokPanelAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool

    private var animator: UIViewPropertyAnimator?
    private var resignObserver: NSObjectProtocol?
    private var didComplete = false

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        if UIAccessibility.isReduceMotionEnabled {
            return GrokPanelMotion.reduceMotionDuration
        }
        return isPresenting ? GrokPanelMotion.presentDuration : GrokPanelMotion.dismissDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: transitionContext).startAnimation()
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let animator { return animator }
        let animator = makeAnimator(using: transitionContext)
        self.animator = animator
        return animator
    }

    private func makeAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewPropertyAnimator {
        guard let chrome = chrome(from: transitionContext) else {
            transitionContext.completeTransition(false)
            return UIViewPropertyAnimator(duration: 0, curve: .linear)
        }
        chrome.installChromeIfNeeded()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        let duration = transitionDuration(using: transitionContext)
        let interactive = transitionContext.isInteractive

        if isPresenting {
            prepareForPresent(chrome, reduceMotion: reduceMotion)
        }

        let animator: UIViewPropertyAnimator
        if reduceMotion {
            animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut)
            animator.addAnimations {
                self.applyReducedMotion(chrome, reduceTransparency: reduceTransparency)
            }
        } else {
            animator = UIViewPropertyAnimator(duration: duration, dampingRatio: GrokPanelMotion.springDamping)
            animator.addAnimations {
                UIView.animateKeyframes(withDuration: duration, delay: 0, options: []) {
                    if self.isPresenting {
                        self.addPresentKeyframes(chrome, reduceTransparency: reduceTransparency)
                    } else {
                        self.addDismissKeyframes(chrome, reduceTransparency: reduceTransparency)
                    }
                }
            }
        }

        animator.addCompletion { [weak self] position in
            self?.finish(position: position, chrome: chrome, context: transitionContext)
        }
        observeResignActive(animator: animator, interactive: interactive)
        return animator
    }

    private func chrome(from transitionContext: UIViewControllerContextTransitioning) -> GrokPanelPresentationController? {
        let controller = isPresenting
            ? transitionContext.viewController(forKey: .to)
            : transitionContext.viewController(forKey: .from)
        return controller?.presentationController as? GrokPanelPresentationController
    }

    private func prepareForPresent(_ chrome: GrokPanelPresentationController, reduceMotion: Bool) {
        chrome.panelView.alpha = 0
        chrome.panelView.transform = reduceMotion ? .identity : GrokPanelMotion.dismissedTransform
        chrome.dimmingView.alpha = 0
        chrome.backdropBlurView.effect = UIBlurEffect(style: GrokPanelMotion.restingBlurStyle)
        chrome.backdropBlurView.alpha = 0
    }

    private func applyReducedMotion(_ chrome: GrokPanelPresentationController, reduceTransparency: Bool) {
        if isPresenting {
            chrome.panelView.alpha = 1
            chrome.panelView.transform = .identity
            chrome.dimmingView.alpha = GrokPanelMotion.dimmingAlpha
            chrome.backdropBlurView.alpha = reduceTransparency ? 0 : GrokPanelMotion.restingBlurAlpha
        } else {
            chrome.panelView.alpha = 0
            chrome.panelView.transform = .identity
            chrome.dimmingView.alpha = 0
            chrome.backdropBlurView.alpha = 0
        }
    }

    private func addPresentKeyframes(_ chrome: GrokPanelPresentationController, reduceTransparency: Bool) {
        UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
            chrome.panelView.alpha = 1
            chrome.panelView.transform = .identity
        }
        UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: GrokPanelMotion.presentBlurRevealEnd) {
            chrome.backdropBlurView.alpha = reduceTransparency ? 0 : GrokPanelMotion.restingBlurAlpha
        }
        UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1 - GrokPanelMotion.dimmingFadeStart) {
            chrome.dimmingView.alpha = GrokPanelMotion.dimmingAlpha
        }
    }

    private func addDismissKeyframes(_ chrome: GrokPanelPresentationController, reduceTransparency: Bool) {
        UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: GrokPanelMotion.panelFadeEnd) {
            chrome.panelView.alpha = 0
            chrome.panelView.transform = GrokPanelMotion.dismissedTransform
        }
        if !reduceTransparency {
            // Style changes only while both effects are non-nil. The rest of the dissolve is alpha.
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: GrokPanelMotion.blurStyleBoostEnd) {
                chrome.backdropBlurView.effect = UIBlurEffect(style: GrokPanelMotion.peakBlurStyle)
            }
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: GrokPanelMotion.blurRampEnd) {
                chrome.backdropBlurView.alpha = GrokPanelMotion.peakBlurAlpha
            }
            UIView.addKeyframe(
                withRelativeStartTime: GrokPanelMotion.blurRampEnd,
                relativeDuration: GrokPanelMotion.blurFadeStart - GrokPanelMotion.blurRampEnd
            ) {
                chrome.backdropBlurView.alpha = GrokPanelMotion.peakBlurAlpha
            }
            UIView.addKeyframe(
                withRelativeStartTime: GrokPanelMotion.blurFadeStart,
                relativeDuration: 1 - GrokPanelMotion.blurFadeStart
            ) {
                chrome.backdropBlurView.alpha = 0
            }
        }
        UIView.addKeyframe(
            withRelativeStartTime: GrokPanelMotion.dimmingFadeStart,
            relativeDuration: 1 - GrokPanelMotion.dimmingFadeStart
        ) {
            chrome.dimmingView.alpha = 0
        }
    }

    /// Every path out of the transition completes the context. A backgrounding non-interactive
    /// animation is forced to `.end` so the card is not left mid-fade when the app returns.
    /// Memory warnings do not stop the animation: nothing here is a snapshot or a cache.
    private func observeResignActive(animator: UIViewPropertyAnimator, interactive: Bool) {
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak animator] _ in
            guard let animator, animator.state == .active, !interactive else { return }
            MainActor.assumeIsolated {
                guard self?.didComplete == false else { return }
                animator.stopAnimation(false)
                animator.finishAnimation(at: .end)
            }
        }
    }

    private func finish(
        position: UIViewAnimatingPosition,
        chrome: GrokPanelPresentationController,
        context: UIViewControllerContextTransitioning
    ) {
        guard !didComplete else { return }
        didComplete = true
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        let completed = position == .end && !context.transitionWasCancelled
        if completed {
            if !isPresenting {
                chrome.removeBackdrop()
            } else {
                chrome.applyResting(resetWrapper: false)
            }
        } else {
            // Dismiss cancel: interaction controller springs the wrapper home — do not snap it.
            // Present cancel: there is no finger offset, so reset the wrapper with the rest of chrome.
            chrome.applyResting(resetWrapper: isPresenting)
            if isPresenting {
                chrome.removeBackdrop()
                chrome.panelWrapper.removeFromSuperview()
            }
        }
        context.completeTransition(completed)
        animator = nil
    }
}
