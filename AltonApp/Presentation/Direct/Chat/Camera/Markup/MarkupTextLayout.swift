import CoreGraphics
import Foundation
import UIKit

/// Shared text metrics for screen layers and JPEG export (WYSIWYG).
enum MarkupTextLayout {
    struct Metrics: Equatable {
        var fontSize: CGFloat
        var maxWidth: CGFloat
        var padX: CGFloat
        var padY: CGFloat
        var corner: CGFloat
        var textSize: CGSize
        var boxSize: CGSize
        var font: UIFont
        var alignment: NSTextAlignment
    }

    static func measure(item: MarkupTextItem, canvasSize: CGSize) -> Metrics {
        let w = max(canvasSize.width, 1)
        // Scale is applied via CGAffine / scaleEffect — keep font metrics independent.
        let fontSize = max(10, item.fontSizeNorm * w)
        let maxWidth = w * 0.85
        let padX = item.background == .none ? 0 : fontSize * 0.3
        let padY = item.background == .none ? 0 : fontSize * 0.15
        let corner = fontSize * 0.25
        let font = item.font.uiFont(size: fontSize)

        let paragraph = NSMutableParagraphStyle()
        switch item.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let trimmed = item.text.isEmpty ? " " : item.text
        let ns = NSAttributedString(string: trimmed, attributes: attrs)
        let textRect = ns.boundingRect(
            with: CGSize(width: maxWidth, height: canvasSize.height * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let textSize = CGSize(width: ceil(textRect.width), height: ceil(textRect.height))
        let boxSize = CGSize(
            width: textSize.width + padX * 2,
            height: textSize.height + padY * 2
        )
        return Metrics(
            fontSize: fontSize,
            maxWidth: maxWidth,
            padX: padX,
            padY: padY,
            corner: corner,
            textSize: textSize,
            boxSize: boxSize,
            font: font,
            alignment: paragraph.alignment
        )
    }

    /// Single-line labels use a capsule; wrapped blocks keep the smaller corner.
    static func backgroundCorner(metrics: Metrics) -> CGFloat {
        if metrics.boxSize.height <= metrics.fontSize * 2.4 {
            return metrics.boxSize.height / 2
        }
        return metrics.corner
    }

    /// Axis-aligned bounds of the rotated + scaled text box in canvas points.
    static func axisAlignedBounds(item: MarkupTextItem, canvasSize: CGSize) -> CGRect {
        let m = measure(item: item, canvasSize: canvasSize)
        let cx = item.center.x * canvasSize.width
        let cy = item.center.y * canvasSize.height
        let hw = m.boxSize.width * item.scale / 2
        let hh = m.boxSize.height * item.scale / 2
        let corners = [
            CGPoint(x: -hw, y: -hh),
            CGPoint(x: hw, y: -hh),
            CGPoint(x: hw, y: hh),
            CGPoint(x: -hw, y: hh)
        ]
        let cosR = cos(item.rotation)
        let sinR = sin(item.rotation)
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for p in corners {
            let x = cx + p.x * cosR - p.y * sinR
            let y = cy + p.x * sinR + p.y * cosR
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Hit-test using the rotated box (local space).
    static func contains(point: CGPoint, item: MarkupTextItem, canvasSize: CGSize) -> Bool {
        let m = measure(item: item, canvasSize: canvasSize)
        let cx = item.center.x * canvasSize.width
        let cy = item.center.y * canvasSize.height
        let dx = point.x - cx
        let dy = point.y - cy
        let cosR = cos(-item.rotation)
        let sinR = sin(-item.rotation)
        let local = CGPoint(x: dx * cosR - dy * sinR, y: dx * sinR + dy * cosR)
        let hw = m.boxSize.width * item.scale / 2 + 8
        let hh = m.boxSize.height * item.scale / 2 + 8
        return abs(local.x) <= hw && abs(local.y) <= hh
    }

    /// Keep the AABB inside the canvas with an inset.
    static func clampCenter(
        _ center: MarkupPoint,
        item: MarkupTextItem,
        canvasSize: CGSize,
        inset: CGFloat = 8
    ) -> MarkupPoint {
        var probe = item
        probe.center = center
        let bounds = axisAlignedBounds(item: probe, canvasSize: canvasSize)
        var cx = center.x * canvasSize.width
        var cy = center.y * canvasSize.height
        let halfW = bounds.width / 2
        let halfH = bounds.height / 2
        cx = min(max(cx, inset + halfW), canvasSize.width - inset - halfW)
        cy = min(max(cy, inset + halfH), canvasSize.height - inset - halfH)
        return MarkupPoint(
            x: cx / max(canvasSize.width, 1),
            y: cy / max(canvasSize.height, 1)
        )
    }
}

enum MarkupTextSnap {
    static let centerThreshold: CGFloat = 6
    static let angleThresholdDegrees: CGFloat = 4

    struct Result: Equatable {
        var center: MarkupPoint
        var rotation: CGFloat
        var showVerticalGuide: Bool
        var showHorizontalGuide: Bool
        var didSnap: Bool
    }

    static func apply(
        center: MarkupPoint,
        rotation: CGFloat,
        canvasSize: CGSize,
        previouslySnapped: Bool
    ) -> Result {
        var cx = center.x * canvasSize.width
        var cy = center.y * canvasSize.height
        var showV = false
        var showH = false
        var didSnap = false

        let midX = canvasSize.width / 2
        let midY = canvasSize.height / 2
        if abs(cx - midX) <= centerThreshold {
            cx = midX
            showV = true
            didSnap = true
        }
        if abs(cy - midY) <= centerThreshold {
            cy = midY
            showH = true
            didSnap = true
        }

        var rot = rotation
        let degrees = rot * 180 / .pi
        if abs(degrees) <= angleThresholdDegrees || abs(abs(degrees) - 360) <= angleThresholdDegrees {
            rot = 0
            didSnap = true
        }

        return Result(
            center: MarkupPoint(x: cx / max(canvasSize.width, 1), y: cy / max(canvasSize.height, 1)),
            rotation: rot,
            showVerticalGuide: showV,
            showHorizontalGuide: showH,
            didSnap: didSnap && !previouslySnapped
        )
    }
}

enum MarkupTextPreferences {
    private static let key = "dm.markup.textStyle"

    struct Style: Equatable, Codable {
        var colorHex: String
        var font: String
        var background: String
        var alignment: String
        var fontSizeNorm: CGFloat
    }

    static func load(defaults: UserDefaults = .standard) -> Style {
        guard let data = defaults.data(forKey: key),
              let style = try? JSONDecoder().decode(Style.self, from: data) else {
            return Style(
                colorHex: MarkupPalette.defaultTextColor,
                font: MarkupTextFont.classic.rawValue,
                background: MarkupTextBackground.none.rawValue,
                alignment: MarkupTextAlignment.center.rawValue,
                fontSizeNorm: 0.07
            )
        }
        return style
    }

    static func save(_ style: Style, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(style) {
            defaults.set(data, forKey: key)
        }
    }

    static func save(from item: MarkupTextItem, defaults: UserDefaults = .standard) {
        save(
            Style(
                colorHex: item.colorHex,
                font: item.font.rawValue,
                background: item.background.rawValue,
                alignment: item.alignment.rawValue,
                fontSizeNorm: item.fontSizeNorm
            ),
            defaults: defaults
        )
    }

    static func apply(to item: inout MarkupTextItem, defaults: UserDefaults = .standard) {
        let style = load(defaults: defaults)
        item.colorHex = style.colorHex
        item.font = MarkupTextFont(rawValue: style.font) ?? .classic
        item.background = MarkupTextBackground(rawValue: style.background) ?? .none
        item.alignment = MarkupTextAlignment(rawValue: style.alignment) ?? .center
        item.fontSizeNorm = style.fontSizeNorm
    }
}
