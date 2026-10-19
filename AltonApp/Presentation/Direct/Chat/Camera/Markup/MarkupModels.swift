import CoreGraphics
import Foundation
import UIKit

enum MarkupBrush: String, CaseIterable, Identifiable, Sendable, Equatable {
    case pen
    case marker
    case neon
    case eraser

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .neon: return "light.max"
        case .eraser: return "eraser"
        }
    }
}

enum MarkupTextFont: String, CaseIterable, Identifiable, Sendable, Equatable {
    case classic
    case rounded
    case serif
    case mono
    case strong
    case typewriter
    case elegant
    case handwriting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .strong: return "Strong"
        case .typewriter: return "Type"
        case .elegant: return "Elegant"
        case .handwriting: return "Hand"
        }
    }

    /// Single source of truth for screen + export fonts.
    func uiFont(size: CGFloat) -> UIFont {
        let fallback = UIFont.systemFont(ofSize: size, weight: .bold)
        switch self {
        case .classic:
            return fallback
        case .rounded:
            if let d = fallback.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: d, size: size)
            }
            return fallback
        case .serif:
            if let d = fallback.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: d, size: size)
            }
            return fallback
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: .bold)
        case .strong:
            return UIFont(name: "AvenirNextCondensed-Heavy", size: size) ?? fallback
        case .typewriter:
            return UIFont(name: "AmericanTypewriter-Semibold", size: size) ?? fallback
        case .elegant:
            return UIFont(name: "Didot-Bold", size: size) ?? fallback
        case .handwriting:
            return UIFont(name: "Noteworthy-Bold", size: size) ?? fallback
        }
    }
}

enum MarkupTextBackground: String, CaseIterable, Identifiable, Sendable, Equatable {
    case none
    case solid
    case translucent

    var id: String { rawValue }
}

enum MarkupTextAlignment: String, CaseIterable, Identifiable, Sendable, Equatable {
    case left
    case center
    case right

    var id: String { rawValue }
}

struct MarkupPoint: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct MarkupStroke: Identifiable, Equatable, Sendable {
    let id: UUID
    var brush: MarkupBrush
    /// Normalized width as fraction of canvas width (e.g. 0.02 = 2%).
    var widthNorm: CGFloat
    var colorHex: String
    /// Points in normalized 0...1 image space.
    var points: [MarkupPoint]
    /// Clean geometry when a freehand stroke snapped to a shape. Nil keeps the ink.
    var shape: MarkupVectorShape?

    init(
        id: UUID = UUID(),
        brush: MarkupBrush,
        widthNorm: CGFloat,
        colorHex: String,
        points: [MarkupPoint] = [],
        shape: MarkupVectorShape? = nil
    ) {
        self.id = id
        self.brush = brush
        self.widthNorm = widthNorm
        self.colorHex = colorHex
        self.points = points
        self.shape = shape
    }
}

/// Straightened stroke: line, arrow, rectangle, ellipse, triangle, or star.
struct MarkupVectorShape: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case line
        case arrow
        case rectangle
        case ellipse
        case triangle
        case star
    }

    var kind: Kind
    /// Normalized center, origin at the top-left (same space as stroke points).
    var center: MarkupPoint
    /// Width as a fraction of the canvas width, height as a fraction of the canvas height.
    var width: CGFloat
    var height: CGFloat
    /// Radians in view space, y pointing down.
    var rotation: CGFloat
    /// Arrow shaft bow, in pixels as a fraction of the canvas width.
    /// Positive bends to the left of the start→tip direction. Zero is straight.
    var bend: CGFloat = 0

    func path(in canvasSize: CGSize, flipsY: Bool) -> CGPath {
        let cx = center.x * canvasSize.width
        let cy = flipsY ? (1 - center.y) * canvasSize.height : center.y * canvasSize.height
        let pixelW = max(1, width * canvasSize.width)
        let pixelH = max(kind == .line || kind == .arrow ? 1 : pixelW * 0.2, height * canvasSize.height)
        let pixelBend = bend * canvasSize.width * (flipsY ? -1 : 1)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: cx, y: cy)
        transform = transform.rotated(by: flipsY ? -rotation : rotation)
        let local = Self.localPath(kind: kind, width: pixelW, height: pixelH, bend: pixelBend)
        return local.copy(using: &transform) ?? local
    }

    private static func localPath(kind: Kind, width: CGFloat, height: CGFloat, bend: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch kind {
        case .line:
            path.move(to: CGPoint(x: -width / 2, y: 0))
            path.addLine(to: CGPoint(x: width / 2, y: 0))
        case .arrow:
            let head = min(width * 0.34, max(18, width * 0.28))
            let spread = head * 0.62
            let start = CGPoint(x: -width / 2, y: 0)
            let tip = CGPoint(x: width / 2, y: 0)
            let control = CGPoint(x: 0, y: bend * 2)
            path.move(to: start)
            if abs(bend) < 0.5 {
                path.addLine(to: tip)
            } else {
                path.addQuadCurve(to: tip, control: control)
            }
            let tangentX = width
            let tangentY = -4 * bend
            let tangentLength = max(hypot(tangentX, tangentY), 0.001)
            let forwardX = tangentX / tangentLength
            let forwardY = tangentY / tangentLength
            let sideX = -forwardY
            let sideY = forwardX
            let neck = CGPoint(x: tip.x - forwardX * head, y: tip.y - forwardY * head)
            path.move(to: tip)
            path.addLine(to: CGPoint(x: neck.x + sideX * spread, y: neck.y + sideY * spread))
            path.move(to: tip)
            path.addLine(to: CGPoint(x: neck.x - sideX * spread, y: neck.y - sideY * spread))
        case .rectangle:
            path.addRect(CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        case .ellipse:
            path.addEllipse(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        case .triangle:
            path.move(to: CGPoint(x: 0, y: -height / 2))
            path.addLine(to: CGPoint(x: width / 2, y: height / 2))
            path.addLine(to: CGPoint(x: -width / 2, y: height / 2))
            path.closeSubpath()
        case .star:
            let outer = min(width, height) / 2
            let inner = outer * 0.4
            for index in 0..<10 {
                let radius = index.isMultiple(of: 2) ? outer : inner
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
        return path
    }
}

struct MarkupTextItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    /// Normalized center 0...1.
    var center: MarkupPoint
    var scale: CGFloat
    var rotation: CGFloat
    var colorHex: String
    var font: MarkupTextFont
    var background: MarkupTextBackground
    var alignment: MarkupTextAlignment
    /// Base font size as fraction of canvas width.
    var fontSizeNorm: CGFloat

    init(
        id: UUID = UUID(),
        text: String,
        center: MarkupPoint = MarkupPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotation: CGFloat = 0,
        colorHex: String = "#FFFFFF",
        font: MarkupTextFont = .classic,
        background: MarkupTextBackground = .none,
        alignment: MarkupTextAlignment = .center,
        fontSizeNorm: CGFloat = 0.07
    ) {
        self.id = id
        self.text = text
        self.center = center
        self.scale = scale
        self.rotation = rotation
        self.colorHex = colorHex
        self.font = font
        self.background = background
        self.alignment = alignment
        self.fontSizeNorm = fontSizeNorm
    }
}

struct MarkupSnapshot: Equatable, Sendable {
    var strokes: [MarkupStroke]
    var texts: [MarkupTextItem]
}

/// Document + undo/redo. Snapshots are cheap (CoW arrays); taken only at stroke/text commit.
struct MarkupDocument: Equatable, Sendable {
    static let maxHistory = 50

    var strokes: [MarkupStroke] = []
    var texts: [MarkupTextItem] = []

    private var undoStack: [MarkupSnapshot] = []
    private var redoStack: [MarkupSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { strokes.isEmpty && texts.isEmpty }

    mutating func beginMutation() {
        undoStack.append(MarkupSnapshot(strokes: strokes, texts: texts))
        if undoStack.count > Self.maxHistory {
            undoStack.removeFirst(undoStack.count - Self.maxHistory)
        }
        redoStack.removeAll(keepingCapacity: true)
    }

    mutating func appendStroke(_ stroke: MarkupStroke) {
        beginMutation()
        strokes.append(stroke)
    }

    mutating func upsertText(_ item: MarkupTextItem) {
        beginMutation()
        if let index = texts.firstIndex(where: { $0.id == item.id }) {
            texts[index] = item
        } else {
            texts.append(item)
        }
    }

    mutating func removeText(id: UUID) {
        guard texts.contains(where: { $0.id == id }) else { return }
        beginMutation()
        texts.removeAll { $0.id == id }
    }

    mutating func updateTextTransform(
        id: UUID,
        center: MarkupPoint,
        scale: CGFloat,
        rotation: CGFloat
    ) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return }
        beginMutation()
        texts[index].center = center
        texts[index].scale = scale
        texts[index].rotation = rotation
    }

    mutating func clearAll() {
        guard !isEmpty else { return }
        beginMutation()
        strokes.removeAll()
        texts.removeAll()
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(MarkupSnapshot(strokes: strokes, texts: texts))
        strokes = previous.strokes
        texts = previous.texts
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(MarkupSnapshot(strokes: strokes, texts: texts))
        strokes = next.strokes
        texts = next.texts
    }
}

enum MarkupPalette {
    static let swatches: [String] = [
        "#FFFFFF",
        "#000000",
        "#FF3B30",
        "#FF9500",
        "#FFCC00",
        "#34C759",
        "#007AFF",
        "#AF52DE",
        "#FF2D55",
        "#5AC8FA"
    ]

    static let defaultDrawColor = "#FFFFFF"
    static let defaultTextColor = "#FFFFFF"

    /// Width as fraction of canvas width. Maps UI slider 0...1 → ~0.004...0.06.
    static func widthNorm(fromSlider t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return 0.004 + clamped * 0.056
    }

    static func slider(fromWidthNorm w: CGFloat) -> CGFloat {
        min(max((w - 0.004) / 0.056, 0), 1)
    }
}
