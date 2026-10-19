import SwiftUI

/// Non-observable registry of badge frames so scroll does not re-render bubbles.
final class ChatFrameRegistry {
    private var badgeFrames: [String: [String: CGRect]] = [:]
    private var bubbleFrames: [String: CGRect] = [:]

    func setBadgeFrame(messageID: String, emoji: String, frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        var map = badgeFrames[messageID] ?? [:]
        map[emoji] = frame
        badgeFrames[messageID] = map
    }

    func badgeFrame(messageID: String, emoji: String) -> CGRect? {
        badgeFrames[messageID]?[emoji]
    }

    func setBubbleFrame(messageID: String, frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        bubbleFrames[messageID] = frame
    }

    func bubbleFrame(messageID: String) -> CGRect? {
        bubbleFrames[messageID]
    }

    /// Fallback landing spot under the bubble when the badge is not laid out yet.
    func predictedBadgeCenter(messageID: String, isMine: Bool) -> CGPoint? {
        guard let bubble = bubbleFrames[messageID] else { return nil }
        let x = isMine ? bubble.maxX - 18 : bubble.minX + 18
        let y = bubble.maxY + 14
        return CGPoint(x: x, y: y)
    }
}

/// Box that holds a CGRect without triggering SwiftUI observation.
final class FrameBox {
    var frame: CGRect = .zero
}

struct ReactionFlight: Identifiable, Equatable {
    let id: UUID
    let emoji: String
    let messageID: String
    let source: CGRect
    let target: CGRect
    let isLarge: Bool

    init(
        id: UUID = UUID(),
        emoji: String,
        messageID: String,
        source: CGRect,
        target: CGRect,
        isLarge: Bool = false
    ) {
        self.id = id
        self.emoji = emoji
        self.messageID = messageID
        self.source = source
        self.target = target
        self.isLarge = isLarge
    }
}

struct ReactionBigEffect: Identifiable, Equatable {
    let id: UUID
    let emoji: String
    let messageID: String
    let isMine: Bool
    let source: CGRect
    let bubbleCenter: CGPoint

    init(
        id: UUID = UUID(),
        emoji: String,
        messageID: String,
        isMine: Bool,
        source: CGRect,
        bubbleCenter: CGPoint
    ) {
        self.id = id
        self.emoji = emoji
        self.messageID = messageID
        self.isMine = isMine
        self.source = source
        self.bubbleCenter = bubbleCenter
    }
}

/// Parabolic flight path ported from Telegram `generateParabollicMotionKeyframes`.
enum ReactionFlightPath {
    static let elevation: CGFloat = 30

    static func point(from source: CGPoint, to target: CGPoint, t: CGFloat, elevation: CGFloat = elevation) -> CGPoint {
        let clamped = min(1, max(0, t))
        if abs(source.y - target.y) < 5, abs(source.x - target.x) < 5 {
            return CGPoint(
                x: source.x + (target.x - source.x) * clamped,
                y: source.y + (target.y - source.y) * clamped
            )
        }
        let mid = CGPoint(x: (source.x + target.x) / 2, y: source.y - elevation)
        let x1 = source.x, y1 = source.y
        let x2 = mid.x, y2 = mid.y
        let x3 = target.x, y3 = target.y
        let denom = (x1 - x2) * (x1 - x3) * (x2 - x3)
        guard abs(denom) > 0.001 else {
            return CGPoint(
                x: source.x + (target.x - source.x) * clamped,
                y: source.y + (target.y - source.y) * clamped
            )
        }
        let a = (x3 * (y2 - y1) + x2 * (y1 - y3) + x1 * (y3 - y2)) / denom
        let b = (x3 * x3 * (y1 - y2) + x2 * x2 * (y3 - y1) + x1 * x1 * (y2 - y3)) / denom
        let c = (x2 * x3 * (x2 - x3) * y1 + x3 * x1 * (x3 - x1) * y2 + x1 * x2 * (x1 - x2) * y3) / denom
        let x = source.x + (target.x - source.x) * clamped
        let y = a * x * x + b * x + c
        return CGPoint(x: x, y: y)
    }

    /// Peak y for tests: midpoint of the parabola at t=0.5.
    static func peakY(from source: CGPoint, to target: CGPoint, elevation: CGFloat = elevation) -> CGFloat {
        point(from: source, to: target, t: 0.5, elevation: elevation).y
    }
}

struct ReactionFlightLayer: View {
    let flight: ReactionFlight
    var onComplete: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global)
            let sourceCenter = CGPoint(x: flight.source.midX, y: flight.source.midY)
            let targetCenter = CGPoint(x: flight.target.midX, y: flight.target.midY)
            let point = ReactionFlightPath.point(from: sourceCenter, to: targetCenter, t: progress)
            let local = CGPoint(x: point.x - origin.minX, y: point.y - origin.minY)
            let startSize = max(flight.source.width, flight.source.height, 28)
            // Telegram insets target by -50% → roughly 2× badge size mid-flight.
            let endSize = max(flight.target.width, flight.target.height, 22) * 2
            let size = startSize + (endSize - startSize) * progress

            Text(flight.emoji)
                .font(.system(size: size * 0.78))
                .frame(width: size, height: size)
                .position(local)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: ChatContextMotion.reactionFlightDuration)) {
                progress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + ChatContextMotion.reactionFlightDuration) {
                onComplete()
            }
        }
    }
}

/// Large emoji pop above the bubble before parabolic flight (charged reaction).
struct ReactionBigEffectView: View {
    let effect: ReactionBigEffect
    var onComplete: () -> Void

    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 1

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global)
            Text(effect.emoji)
                .font(.system(size: 72))
                .scaleEffect(scale)
                .opacity(opacity)
                .position(
                    x: effect.bubbleCenter.x - origin.minX,
                    y: effect.bubbleCenter.y - origin.minY - 8
                )
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(ChatContextMotion.bounce(damping: 72, duration: 0.32)) {
                scale = 2.4
            }
            let hold = ChatContextMotion.bigEffectHoldDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32 + hold) {
                withAnimation(.easeIn(duration: 0.08)) {
                    opacity = 0
                }
                onComplete()
            }
        }
    }
}

/// Lightweight stand-in for Telegram's Lottie around-animation.
struct ReactionBurstView: View {
    let emoji: String
    var particleCount: Int = 6
    var radius: CGFloat = 28
    var onFinished: (() -> Void)? = nil

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                let angle = (Double(index) / Double(particleCount)) * .pi * 2
                let distance: CGFloat = radius * 0.7 + CGFloat(index % 2) * (radius * 0.3)
                Text(emoji)
                    .font(.system(size: particleCount > 6 ? 16 : 12))
                    .opacity(Double(1 - progress))
                    .scaleEffect(1 - progress * 0.4)
                    .offset(
                        x: cos(angle) * distance * progress,
                        y: sin(angle) * distance * progress
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                progress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onFinished?()
            }
        }
    }
}
