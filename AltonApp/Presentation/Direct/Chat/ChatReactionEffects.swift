import SwiftUI
import UIKit

enum ChatReactionHaptics {
    static func longPressArmed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func reactionSelected() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func actionSelected() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func doubleTapHeart() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private static let selection = UISelectionFeedbackGenerator()

    static func selectionChanged() {
        selection.selectionChanged()
    }
}

/// Scale pop for newly applied reaction badges.
struct ReactionBadgePopModifier: ViewModifier {
    /// Increments each time this badge should pop. `0` means no pop.
    let trigger: Int

    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                guard trigger != 0 else { return }
                runPop()
            }
            .onChange(of: trigger) { _, newValue in
                guard newValue != 0 else { return }
                runPop()
            }
    }

    private func runPop() {
        scale = 0.01
        withAnimation(ChatContextMotion.bounce(damping: 72, duration: 0.28)) {
            scale = 1.35
        }
        withAnimation(
            ChatContextMotion.bounce(damping: 88, duration: 0.28).delay(0.14)
        ) {
            scale = 1
        }
    }
}

extension View {
    func reactionBadgePop(trigger: Int) -> some View {
        modifier(ReactionBadgePopModifier(trigger: trigger))
    }
}

/// Heart that pops over a bubble on double-tap.
struct DoubleTapHeartOverlay: View {
    @State private var scale: CGFloat = 0.92
    @State private var opacity: Double = 0

    var body: some View {
        Text("❤️")
            .font(.system(size: 56))
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .allowsHitTesting(false)
            .onAppear {
                ChatReactionHaptics.doubleTapHeart()
                withAnimation(.smooth(duration: 0.16, extraBounce: 0)) {
                    opacity = 1
                    scale = 1
                }
                withAnimation(.smooth(duration: 0.18, extraBounce: 0).delay(0.18)) {
                    opacity = 0
                    scale = 1.04
                }
            }
    }
}
