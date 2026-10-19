import SwiftUI

enum ChatSendMotion {
    static var listInsert: Animation {
        if AccessibilitySettings.reduceMotion {
            return .easeOut(duration: 0.2)
        }
        return .spring(response: 0.38, dampingFraction: 0.86)
    }

    static var entrance: Animation {
        if AccessibilitySettings.reduceMotion {
            return .easeOut(duration: 0.2)
        }
        return .spring(response: 0.42, dampingFraction: 0.78)
    }

    /// Long, critically damped rise for the photo preview. No bounce.
    static var paste: Animation {
        if AccessibilitySettings.reduceMotion {
            return .easeOut(duration: 0.22)
        }
        return .spring(response: 0.72, dampingFraction: 0.96)
    }

    static var entranceScale: CGFloat {
        AccessibilitySettings.reduceMotion ? 1 : 0.86
    }

    static var entranceOffset: CGFloat {
        AccessibilitySettings.reduceMotion ? 0 : 12
    }

    /// One spring for both axes so the bubble does not hitch when X and Y finish apart.
    static var morphSpring: Animation {
        .spring(response: 0.46, dampingFraction: 0.92)
    }

    /// Fresh rows that already morphed out of the composer must not replay the
    /// scale-in. `morphPrepared` stays true after the morph source is cleared.
    static func playsEntrance(isFresh: Bool, hasMorphSource: Bool, morphPrepared: Bool) -> Bool {
        isFresh && !hasMorphSource && !morphPrepared
    }
}

enum MessageSendTransition {
    static var spring: Animation {
        .spring(response: 0.32, dampingFraction: 0.8)
    }

    static let fieldRadius: CGFloat = 20
    static let bubbleRadius: CGFloat = ChatBubbleShape.outerRadius
    static let revealDuration: TimeInterval = 0.15

    static func shouldFly(reduceMotion: Bool, nearBottom: Bool, hasSource: Bool) -> Bool {
        !reduceMotion && nearBottom && hasSource
    }
}

enum MessageSendMath {
    static func mix(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        return from + (to - from) * t
    }

    static func rect(from source: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: mix(source.minX, target.minX, progress),
            y: mix(source.minY, target.minY, progress),
            width: mix(source.width, target.width, progress),
            height: mix(source.height, target.height, progress)
        )
    }

    /// Tail stays hidden until the last 30% of the flight.
    static func tailProgress(_ progress: CGFloat) -> CGFloat {
        let start: CGFloat = 0.7
        guard progress > start else { return 0 }
        return min((progress - start) / (1 - start), 1)
    }
}

enum ChatSendMorphMath {
    /// Moves `bubble` so its left edge and bottom meet `source`.
    static func startOffset(source: CGRect, bubble: CGRect) -> CGSize {
        CGSize(
            width: source.minX - bubble.minX,
            height: source.maxY - bubble.maxY
        )
    }
}

/// Grows a new row from its bottom so older messages glide up with the scroll anchor.
struct ChatRowReveal: Layout {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(proposal)
        return CGSize(
            width: natural.width,
            height: Self.fittedHeight(natural: natural.height, progress: progress)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let natural = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let y = bounds.minY + Self.childMinY(containerHeight: bounds.height, childHeight: natural.height)
        child.place(
            at: CGPoint(x: bounds.minX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: natural.height)
        )
    }

    static func fittedHeight(natural: CGFloat, progress: CGFloat) -> CGFloat {
        natural * min(max(progress, 0), 1)
    }

    static func childMinY(containerHeight: CGFloat, childHeight: CGFloat) -> CGFloat {
        containerHeight - childHeight
    }
}

