import QuartzCore
import SwiftUI
import UIKit
import os

/// High-performance ink canvas: committed strokes in a CPU bitmap (`inkLayer`),
/// live stroke as `CAShapeLayer` path updates. No Core Image / Metal / PencilKit.
final class MarkupDrawingView: UIView {
    var brush: MarkupBrush = .pen
    var colorHex: String = MarkupPalette.defaultDrawColor
    /// UI slider 0...1.
    var widthSlider: CGFloat = 0.35
    var isDrawingEnabled = true

    var onStrokeCommitted: ((MarkupStroke) -> Void)?
    var onNeedsFullRerender: (() -> MarkupDocument)?

    private let inkLayer = CALayer()
    private let liveGlow = CAShapeLayer()
    private let liveMid = CAShapeLayer()
    private let liveCore = CAShapeLayer()

    private var inkContext: CGContext?
    private var inkWidth = 0
    private var inkHeight = 0
    private var inkScale: CGFloat = 1

    private var activePoints: [CGPoint] = []
    private var lastAccepted: CGPoint?
    private var displayLink: CADisplayLink?
    private var eraserDirty = false

    private let minPointDistance: CGFloat = 1.5
    private let maxPointsPerStroke = 4000
    private let signposter = OSSignposter(
        logger: Logger(subsystem: Bundle.main.bundleIdentifier ?? "AltonApp", category: "DMMarkup")
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        isOpaque = false
        inkLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer.addSublayer(inkLayer)
        configureLive(liveGlow)
        configureLive(liveMid)
        configureLive(liveCore)
        layer.addSublayer(liveGlow)
        layer.addSublayer(liveMid)
        layer.addSublayer(liveCore)
        clearLive()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        inkLayer.frame = bounds
        liveGlow.frame = bounds
        liveMid.frame = bounds
        liveCore.frame = bounds
        ensureInkBuffer()
    }

    /// Full rebuild from document (undo/redo/crop).
    func reload(from document: MarkupDocument) {
        ensureInkBuffer()
        guard let ctx = inkContext, inkWidth > 0, inkHeight > 0 else { return }
        let state = signposter.beginInterval("dm.markup.rerender")
        ctx.clear(CGRect(x: 0, y: 0, width: inkWidth, height: inkHeight))
        let size = CGSize(width: inkWidth, height: inkHeight)
        MarkupRenderer.drawStrokeBatch(document.strokes, in: ctx, size: size)
        // Texts are drawn in SwiftUI overlay — ink layer is strokes only.
        publishInk(clearingLive: true)
        signposter.endInterval("dm.markup.rerender", state)
    }

    func clearInk() {
        inkContext?.clear(CGRect(x: 0, y: 0, width: inkWidth, height: inkHeight))
        publishInk(clearingLive: true)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, let touch = touches.first else { return }
        activePoints.removeAll(keepingCapacity: true)
        lastAccepted = nil
        eraserDrawnCount = 0
        appendCoalesced(from: touch, event: event)
        updateLivePath()
        if brush == .eraser {
            startDisplayLink()
            eraseActiveSegment()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, let touch = touches.first, !activePoints.isEmpty else { return }
        appendCoalesced(from: touch, event: event)
        updateLivePath()
        if brush == .eraser {
            eraseActiveSegment()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, let touch = touches.first else { return }
        appendCoalesced(from: touch, event: event)
        // Bake the path already on screen. Do not rebuild or re-smooth it.
        updateLivePath()
        commitStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activePoints.removeAll()
        lastAccepted = nil
        clearLive()
        stopDisplayLink()
        if brush == .eraser {
            publishInk(clearingLive: false)
        }
    }

    // MARK: - Private

    private func configureLive(_ layer: CAShapeLayer) {
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.contentsScale = UIScreen.main.scale
        // SwiftUI animates layer changes on touch-up. That fade is the flicker.
        layer.actions = [
            "path": NSNull(),
            "strokeColor": NSNull(),
            "fillColor": NSNull(),
            "lineWidth": NSNull(),
            "opacity": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]
    }

    private func ensureInkBuffer() {
        let scale = min(UIScreen.main.scale, 2)
        let w = max(1, Int((bounds.width * scale).rounded()))
        let h = max(1, Int((bounds.height * scale).rounded()))
        guard w != inkWidth || h != inkHeight || inkContext == nil || abs(scale - inkScale) > 0.01 else {
            return
        }
        inkScale = scale
        inkWidth = w
        inkHeight = h
        inkContext = CPUImageIO.makeClearBitmapContext(width: w, height: h)
        // contentsScale 1 + resize: the bitmap is stretched to the view.
        // A scale of 2 here shrinks a 2× image into the corner and the stroke jumps on commit.
        inkLayer.contentsScale = 1
        inkLayer.contentsGravity = .resize
        inkLayer.magnificationFilter = .linear
        inkLayer.minificationFilter = .linear
        if let document = onNeedsFullRerender?() {
            reload(from: document)
        }
    }

    private func appendCoalesced(from touch: UITouch, event: UIEvent?) {
        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        for t in coalesced {
            let p = t.location(in: self)
            if let last = lastAccepted, hypot(p.x - last.x, p.y - last.y) < minPointDistance {
                continue
            }
            if activePoints.count >= maxPointsPerStroke { break }
            activePoints.append(p)
            lastAccepted = p
        }
    }

    private func updateLivePath() {
        guard brush != .eraser else {
            clearLive()
            return
        }
        let width = MarkupPalette.widthNorm(fromSlider: widthSlider) * bounds.width
        let color = UIColor(markupHex: colorHex) ?? .white
        let path = Self.displayPath(points: activePoints, width: width)

        liveGlow.fillColor = nil
        liveMid.fillColor = nil
        liveCore.fillColor = nil

        switch brush {
        case .pen:
            liveGlow.path = nil
            liveMid.path = nil
            liveCore.path = path
            liveCore.strokeColor = color.cgColor
            liveCore.lineWidth = activePoints.count < 2 ? 0 : width
            liveCore.fillColor = activePoints.count < 2 ? color.cgColor : nil
            liveCore.opacity = 1
        case .marker:
            liveGlow.path = nil
            liveMid.path = nil
            liveCore.path = path
            liveCore.strokeColor = color.withAlphaComponent(0.45).cgColor
            liveCore.lineWidth = activePoints.count < 2 ? 0 : width * 1.6
            liveCore.fillColor = activePoints.count < 2 ? color.withAlphaComponent(0.45).cgColor : nil
            liveCore.opacity = 1
        case .neon:
            if activePoints.count < 2 {
                liveGlow.path = nil
                liveMid.path = nil
                liveCore.path = path
                liveCore.strokeColor = nil
                liveCore.fillColor = color.cgColor
                liveCore.lineWidth = 0
            } else {
                liveGlow.path = path
                liveGlow.strokeColor = color.withAlphaComponent(0.25).cgColor
                liveGlow.lineWidth = width * 3.2
                liveMid.path = path
                liveMid.strokeColor = color.withAlphaComponent(0.6).cgColor
                liveMid.lineWidth = width * 1.8
                liveCore.path = path
                liveCore.strokeColor = UIColor.white.cgColor
                liveCore.lineWidth = width * 0.7
                liveCore.fillColor = nil
            }
        case .eraser:
            break
        }
    }

    /// Dot for a tap, otherwise the same polyline the bitmap will keep. No second smoothing pass.
    private static func displayPath(points: [CGPoint], width: CGFloat) -> CGPath {
        if points.count == 1, let p = points.first {
            let r = max(width, 1) / 2
            return CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil)
        }
        return MarkupRenderer.livePath(points: points)
    }

    private func clearLive() {
        liveGlow.path = nil
        liveMid.path = nil
        liveCore.path = nil
    }

    private func commitStroke() {
        stopDisplayLink()
        defer {
            activePoints.removeAll(keepingCapacity: true)
            lastAccepted = nil
        }
        guard activePoints.count >= 1, bounds.width > 1, bounds.height > 1 else { return }

        let widthNorm = MarkupPalette.widthNorm(fromSlider: widthSlider)
        let normalized = activePoints.map { p in
            MarkupPoint(
                x: min(max(p.x / bounds.width, 0), 1),
                y: min(max(p.y / bounds.height, 0), 1)
            )
        }
        let shape = recognizedShape()
        let stroke = MarkupStroke(
            brush: brush,
            widthNorm: widthNorm,
            colorHex: brush == .eraser ? "#000000" : colorHex,
            points: normalized,
            shape: shape
        )

        let state = signposter.beginInterval("dm.markup.commitStroke")
        if brush != .eraser {
            // Stamp the CAShapeLayer path as-is. Re-smoothing here changed thickness and shape.
            stampLiveLayersIntoInk()
        } else {
            publishInk(clearingLive: true)
        }
        signposter.endInterval("dm.markup.commitStroke", state)

        onStrokeCommitted?(stroke)
    }

    /// Pen strokes that look like a line, arrow, or closed shape replace the ink
    /// with the straightened path before it is stamped.
    private func recognizedShape() -> MarkupVectorShape? {
        guard brush == .pen, activePoints.count >= 8 else { return nil }
        guard let shape = MarkupShapeRecognizer.recognize(points: activePoints, canvasSize: bounds.size) else {
            return nil
        }
        let width = MarkupPalette.widthNorm(fromSlider: widthSlider) * bounds.width
        let color = UIColor(markupHex: colorHex) ?? .white
        let path = shape.path(in: bounds.size, flipsY: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liveGlow.path = nil
        liveMid.path = nil
        liveCore.path = path
        liveCore.strokeColor = color.cgColor
        liveCore.fillColor = nil
        liveCore.lineWidth = max(width, 1)
        liveCore.opacity = 1
        CATransaction.commit()
        return shape
    }

    private var eraserDrawnCount = 0

    private func eraseActiveSegment() {
        guard let ctx = inkContext, activePoints.count >= 2 else { return }
        // Only erase newly added points to avoid re-clearing the same path every move.
        let start = max(eraserDrawnCount - 1, 0)
        guard start < activePoints.count else { return }
        let segment = Array(activePoints[start...])
        eraserDrawnCount = activePoints.count
        let normalized = segment.map { p in
            MarkupPoint(
                x: min(max(p.x / bounds.width, 0), 1),
                y: min(max(p.y / bounds.height, 0), 1)
            )
        }
        let stroke = MarkupStroke(
            brush: .eraser,
            widthNorm: MarkupPalette.widthNorm(fromSlider: widthSlider),
            colorHex: "#000000",
            points: normalized
        )
        MarkupRenderer.drawStroke(stroke, in: ctx, size: CGSize(width: inkWidth, height: inkHeight))
        eraserDirty = true
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(flushEraser))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        if eraserDirty {
            publishInk(clearingLive: false)
            eraserDirty = false
        }
    }

    @objc private func flushEraser() {
        guard eraserDirty else { return }
        publishInk(clearingLive: false)
        eraserDirty = false
    }

    /// Swap the vector stroke for the bitmap in one frame, with no fade.
    private func publishInk(clearingLive: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inkLayer.contents = inkContext?.makeImage()
        if clearingLive {
            clearLive()
        }
        CATransaction.commit()
    }

    /// Draw the on-screen stroke into the ink bitmap in the same view coordinates.
    private func stampLiveLayersIntoInk() {
        guard let ctx = inkContext, bounds.width > 1, bounds.height > 1 else { return }
        ctx.saveGState()
        applyViewSpaceCTM(ctx)
        stamp(liveGlow, in: ctx)
        stamp(liveMid, in: ctx)
        stamp(liveCore, in: ctx)
        ctx.restoreGState()
        publishInk(clearingLive: true)
    }

    private func applyViewSpaceCTM(_ ctx: CGContext) {
        let sx = CGFloat(inkWidth) / bounds.width
        let sy = CGFloat(inkHeight) / bounds.height
        ctx.translateBy(x: 0, y: CGFloat(inkHeight))
        ctx.scaleBy(x: sx, y: -sy)
    }

    private func stamp(_ layer: CAShapeLayer, in ctx: CGContext) {
        guard let path = layer.path else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if let fill = layer.fillColor, layer.lineWidth <= 0.5 {
            ctx.setFillColor(fill)
            ctx.addPath(path)
            ctx.fillPath()
        } else if let stroke = layer.strokeColor, layer.lineWidth > 0 {
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(layer.lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

extension MarkupRenderer {
    /// Draw strokes only (no text) — for ink bitmap.
    static func drawStrokeBatch(_ strokes: [MarkupStroke], in ctx: CGContext, size: CGSize) {
        for stroke in strokes {
            drawStroke(stroke, in: ctx, size: size)
        }
    }
}

struct MarkupDrawingRepresentable: UIViewRepresentable {
    @Binding var document: MarkupDocument
    var brush: MarkupBrush
    var colorHex: String
    var widthSlider: CGFloat
    var isDrawingEnabled: Bool
    var reloadToken: Int

    func makeUIView(context: Context) -> MarkupDrawingView {
        let view = MarkupDrawingView()
        view.onStrokeCommitted = { stroke in
            context.coordinator.commit(stroke)
        }
        view.onNeedsFullRerender = {
            context.coordinator.document
        }
        return view
    }

    func updateUIView(_ uiView: MarkupDrawingView, context: Context) {
        context.coordinator.document = document
        context.coordinator.binding = $document
        uiView.brush = brush
        uiView.colorHex = colorHex
        uiView.widthSlider = widthSlider
        uiView.isDrawingEnabled = isDrawingEnabled
        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            uiView.reload(from: document)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, binding: $document)
    }

    final class Coordinator {
        var document: MarkupDocument
        var binding: Binding<MarkupDocument>
        var reloadToken = -1

        init(document: MarkupDocument, binding: Binding<MarkupDocument>) {
            self.document = document
            self.binding = binding
        }

        func commit(_ stroke: MarkupStroke) {
            var doc = binding.wrappedValue
            doc.appendStroke(stroke)
            binding.wrappedValue = doc
            document = doc
        }
    }
}
