import SwiftUI

/// Visual text sticker. Gestures live in `MarkupTextGestureView`.
struct MarkupTextLayer: View {
    let item: MarkupTextItem
    let canvasSize: CGSize
    var liveCenter: MarkupPoint?
    var liveScale: CGFloat?
    var liveRotation: CGFloat?
    var isHidden: Bool = false
    var trashHoverScale: CGFloat = 1
    /// Non-nil while the sticker is flying into the trash.
    var motionAnimation: Animation? = nil

    var body: some View {
        let center = liveCenter ?? item.center
        let scale = liveScale ?? item.scale
        let rotation = liveRotation ?? item.rotation
        let metrics = MarkupTextLayout.measure(item: item, canvasSize: canvasSize)

        textLabel(metrics: metrics)
            .scaleEffect(scale * trashHoverScale)
            .rotationEffect(.radians(rotation))
            .position(
                x: center.x * canvasSize.width,
                y: center.y * canvasSize.height
            )
            .animation(motionAnimation, value: center.x)
            .animation(motionAnimation, value: center.y)
            .animation(motionAnimation, value: scale)
            .animation(motionAnimation, value: rotation)
            .opacity(isHidden ? 0 : 1)
            .accessibilityLabel(item.text)
            .allowsHitTesting(false)
    }

    private func textLabel(metrics: MarkupTextLayout.Metrics) -> some View {
        Text(item.text)
            .font(Font(metrics.font))
            .foregroundStyle(Color(markupHex: item.colorHex) ?? .white)
            .multilineTextAlignment(textAlignment)
            .padding(.horizontal, metrics.padX)
            .padding(.vertical, metrics.padY)
            .frame(width: metrics.boxSize.width, alignment: frameAlignment)
            .background {
                if item.background != .none {
                    RoundedRectangle(
                        cornerRadius: MarkupTextLayout.backgroundCorner(metrics: metrics),
                        style: .continuous
                    )
                    .fill(item.background == .solid ? Color.black : Color.black.opacity(0.45))
                }
            }
    }

    private var textAlignment: TextAlignment {
        switch item.alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch item.alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

struct MarkupTrashTarget: View {
    var isActive: Bool
    var isHovering: Bool
    var isSwallowing: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: 56, height: 56)
                .scaleEffect(isSwallowing ? 1.85 : 1)
                .opacity(isSwallowing ? 0 : (isActive ? 0.9 : 0))

            Image(systemName: isHovering || isSwallowing ? "trash.fill" : "trash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(isHovering || isSwallowing ? Color.red.opacity(0.92) : Color.white.opacity(0.18))
                )
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                }
        }
        .scaleEffect(isSwallowing ? 1.18 : (isHovering ? 1.28 : (isActive ? 1 : 0.72)))
        .opacity(isActive ? 1 : 0)
        .offset(y: isActive ? 0 : 28)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isHovering)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isActive)
        .animation(.easeOut(duration: 0.42), value: isSwallowing)
    }
}

struct MarkupSnapGuides: View {
    var showVertical: Bool
    var showHorizontal: Bool
    var canvasSize: CGSize

    var body: some View {
        ZStack {
            if showVertical {
                Rectangle()
                    .fill(Color.yellow.opacity(0.85))
                    .frame(width: 1, height: canvasSize.height)
                    .position(x: canvasSize.width / 2, y: canvasSize.height / 2)
            }
            if showHorizontal {
                Rectangle()
                    .fill(Color.yellow.opacity(0.85))
                    .frame(width: canvasSize.width, height: 1)
                    .position(x: canvasSize.width / 2, y: canvasSize.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}
