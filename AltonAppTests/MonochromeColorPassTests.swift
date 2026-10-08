import SwiftUI
import UIKit
import XCTest
@testable import AltonApp

final class MonochromeColorPassTests: XCTestCase {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    private func hex(_ color: Color, _ traits: UITraitCollection) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func testPaletteIsAdaptiveWithApprovedValues() {
        let p = ComposerPalette.monochrome
        XCTAssertEqual(hex(p.primary, light), "#1c1c1e")
        XCTAssertEqual(hex(p.primary, dark), "#f5f5f7")
        XCTAssertEqual(hex(p.divider, light), "#eaecf0")
        XCTAssertEqual(hex(p.divider, dark), "#2c2c2e")
        XCTAssertEqual(hex(p.secondary, light), "#a0a3ab")
        XCTAssertEqual(hex(p.secondary, dark), "#8e8e93")
        XCTAssertEqual(hex(p.activeFill, light), "#eaecf0")
        XCTAssertEqual(hex(p.activeFill, dark), "#2c2c2e")
        XCTAssertEqual(hex(p.accent, light), "#1c1c1e")
        XCTAssertEqual(hex(p.accent, dark), "#f5f5f7")
        XCTAssertEqual(hex(p.onPrimary, light), "#ffffff")
        XCTAssertEqual(hex(p.onPrimary, dark), "#1c1c1e")
    }

    func testNoSystemBlueInEitherAppearance() {
        let p = ComposerPalette.monochrome
        for traits in [light, dark] {
            let blues = [hex(.blue, traits), hex(Color(uiColor: .systemBlue), traits), hex(.accentColor, traits)]
            for token in [p.primary, p.secondary, p.divider, p.activeFill, p.accent, p.onPrimary, p.muted] {
                XCTAssertFalse(blues.contains(hex(token, traits)), "palette token resolved to system blue")
            }
        }
    }

    func testMentionAttributeColorIsMonochromeAdaptive() {
        let color = ComposerMentionStyle.uiColor
        XCTAssertEqual(color.resolvedColor(with: light), UIColor(ComposerPalette.monochrome.primary).resolvedColor(with: light))
        XCTAssertEqual(color.resolvedColor(with: dark), UIColor(ComposerPalette.monochrome.primary).resolvedColor(with: dark))
        XCTAssertNotEqual(color.resolvedColor(with: light), UIColor.link.resolvedColor(with: light))
    }
}
