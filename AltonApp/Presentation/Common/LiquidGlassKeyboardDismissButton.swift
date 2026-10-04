import SwiftUI
import UIKit

/// Controller tracking keyboard visibility and height for floating dismiss controls.
///
/// When `keyboardWillShowNotification` is received without a valid frame in its `userInfo`,
/// `isKeyboardVisible` is set to `true` while `keyboardHeight` resets to `0`.
@MainActor @Observable final class KeyboardDismissController {
    var isKeyboardVisible = false
    var keyboardHeight: CGFloat = 0
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    init() {
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            self.isKeyboardVisible = true
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                self.keyboardHeight = frame.height
            } else {
                self.keyboardHeight = 0
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.isKeyboardVisible = false
            self.keyboardHeight = 0
        })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    func dismiss() { KeyboardDismiss.dismiss() }
}

struct LiquidGlassKeyboardDismissButton: View {
    let controller: KeyboardDismissController
    var body: some View {
        if controller.isKeyboardVisible {
            Button { controller.dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                    Text("Done").font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(Color(#colorLiteral(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)))
                .background(.ultraThinMaterial, in: Capsule().inset(by: 0.5))
                .overlay(Capsule().inset(by: 0.5).strokeBorder(Color(#colorLiteral(red: 0.92, green: 0.93, blue: 0.94, alpha: 1)), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss keyboard")
        }
    }
}

extension View {
    /// Overlays the glass Done button at bottom-trailing, lifted by `keyboardHeight + bottomInset`
    /// so it floats just above the keyboard's top edge (and above any bottom composer bar). Hidden when keyboard is down.
    ///
    /// The overlay content ignores the keyboard safe area (`.ignoresSafeArea(.keyboard)`) so that
    /// the explicit `-(controller.keyboardHeight + bottomInset) - 8` offset correctly positions the button just above
    /// the keyboard top edge (or bottom composer bar) regardless of whether the host view handles or ignores keyboard safe area.
    func liquidGlassKeyboardDismiss(
        controller: KeyboardDismissController,
        bottomInset: CGFloat = 0
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            LiquidGlassKeyboardDismissButton(controller: controller)
                .padding(.trailing, 12)
                .offset(y: -(controller.keyboardHeight + bottomInset) - 8)
                .allowsHitTesting(controller.isKeyboardVisible)
                .animation(.easeInOut(duration: 0.25), value: controller.keyboardHeight)
                .ignoresSafeArea(.keyboard)
        }
    }
}

#Preview {
    let controller = KeyboardDismissController()
    controller.isKeyboardVisible = true
    controller.keyboardHeight = 300
    return ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        LiquidGlassKeyboardDismissButton(controller: controller)
    }
}
