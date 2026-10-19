import QuartzCore
import SwiftUI
import UIKit

/// Motion constants and curves taken from Telegram-iOS
/// (`ContextGesture`, `ContextControllerExtractedPresentationNode`,
/// `ReactionContextNode`, `makeSpringBounceAnimation`).
enum ChatContextMotion {
    static let beginDelay: TimeInterval = 0.12
    static let pressDuration: TimeInterval = 0.2
    static let presentDuration: TimeInterval = 0.42
    static let capsuleSpringDuration: TimeInterval = 0.5
    static let capsuleScaleDelay: TimeInterval = 0.1
    static let capsuleExpandDelay: TimeInterval = 0.11
    static let emojiAppearDuration: TimeInterval = 0.4
    static let gridDuration: TimeInterval = 0.4
    static let dismissDuration: TimeInterval = 0.2
    static let dismissAfterReaction: TimeInterval = 0.25
    /// Bubble travels home and settles. Must finish before the overlay is removed.
    static let dismissReturnDuration: TimeInterval = 0.42
    static let menuFadeInDuration: TimeInterval = 0.05
    static let blurDuration: TimeInterval = 0.2
    static let backdropDimOpacity: Double = 0.22
    static let pressCancelDuration: TimeInterval = 0.2
    static let maximumPressDistance: CGFloat = 10
    /// Telegram `animateOutToReaction` parabolic flight (~0.28s).
    static let reactionFlightDuration: TimeInterval = 0.28
    static let swipeReplySpringDuration: TimeInterval = 0.36
    static let swipeReplyIconDuration: TimeInterval = 0.2
    /// Delay after highlight before charge shake begins.
    static let chargeDelay: TimeInterval = 0.2
    /// Full charge duration until big-commit auto-fires.
    static let chargeDuration: TimeInterval = 0.7
    static let chargeShakeHz: Double = 8
    static let bigEffectHoldDuration: TimeInterval = 0.2

    /// Telegram `makeSpringBounceAnimation` (mass 5, stiffness 900) compressed to `duration`.
    static func bounce(damping: CGFloat = 104, duration: TimeInterval) -> Animation {
        if AccessibilitySettings.reduceMotion {
            return .easeInOut(duration: min(duration, 0.2))
        }
        let speed = springSpeed(mass: 5, stiffness: 900, damping: damping, duration: duration)
        return .interpolatingSpring(mass: 5, stiffness: 900, damping: damping)
            .speed(speed)
    }

    /// Telegram Display spring (mass 3, stiffness 1000, damping 500) compressed to `gridDuration`.
    static func gridSpring() -> Animation {
        if AccessibilitySettings.reduceMotion {
            return .easeInOut(duration: 0.2)
        }
        let speed = springSpeed(mass: 3, stiffness: 1000, damping: 500, duration: gridDuration)
        return .interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)
            .speed(speed)
    }

    static func presentSpring() -> Animation {
        bounce(damping: 104, duration: presentDuration)
    }

    static func dismiss(afterReaction: Bool) -> Animation {
        .easeInOut(duration: afterReaction ? dismissAfterReaction : dismissDuration)
    }

    /// Ease-out that lands exactly on the list bubble so removal does not snap.
    static func dismissReturn() -> Animation {
        if AccessibilitySettings.reduceMotion {
            return .easeOut(duration: 0.2)
        }
        return .timingCurve(0.16, 0.84, 0.2, 1, duration: dismissReturnDuration)
    }

    static func pressMinScale(width: CGFloat) -> CGFloat {
        max(0.7, (width - 15) / max(width, 1))
    }

    /// Wave delay from `ReactionContextNode.animateIn`:
    /// `0.01 + (distance / width) * 0.3`.
    static func itemDelay(itemCenterX: CGFloat, anchorX: CGFloat, width: CGFloat) -> TimeInterval {
        let distance = abs(itemCenterX - anchorX)
        let distanceNorm = distance / max(width, 1)
        return 0.01 + Double(distanceNorm) * 0.3
    }

    /// Mirror of Telegram `animation.speed = settlingDuration / duration`.
    static func springSpeed(
        mass: CGFloat,
        stiffness: CGFloat,
        damping: CGFloat,
        duration: TimeInterval
    ) -> Double {
        let probe = CASpringAnimation()
        probe.mass = mass
        probe.stiffness = stiffness
        probe.damping = damping
        let settling = max(probe.settlingDuration, 0.001)
        return settling / max(duration, 0.001)
    }
}

enum AccessibilitySettings {
    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}
