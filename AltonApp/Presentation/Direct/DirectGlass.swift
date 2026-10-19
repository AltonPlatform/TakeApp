import SwiftUI

/// Shared Liquid Glass helpers for Direct (iOS 26+) with material fallbacks for iOS 18–25.
struct DirectGlassContainer<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func directGlass<S: Shape>(
        _ shape: S,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Self.directMakeGlass(interactive: interactive, tint: tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @available(iOS 26, *)
    private static func directMakeGlass(interactive: Bool, tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }

    @ViewBuilder
    func directGlassID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Materialize glass on appear/disappear (iOS 26+); no-op otherwise.
    @ViewBuilder
    func directGlassTransition() -> some View {
        if #available(iOS 26, *) {
            self.glassEffectTransition(.materialize)
        } else {
            self
        }
    }

    @ViewBuilder
    func directGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.plain)
        }
    }

    /// Floating composer. No opaque fill: the glass field sits on the chat, not on a white slab.
    @ViewBuilder
    func directBottomBar<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            bar()
        }
    }
}
