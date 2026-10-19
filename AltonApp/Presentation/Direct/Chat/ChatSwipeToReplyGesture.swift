import SwiftUI
import UIKit

/// Pure swipe-to-reply math (Telegram-style left swipe with post-threshold resistance).
enum ChatSwipeToReply {
    static let maxOffset: CGFloat = -80
    static let threshold: CGFloat = -45
    static let iconSize: CGFloat = 33
    static let resistance: CGFloat = 0.35

    /// Clamps horizontal translation with resistance past the threshold.
    static func offset(translationX: CGFloat) -> CGFloat {
        let tx = min(0, translationX)
        if tx > threshold {
            return tx
        }
        let resisted = threshold + (tx - threshold) * resistance
        return max(maxOffset, resisted)
    }

    /// True when the finger has crossed the reply threshold.
    static func shouldTrigger(offset: CGFloat) -> Bool {
        offset <= threshold
    }

    /// 0…1 fill progress toward the threshold.
    static func progress(offset: CGFloat) -> CGFloat {
        min(1, abs(offset) / abs(threshold))
    }

    /// Icon opacity from 0 at rest to 1 at threshold.
    static func iconOpacity(offset: CGFloat) -> Double {
        Double(progress(offset: offset))
    }

    /// Arrow rotation from -30° at rest to 0° at threshold.
    static func arrowRotation(offset: CGFloat) -> Angle {
        .degrees(Double(-30) * (1 - Double(progress(offset: offset))))
    }
}

/// UIKit pan that only begins on a clear leftward horizontal drag.
struct ChatSwipeToReplyGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool = true
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelPress: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> SwipeToReplyGestureRecognizer {
        let recognizer = SwipeToReplyGestureRecognizer(target: nil, action: nil)
        recognizer.isEnabled = isEnabled
        context.coordinator.bind(recognizer)
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelPress = onCancelPress
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: SwipeToReplyGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelPress = onCancelPress
    }

    final class Coordinator {
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat) -> Void)?
        var onCancelPress: (() -> Void)?

        func bind(_ recognizer: SwipeToReplyGestureRecognizer) {
            recognizer.onChanged = { [weak self] offset in
                self?.onChanged?(offset)
            }
            recognizer.onEnded = { [weak self] offset in
                self?.onEnded?(offset)
            }
            recognizer.onCancelPress = { [weak self] in
                self?.onCancelPress?()
            }
        }
    }
}

final class SwipeToReplyGestureRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?
    var onCancelPress: (() -> Void)?

    private var didNotifyCancelPress = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        maximumNumberOfTouches = 1
        cancelsTouchesInView = false
        addTarget(self, action: #selector(handlePan))
    }

    override func reset() {
        super.reset()
        didNotifyCancelPress = false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = self.velocity(in: view)
        let translation = self.translation(in: view)
        guard translation.x < 0 || velocity.x < 0 else { return false }
        return abs(velocity.x) > abs(velocity.y) || abs(translation.x) > abs(translation.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer,
           !(otherGestureRecognizer is SwipeToReplyGestureRecognizer)
        {
            return false
        }
        return true
    }

    @objc private func handlePan() {
        let tx = translation(in: view).x
        let offset = ChatSwipeToReply.offset(translationX: tx)
        switch state {
        case .began, .changed:
            if !didNotifyCancelPress {
                didNotifyCancelPress = true
                onCancelPress?()
                cancelSiblingContextPress()
            }
            onChanged?(offset)
        case .ended, .cancelled, .failed:
            onEnded?(offset)
        default:
            break
        }
    }

    private func cancelSiblingContextPress() {
        guard let view else { return }
        var candidate: UIView? = view
        while let current = candidate {
            if let recognizers = current.gestureRecognizers {
                for recognizer in recognizers {
                    if let press = recognizer as? ContextPressGestureRecognizer {
                        press.forceCancel()
                    }
                }
            }
            candidate = current.superview
        }
    }
}
