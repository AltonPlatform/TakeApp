import UIKit

/// Full-screen chrome behind the card: dimming, one backdrop blur, and the card itself.
/// The card is split in two. `panelWrapper` follows the finger. `panelView` only receives
/// the dissolve (scale, 12pt, fade) from the animator.
@MainActor
final class GrokPanelPresentationController: UIPresentationController {
    let dimmingView = UIView()
    let backdropBlurView = UIVisualEffectView(
        effect: UIBlurEffect(style: GrokPanelMotion.restingBlurStyle)
    )
    let panelWrapper = UIView()
    let panelView = UIView()
    let contentClipView = UIView()

    let interaction = GrokPanelInteractionController()
    /// While the finger-up return animation is running, transition teardown must not snap the card.
    var deferRestingSnap = false

    private let edgeMask = CAGradientLayer()
    private let grabber = UIView()
    private var didInstall = false

    override var presentedView: UIView? { panelWrapper }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let height = container.bounds.height * GrokPanelMotion.heightRatio
        return CGRect(
            x: 0,
            y: container.bounds.height - height,
            width: container.bounds.width,
            height: height
        )
    }

    override var shouldRemovePresentersView: Bool { false }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        installChromeIfNeeded()
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        guard completed else {
            removeBackdrop()
            return
        }
        applyResting(resetWrapper: true)
        interaction.attach(to: self)
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        if completed {
            interaction.detach()
            removeBackdrop()
        } else if !deferRestingSnap {
            applyResting(resetWrapper: true)
        }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let container = containerView else { return }
        dimmingView.frame = container.bounds
        backdropBlurView.frame = container.bounds
        // `frame` clears an in-flight transform animation. Position through bounds and center.
        let frame = frameOfPresentedViewInContainerView
        panelWrapper.bounds = CGRect(origin: .zero, size: frame.size)
        panelWrapper.center = CGPoint(x: frame.midX, y: frame.midY)
        layoutChrome()
    }

    func installChromeIfNeeded() {
        guard let container = containerView, !didInstall else { return }
        didInstall = true

        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0
        dimmingView.accessibilityLabel = "Dismiss"
        dimmingView.accessibilityTraits = .button
        dimmingView.isAccessibilityElement = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDimmingTap))
        dimmingView.addGestureRecognizer(tap)

        // One effect view for the whole presentation. Alpha does the fade; effect stays non-nil.
        backdropBlurView.effect = UIBlurEffect(style: GrokPanelMotion.restingBlurStyle)
        backdropBlurView.alpha = 0
        backdropBlurView.isUserInteractionEnabled = false

        panelWrapper.backgroundColor = .clear
        panelView.backgroundColor = .clear
        panelView.alpha = 0
        contentClipView.backgroundColor = .systemBackground
        contentClipView.layer.cornerRadius = GrokPanelMotion.cornerRadius
        contentClipView.layer.cornerCurve = .continuous
        contentClipView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentClipView.clipsToBounds = true

        grabber.backgroundColor = .systemGray3
        grabber.layer.cornerRadius = 2.5
        grabber.isUserInteractionEnabled = false
        grabber.accessibilityLabel = "Drag down to close"

        container.addSubview(dimmingView)
        container.addSubview(backdropBlurView)
        container.addSubview(panelWrapper)
        panelWrapper.addSubview(panelView)
        panelView.addSubview(contentClipView)
        contentClipView.addSubview(grabber)

        if let content = presentedViewController.view {
            content.translatesAutoresizingMaskIntoConstraints = true
            content.autoresizingMask = []
            content.backgroundColor = .clear
            contentClipView.addSubview(content)
        }
        panelWrapper.frame = frameOfPresentedViewInContainerView
        panelWrapper.accessibilityViewIsModal = true
        layoutChrome()
    }

    func layoutChrome() {
        let bounds = panelWrapper.bounds
        panelView.frame = bounds
        contentClipView.frame = bounds
        let grabberSize = CGSize(width: 36, height: 5)
        grabber.frame = CGRect(
            x: (bounds.width - grabberSize.width) / 2,
            y: GrokPanelMotion.contentTopInset,
            width: grabberSize.width,
            height: grabberSize.height
        )
        if let content = presentedViewController.view, content.superview === contentClipView {
            let top = grabber.frame.maxY + 8
            content.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        }
        updateEdgeMask()
    }

    func applyResting(resetWrapper: Bool) {
        if deferRestingSnap { return }
        if resetWrapper {
            panelWrapper.transform = .identity
        }
        panelView.alpha = 1
        panelView.transform = .identity
        dimmingView.alpha = GrokPanelMotion.dimmingAlpha
        backdropBlurView.effect = UIBlurEffect(style: GrokPanelMotion.restingBlurStyle)
        backdropBlurView.alpha = UIAccessibility.isReduceTransparencyEnabled
            ? 0
            : GrokPanelMotion.restingBlurAlpha
    }

    func removeBackdrop() {
        dimmingView.removeFromSuperview()
        backdropBlurView.removeFromSuperview()
        didInstall = false
    }

    private func updateEdgeMask() {
        let height = panelView.bounds.height
        guard height > 0 else { return }
        let fade = GrokPanelMotion.edgeFadeHeight / height
        // A midpoint stop keeps the 16pt fade from looking like a flat translucent strip.
        edgeMask.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor,
        ]
        edgeMask.locations = [
            0,
            NSNumber(value: Float(fade * 0.5)),
            NSNumber(value: Float(fade)),
            1,
        ]
        edgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        edgeMask.endPoint = CGPoint(x: 0.5, y: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame = panelView.bounds
        panelView.layer.mask = edgeMask
        CATransaction.commit()
    }

    @objc private func handleDimmingTap() {
        guard !presentedViewController.isBeingPresented, !presentedViewController.isBeingDismissed else { return }
        presentedViewController.dismiss(animated: true)
    }
}
