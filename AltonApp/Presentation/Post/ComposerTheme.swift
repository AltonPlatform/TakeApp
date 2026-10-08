import SwiftUI
import UIKit

// MARK: - Adaptive hex helpers

private extension UIColor {
    /// `#rrggbb` (leading `#` optional). Falls back to clear on malformed input.
    convenience init(composerHex hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        guard trimmed.count == 6, Scanner(string: trimmed).scanHexInt64(&value) else {
            self.init(white: 0, alpha: 0)
            return
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension UIColor {
    /// Adaptive color from a light/dark `#rrggbb` pair (dynamic provider).
    static func composerAdaptive(light: String, dark: String) -> UIColor {
        let lightColor = UIColor(composerHex: light)
        let darkColor = UIColor(composerHex: dark)
        return UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor }
    }
}

extension Color {
    /// Adaptive color from a light/dark `#rrggbb` pair.
    static func hex(_ light: String, dark: String) -> Color {
        Color(uiColor: .composerAdaptive(light: light, dark: dark))
    }
}

// MARK: - ComposerPalette

/// Single source of truth for the take-composer monochrome tokens.
/// Every token is adaptive (light/dark) and none is system blue.
struct ComposerPalette {
    /// Ink: text, icons, solid fills. Light `#1c1c1e` / dark `#f5f5f7`.
    let primary: Color
    /// Secondary text / dimmed controls. Light `#a0a3ab` / dark `#8e8e93`.
    let secondary: Color
    /// Hairlines and borders. Light `#eaecf0` / dark `#2c2c2e`.
    let divider: Color
    /// Active-toggle / tile fill. Light `#eaecf0` / dark `#2c2c2e`.
    let activeFill: Color
    /// Interactive accent (replaces system blue). Light `#1c1c1e` / dark `#f5f5f7`.
    let accent: Color
    /// Content drawn on top of `primary` fills — inverse of ink. Light `#ffffff` / dark `#1c1c1e`.
    let onPrimary: Color
    /// Muted glyph/label on `activeFill` tiles (attachment "Add"). Light `#8d939c` / dark `#8e8e93`.
    let muted: Color

    static let monochrome = ComposerPalette(
        primary: .hex("#1c1c1e", dark: "#f5f5f7"),
        secondary: .hex("#a0a3ab", dark: "#8e8e93"),
        divider: .hex("#eaecf0", dark: "#2c2c2e"),
        activeFill: .hex("#eaecf0", dark: "#2c2c2e"),
        accent: .hex("#1c1c1e", dark: "#f5f5f7"),
        onPrimary: .hex("#ffffff", dark: "#1c1c1e"),
        muted: .hex("#8d939c", dark: "#8e8e93")
    )
}

/// Mention text color inside the rich-text editor (monochrome ink, never `UIColor.link`).
enum ComposerMentionStyle {
    static let uiColor: UIColor = .composerAdaptive(light: "#1c1c1e", dark: "#f5f5f7")
}
