import UIKit

/// Tunables for the Grok-style panel dismiss.
///
/// The finger moves the panel 1:1. These values only describe the extra dissolve
/// (scale, a few points of drop, fade, blur, dimming) driven by transition progress.
enum GrokPanelMotion {
    /// End scale. Small enough to read as a settle, not a zoom-away.
    static let dismissedScale: CGFloat = 0.97
    /// Extra downward shift in points, on top of the finger offset.
    static let dismissedTranslationY: CGFloat = 12

    /// Present is a hair slower than dismiss so the card arrives instead of snapping in.
    static let presentDuration: TimeInterval = 0.38
    static let dismissDuration: TimeInterval = 0.35
    /// Light spring. High damping so the card does not overshoot.
    static let springDamping: CGFloat = 0.88
    /// Reduce Motion: alpha crossfade only, no scale or translation.
    static let reduceMotionDuration: TimeInterval = 0.2

    /// Resting glass under the open panel.
    static let restingBlurStyle: UIBlurEffect.Style = .systemUltraThinMaterial
    /// Stronger glass while the card is dissolving. Never animated to `nil` — that pops.
    static let peakBlurStyle: UIBlurEffect.Style = .systemThinMaterial
    /// Slightly under opaque so the ramp to `peakBlurAlpha` reads as "more blur".
    static let restingBlurAlpha: CGFloat = 0.85
    static let peakBlurAlpha: CGFloat = 1

    /// Progress at which the style boost (ultraThin → thin) has finished.
    static let blurStyleBoostEnd: CGFloat = 0.2
    /// Progress at which blur alpha has reached its peak.
    static let blurRampEnd: CGFloat = 0.3
    /// Progress at which blur alpha starts falling to 0. The gap after `blurRampEnd` is a hold.
    static let blurFadeStart: CGFloat = 0.4
    /// The card's own alpha finishes fading before the blur does, so it dissolves into the glass.
    static let panelFadeEnd: CGFloat = 0.85
    /// Dimming starts leaving after the blur has already peaked.
    static let dimmingFadeStart: CGFloat = 0.3
    /// Present: blur alpha reaches its resting value before the transition ends.
    static let presentBlurRevealEnd: CGFloat = 0.8

    static let dimmingAlpha: CGFloat = 0.25
    /// Soft top edge, about half the corner radius, so it reads as anti-aliasing into the blur
    /// rather than a transparent header.
    static let edgeFadeHeight: CGFloat = 16
    /// Content and the grabber start below the fade band.
    static let contentTopInset: CGFloat = 16
    static let cornerRadius: CGFloat = 28
    static let heightRatio: CGFloat = 0.9

    /// Fraction of the panel height the finger must travel for progress 1.
    /// Tuned like Grok's history drawer: a short drag barely dissolves; full dissolve needs a real pull.
    static let interactiveDistanceRatio: CGFloat = 0.58
    /// Clamped so phone and pad need roughly the same deliberate thumb travel.
    static let interactiveDistanceRange: ClosedRange<CGFloat> = 320...400
    /// Release past this fraction of the distance and the panel finishes dismissing.
    /// Just under half the travel so a casual tug cancels instead of closing.
    static let finishProgressThreshold: CGFloat = 0.52
    /// A flick faster than this (points/second, downward) dismisses even from a short drag.
    /// High enough that a light swipe is ignored; only a committed flick counts.
    static let finishVelocityThreshold: CGFloat = 1_400

    /// Upward rubber-band approaches this many points and never reaches it.
    static let rubberBandLimit: CGFloat = 80

    static var dismissedTransform: CGAffineTransform {
        CGAffineTransform(scaleX: dismissedScale, y: dismissedScale)
            .concatenating(CGAffineTransform(translationX: 0, y: dismissedTranslationY))
    }

    static func interactiveDistance(panelHeight: CGFloat) -> CGFloat {
        let proposed = panelHeight * interactiveDistanceRatio
        return min(max(proposed, interactiveDistanceRange.lowerBound), interactiveDistanceRange.upperBound)
    }

    static func interactiveProgress(translationY: CGFloat, panelHeight: CGFloat) -> CGFloat {
        let distance = max(interactiveDistance(panelHeight: panelHeight), 1)
        return min(1, max(0, translationY / distance))
    }

    /// Upward velocity always cancels: the finger is putting the panel back.
    static func shouldFinish(progress: CGFloat, velocityY: CGFloat) -> Bool {
        if velocityY < 0 { return false }
        return progress >= finishProgressThreshold || velocityY >= finishVelocityThreshold
    }

    /// Compresses a pull so it stays inside `rubberBandLimit`.
    /// Downward dismiss tracking does not use this — the finger offset stays 1:1.
    /// Upward resistance does. The curve is odd, monotonic, and never reaches the limit.
    static func rubberBand(_ offset: CGFloat) -> CGFloat {
        let distance = abs(offset)
        let banded = (distance * rubberBandLimit) / (distance + rubberBandLimit)
        return offset < 0 ? -banded : banded
    }
}
