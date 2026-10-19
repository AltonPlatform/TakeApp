import SwiftUI
import UIKit

/// UIKit long-press that mirrors Telegram `ContextGesture`:
/// beginDelay 0.12s → progressive shrink over 0.2s → activate.
struct ChatContextPressGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool = true
    var onProgress: (CGFloat) -> Void
    var onActivate: (CGRect) -> Void
    var onCancel: () -> Void
    /// Window-space point while the finger stays down after the menu opens.
    var onMove: ((CGPoint) -> Void)? = nil
    var onRelease: (() -> Void)? = nil

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> ContextPressGestureRecognizer {
        let recognizer = ContextPressGestureRecognizer(target: nil, action: nil)
        recognizer.beginDelay = ChatContextMotion.beginDelay
        recognizer.pressDuration = ChatContextMotion.pressDuration
        recognizer.maximumDistance = ChatContextMotion.maximumPressDistance
        recognizer.isEnabled = isEnabled
        context.coordinator.bind(recognizer)
        context.coordinator.onProgress = onProgress
        context.coordinator.onActivate = onActivate
        context.coordinator.onCancel = onCancel
        context.coordinator.onMove = onMove
        context.coordinator.onRelease = onRelease
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: ContextPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
        context.coordinator.onProgress = onProgress
        context.coordinator.onActivate = onActivate
        context.coordinator.onCancel = onCancel
        context.coordinator.onMove = onMove
        context.coordinator.onRelease = onRelease
    }

    final class Coordinator {
        var onProgress: ((CGFloat) -> Void)?
        var onActivate: ((CGRect) -> Void)?
        var onCancel: (() -> Void)?
        var onMove: ((CGPoint) -> Void)?
        var onRelease: (() -> Void)?

        func bind(_ recognizer: ContextPressGestureRecognizer) {
            recognizer.onProgress = { [weak self] progress in
                self?.onProgress?(progress)
            }
            recognizer.onActivate = { [weak self] frame in
                self?.onActivate?(frame)
            }
            recognizer.onCancel = { [weak self] in
                self?.onCancel?()
            }
            recognizer.onMove = { [weak self] point in
                self?.onMove?(point)
            }
            recognizer.onRelease = { [weak self] in
                self?.onRelease?()
            }
        }
    }
}

final class ContextPressGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var beginDelay: TimeInterval = ChatContextMotion.beginDelay
    var pressDuration: TimeInterval = ChatContextMotion.pressDuration
    var maximumDistance: CGFloat = ChatContextMotion.maximumPressDistance

    var onProgress: ((CGFloat) -> Void)?
    var onActivate: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onRelease: (() -> Void)?

    private var delayTimer: Timer?
    private var displayLink: CADisplayLink?
    private var pressStartTime: CFTimeInterval = 0
    private var currentProgress: CGFloat = 0
    private var isValidated = false
    private var wasActivated = false
    private var startLocation: CGPoint = .zero
    /// True while a press sequence is live and the bubble may be scaled.
    private var needsCancelReport = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        // Cancel delivery of the remaining touch sequence to the view once we
        // recognize, so a finger-up after long-press cannot fire a SwiftUI tap
        // (open media / post / take).
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = true
    }

    override func reset() {
        // When scroll steals the touch, UIKit calls reset() without
        // touchesCancelled. Report cancel so the bubble spring-backs.
        let shouldReport = needsCancelReport && !wasActivated && currentProgress > 0
        endTracking(reportCancel: shouldReport)
        currentProgress = 0
        isValidated = false
        wasActivated = false
        needsCancelReport = false
        super.reset()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        startLocation = touch.location(in: view)
        wasActivated = false
        isValidated = false
        currentProgress = 0
        needsCancelReport = true

        let timer = Timer(timeInterval: beginDelay, repeats: false) { [weak self] _ in
            guard let self, self.delayTimer != nil else { return }
            self.isValidated = true
            self.pressStartTime = CACurrentMediaTime()
            self.onProgress?(0)
            self.startDisplayLink()
        }
        delayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        // After activation the finger scrubs reactions; it must not cancel the menu.
        if wasActivated {
            if let touch = touches.first {
                onMove?(touch.location(in: nil))
            }
            return
        }
        guard let touch = touches.first, let view else { return }
        let location = touch.location(in: view)
        let dx = location.x - startLocation.x
        let dy = location.y - startLocation.y
        if hypot(dx, dy) > maximumDistance {
            cancelPress()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if wasActivated {
            onRelease?()
            state = .ended
            needsCancelReport = false
            endTracking(reportCancel: false)
        } else {
            cancelPress()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        cancelPress()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        if otherGestureRecognizer is SwipeToReplyGestureRecognizer {
            return false
        }
        return true
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func handleDisplayLink() {
        guard isValidated, !wasActivated else { return }
        let elapsed = CACurrentMediaTime() - pressStartTime
        let progress = CGFloat(min(1, max(0, elapsed / pressDuration)))
        currentProgress = progress
        onProgress?(progress)
        if progress >= 1 {
            activate()
        }
    }

    private func activate() {
        guard !wasActivated else { return }
        wasActivated = true
        needsCancelReport = false
        displayLink?.invalidate()
        displayLink = nil
        delayTimer?.invalidate()
        delayTimer = nil
        cancelParentScroll()
        if let view {
            // Fail every tap in the window tree, then climb parents (Telegram
            // cancelOtherGestures + cancelParentGestures).
            if let window = view.window {
                cancelOtherGestures(in: window, ignoring: self)
            }
            cancelParentGestures(from: view, ignoring: self)
        }
        let frame = view?.convert(view?.bounds ?? .zero, to: nil) ?? .zero
        state = .began
        onActivate?(frame)
    }

    /// Force-cancel from outside (e.g. swipe-to-reply began).
    func forceCancel() {
        cancelPress()
    }

    private func cancelPress() {
        let shouldReport = needsCancelReport && !wasActivated && (isValidated || currentProgress > 0)
        endTracking(reportCancel: shouldReport)
        needsCancelReport = false
        // From `.began`, `.failed` is illegal — use `.cancelled`.
        if state == .began || state == .changed {
            state = .cancelled
        } else if state == .possible {
            state = .failed
        }
    }

    private func endTracking(reportCancel: Bool) {
        delayTimer?.invalidate()
        delayTimer = nil
        displayLink?.invalidate()
        displayLink = nil
        if reportCancel {
            currentProgress = 0
            onCancel?()
        }
        isValidated = false
    }

    private func cancelParentScroll() {
        var candidate: UIView? = view
        while let current = candidate {
            if let scroll = current as? UIScrollView {
                let pan = scroll.panGestureRecognizer
                pan.isEnabled = false
                pan.isEnabled = true
                break
            }
            candidate = current.superview
        }
    }

    /// Fail sibling/parent tap recognizers so they cannot fire on finger-up
    /// after the context menu has already opened (Telegram `cancelOtherGestures`).
    private func cancelOtherGestures(in root: UIView, ignoring keep: UIGestureRecognizer) {
        if let recognizers = root.gestureRecognizers {
            for recognizer in recognizers {
                if recognizer === keep { continue }
                if recognizer is UITapGestureRecognizer {
                    recognizer.state = .failed
                } else if let other = recognizer as? ContextPressGestureRecognizer, other !== keep {
                    other.forceCancel()
                }
            }
        }
        for subview in root.subviews {
            cancelOtherGestures(in: subview, ignoring: keep)
        }
    }

    private func cancelParentGestures(from view: UIView, ignoring keep: UIGestureRecognizer) {
        if let recognizers = view.gestureRecognizers {
            for recognizer in recognizers {
                if recognizer === keep { continue }
                if recognizer is UITapGestureRecognizer
                    || recognizer is UILongPressGestureRecognizer
                    || recognizer is ContextPressGestureRecognizer
                {
                    if recognizer !== keep {
                        recognizer.state = .failed
                    }
                }
            }
        }
        if let superview = view.superview {
            cancelParentGestures(from: superview, ignoring: keep)
        }
    }
}
