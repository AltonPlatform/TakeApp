import CoreGraphics
import CoreText
import Foundation
import UIKit
import os

enum MarkupRenderer {
    private static let signposter = OSSignposter(
        logger: Logger(subsystem: Bundle.main.bundleIdentifier ?? "AltonApp", category: "DMMarkup")
    )

    // MARK: - Public

    /// Draw ink + text into an existing context. Context must be raw Quartz (y-up, no CTM flip).
    /// Coordinates: normalized document → pixel space of `size` (width × height).
    static func draw(document: MarkupDocument, in ctx: CGContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let state = signposter.beginInterval("dm.markup.rerender")
        defer { signposter.endInterval("dm.markup.rerender", state) }

        ctx.saveGState()
        drawStrokes(document.strokes, in: ctx, size: size)
        ctx.restoreGState()

        ctx.saveGState()
        // Text uses UIKit-style top-left via a single CTM flip for attributed strings.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        for item in document.texts {
            drawText(item, in: ctx, size: size)
        }
        ctx.restoreGState()
    }

    /// Draw a single stroke (used for incremental ink commit).
    static func drawStroke(_ stroke: MarkupStroke, in ctx: CGContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        drawStrokes([stroke], in: ctx, size: size)
    }

    /// Composite base photo + markup into a new CGImage (export path).
    static func renderExport(base: CGImage, document: MarkupDocument) -> CGImage? {
        let state = signposter.beginInterval("dm.markup.export")
        defer { signposter.endInterval("dm.markup.export", state) }

        let w = base.width
        let h = base.height
        guard let ctx = CPUImageIO.makeBitmapContext(width: w, height: h) else { return nil }
        let size = CGSize(width: w, height: h)
        ctx.draw(base, in: CGRect(origin: .zero, size: size))
        draw(document: document, in: ctx, size: size)
        return ctx.makeImage()
    }

    /// Build a CGPath for live preview (CAShapeLayer). Points must already be in view points.
    static func livePath(points: [CGPoint]) -> CGPath {
        smoothedPath(points: points)
    }

    // MARK: - Strokes

    private static func drawStrokes(_ strokes: [MarkupStroke], in ctx: CGContext, size: CGSize) {
        for stroke in strokes {
            let points = stroke.points.map { p in
                CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
            }
            guard !points.isEmpty else { continue }
            let width = max(1, stroke.widthNorm * size.width)
            let color = cgColor(hex: stroke.colorHex) ?? CGColor(gray: 1, alpha: 1)

            if let shape = stroke.shape {
                drawVectorShape(shape, stroke: stroke, in: ctx, size: size)
                continue
            }

            switch stroke.brush {
            case .pen:
                strokePath(points: points, width: width, color: color, alpha: 1, in: ctx)
            case .marker:
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                strokePath(points: points, width: width * 1.6, color: color, alpha: 0.45, in: ctx)
                ctx.endTransparencyLayer()
            case .neon:
                strokePath(points: points, width: width * 3.2, color: color, alpha: 0.25, in: ctx)
                strokePath(points: points, width: width * 1.8, color: color, alpha: 0.6, in: ctx)
                strokePath(
                    points: points,
                    width: width * 0.7,
                    color: CGColor(gray: 1, alpha: 1),
                    alpha: 1,
                    in: ctx
                )
            case .eraser:
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                strokePath(
                    points: points,
                    width: width * 2.2,
                    color: CGColor(gray: 0, alpha: 1),
                    alpha: 1,
                    in: ctx
                )
                ctx.restoreGState()
            }
        }
    }

    private static func drawVectorShape(
        _ shape: MarkupVectorShape,
        stroke: MarkupStroke,
        in ctx: CGContext,
        size: CGSize
    ) {
        let width = max(1, stroke.widthNorm * size.width)
        let color = cgColor(hex: stroke.colorHex) ?? CGColor(gray: 1, alpha: 1)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(shape.path(in: size, flipsY: true))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func strokePath(
        points: [CGPoint],
        width: CGFloat,
        color: CGColor,
        alpha: CGFloat,
        in ctx: CGContext
    ) {
        guard let first = points.first else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.copy(alpha: alpha) ?? color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setMiterLimit(2)
        let path = smoothedPath(points: points)
        if points.count == 1 {
            ctx.setFillColor(color.copy(alpha: alpha) ?? color)
            let r = width / 2
            ctx.fillEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: width, height: width))
        } else {
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Quadratic mid-point smoothing. Works for both Quartz (y-up) and UIKit (y-down) point spaces.
    static func smoothedPath(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        if points.count == 1 {
            path.move(to: first)
            return path
        }
        path.move(to: first)
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 1..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    // MARK: - Text

    private static func drawText(_ item: MarkupTextItem, in ctx: CGContext, size: CGSize) {
        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let metrics = MarkupTextLayout.measure(item: item, canvasSize: size)
        let center = CGPoint(x: item.center.x * size.width, y: item.center.y * size.height)
        let color = UIColor(markupHex: item.colorHex) ?? .white

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = metrics.alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: metrics.font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let ns = NSAttributedString(string: trimmed, attributes: attrs)
        let box = CGRect(
            x: center.x - metrics.boxSize.width / 2,
            y: center.y - metrics.boxSize.height / 2,
            width: metrics.boxSize.width,
            height: metrics.boxSize.height
        )

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: item.rotation)
        ctx.scaleBy(x: item.scale, y: item.scale)
        ctx.translateBy(x: -center.x, y: -center.y)

        switch item.background {
        case .none:
            break
        case .solid:
            ctx.setFillColor(UIColor.black.cgColor)
            let radius = MarkupTextLayout.backgroundCorner(metrics: metrics)
            let path = CGPath(
                roundedRect: box,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            ctx.addPath(path)
            ctx.fillPath()
        case .translucent:
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            let radius = MarkupTextLayout.backgroundCorner(metrics: metrics)
            let path = CGPath(
                roundedRect: box,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            ctx.addPath(path)
            ctx.fillPath()
        }

        let drawOrigin = CGPoint(x: box.minX + metrics.padX, y: box.minY + metrics.padY)
        UIGraphicsPushContext(ctx)
        ns.draw(
            with: CGRect(origin: drawOrigin, size: metrics.textSize),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        UIGraphicsPopContext()

        ctx.restoreGState()
    }

    static func cgColor(hex: String) -> CGColor? {
        UIColor(markupHex: hex)?.cgColor
    }
}

extension UIColor {
    convenience init?(markupHex: String) {
        var cleaned = markupHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func markupHexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255)
        )
    }
}
