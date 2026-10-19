import CoreGraphics
import Foundation

/// Pure layout for Telegram-style message action overlay.
enum ChatActionOverlayLayout {
    static let spacing: CGFloat = 10
    static let horizontalInset: CGFloat = 12
    static let barEstimatedHeight: CGFloat = 52
    static let menuEstimatedWidth: CGFloat = 240
    /// Distance between the reaction capsule and the lifted bubble.
    static let barGap: CGFloat = 8

    struct Placement: Equatable {
        /// Bubble frame after vertical shift (and optional height clip).
        let bubbleFrame: CGRect
        let barFrame: CGRect
        let menuFrame: CGRect
        /// True when the bubble was taller than available space and got clipped.
        let isClipped: Bool
        /// Vertical delta applied to the original bubble frame.
        let bubbleOffsetY: CGFloat
    }

    /// Places reaction bar above and action menu below the bubble, shifting the bubble
    /// when there is not enough room inside `safeArea`.
    static func resolve(
        bubbleFrame: CGRect,
        safeArea: CGRect,
        barHeight: CGFloat = barEstimatedHeight,
        menuHeight: CGFloat,
        barWidth: CGFloat,
        menuWidth: CGFloat = menuEstimatedWidth,
        isMine: Bool,
        spacing: CGFloat = spacing
    ) -> Placement {
        let usable = safeArea.insetBy(dx: horizontalInset, dy: spacing)
        let neededAbove = barHeight + barGap
        let neededBelow = menuHeight + spacing

        var bubble = bubbleFrame
        var clipped = false

        let maxBubbleHeight = max(80, usable.height - neededAbove - neededBelow)
        if bubble.height > maxBubbleHeight {
            bubble.size.height = maxBubbleHeight
            clipped = true
        }

        // Drop the bubble so the reaction bar occupies the slot it left.
        // Otherwise the bar is painted on top of the messages above it.
        var offsetY: CGFloat = neededAbove
        let bottomNeeded = bubble.maxY + offsetY + neededBelow
        if bottomNeeded > usable.maxY {
            offsetY -= bottomNeeded - usable.maxY
        }
        let topAfter = bubble.minY + offsetY - neededAbove
        if topAfter < usable.minY {
            offsetY += usable.minY - topAfter
        }
        let bottomAgain = bubble.maxY + offsetY + neededBelow
        if bottomAgain > usable.maxY {
            offsetY -= bottomAgain - usable.maxY
        }

        bubble.origin.y += offsetY

        let fittedBarWidth = min(barWidth, usable.width)
        let barX = clampedX(
            preferred: isMine ? bubble.maxX - fittedBarWidth : bubble.minX,
            width: fittedBarWidth,
            usable: usable
        )
        let barFrame = CGRect(
            x: barX,
            y: bubble.minY - barGap - barHeight,
            width: fittedBarWidth,
            height: barHeight
        )

        let fittedMenuWidth = min(menuWidth, usable.width)
        let menuX = clampedX(
            preferred: isMine ? bubble.maxX - fittedMenuWidth : bubble.minX,
            width: fittedMenuWidth,
            usable: usable
        )
        let menuFrame = CGRect(
            x: menuX,
            y: bubble.maxY + spacing,
            width: fittedMenuWidth,
            height: menuHeight
        )

        return Placement(
            bubbleFrame: bubble,
            barFrame: barFrame,
            menuFrame: menuFrame,
            isClipped: clipped,
            bubbleOffsetY: offsetY
        )
    }

    /// Keeps a horizontal span fully inside `usable`, even when the preferred edge hangs off-screen.
    static func clampedX(preferred: CGFloat, width: CGFloat, usable: CGRect) -> CGFloat {
        let fitted = min(max(width, 0), usable.width)
        return min(max(usable.minX, preferred), usable.maxX - fitted)
    }
}
