import SwiftUI
import UIKit

@MainActor
@Observable
final class MarkupTextGestureState {
    var activeID: UUID?
    var center: MarkupPoint?
    var scale: CGFloat?
    var rotation: CGFloat?
    var showVerticalGuide = false
    var showHorizontalGuide = false
    var trashHovering = false
    var isInteracting = false

    func reset() {
        activeID = nil
        center = nil
        scale = nil
        rotation = nil
        showVerticalGuide = false
        showHorizontalGuide = false
        trashHovering = false
        isInteracting = false
    }
}

struct MarkupTextGestureRepresentable: UIViewRepresentable {
    var texts: [MarkupTextItem]
    var canvasSize: CGSize
    var trashFrameInCanvas: CGRect
    var isEnabled: Bool
    var gestureState: MarkupTextGestureState
    var onEdit: (UUID) -> Void
    var onCommit: (_ id: UUID, _ center: MarkupPoint, _ scale: CGFloat, _ rotation: CGFloat) -> Void
    var onDelete: (_ id: UUID, _ center: MarkupPoint, _ scale: CGFloat) -> Void
    var onTapEmpty: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            gestureState: gestureState,
            onEdit: onEdit,
            onCommit: onCommit,
            onDelete: onDelete,
            onTapEmpty: onTapEmpty
        )
    }

    func makeUIView(context: Context) -> GestureHostView {
        let view = GestureHostView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: GestureHostView, context: Context) {
        context.coordinator.texts = texts
        context.coordinator.canvasSize = canvasSize
        context.coordinator.trashFrame = trashFrameInCanvas
        context.coordinator.onEdit = onEdit
        context.coordinator.onCommit = onCommit
        context.coordinator.onDelete = onDelete
        context.coordinator.onTapEmpty = onTapEmpty
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var texts: [MarkupTextItem] = []
        var canvasSize: CGSize = .zero
        var trashFrame: CGRect = .zero
        var onEdit: (UUID) -> Void
        var onCommit: (_ id: UUID, _ center: MarkupPoint, _ scale: CGFloat, _ rotation: CGFloat) -> Void
        var onDelete: (UUID, MarkupPoint, CGFloat) -> Void
        var onTapEmpty: (CGPoint) -> Void
        let gestureState: MarkupTextGestureState

        private weak var host: GestureHostView?
        private var pan: UIPanGestureRecognizer!
        private var pinch: UIPinchGestureRecognizer!
        private var rotate: UIRotationGestureRecognizer!
        private var tap: UITapGestureRecognizer!

        private var baseCenter = MarkupPoint(x: 0.5, y: 0.5)
        private var baseScale: CGFloat = 1
        private var baseRotation: CGFloat = 0
        private var activeItem: MarkupTextItem?
        private var activeRecognizers = 0
        private var wasSnapped = false
        private var didTransform = false
        private var trackingEmptyTap = false
        private var touchDownPoint: CGPoint = .zero
        private var fingerAnchor: CGPoint = .zero
        private var centerAnchor = MarkupPoint(x: 0.5, y: 0.5)
        private var clampHalf = CGSize(width: 24, height: 16)
        private var selectionHaptic = UISelectionFeedbackGenerator()

        init(
            gestureState: MarkupTextGestureState,
            onEdit: @escaping (UUID) -> Void,
            onCommit: @escaping (UUID, MarkupPoint, CGFloat, CGFloat) -> Void,
            onDelete: @escaping (UUID, MarkupPoint, CGFloat) -> Void,
            onTapEmpty: @escaping (CGPoint) -> Void
        ) {
            self.gestureState = gestureState
            self.onEdit = onEdit
            self.onCommit = onCommit
            self.onDelete = onDelete
            self.onTapEmpty = onTapEmpty
        }

        func attach(to view: GestureHostView) {
            host = view
            pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
            tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            for g in [pan, pinch, rotate, tap] {
                g?.delegate = self
                view.addGestureRecognizer(g!)
            }
            pan.maximumNumberOfTouches = 2
            pan.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            selectionHaptic.prepare()
        }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, !didTransform, canvasSize.width > 0 else { return }
            let point = g.location(in: host)
            if let item = hitTest(point) {
                onEdit(item.id)
            } else {
                onTapEmpty(point)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                touchDownPoint = g.location(in: host)
                beginIfNeeded(at: touchDownPoint, allowEmpty: true)
                fallthrough
            case .changed:
                let finger = g.location(in: host)
                let dx = finger.x - fingerAnchor.x
                let dy = finger.y - fingerAnchor.y
                if hypot(dx, dy) > 2 { didTransform = true }
                guard activeItem != nil, canvasSize.width > 0, canvasSize.height > 0 else { return }
                let cx = centerAnchor.x * canvasSize.width + dx
                let cy = centerAnchor.y * canvasSize.height + dy
                applyLive(
                    center: MarkupPoint(x: cx / canvasSize.width, y: cy / canvasSize.height),
                    scale: gestureState.scale ?? baseScale,
                    rotation: gestureState.rotation ?? baseRotation
                )
            case .ended, .cancelled, .failed:
                endRecognizer(fromPan: true)
            default:
                break
            }
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                let point = g.numberOfTouches > 0
                    ? g.location(ofTouch: 0, in: host)
                    : g.location(in: host)
                beginIfNeeded(at: point, allowEmpty: false)
                fallthrough
            case .changed:
                guard activeItem != nil else { return }
                if abs(g.scale - 1) > 0.02 { didTransform = true }
                let next = min(max(baseScale * g.scale, 0.4), 4)
                applyLive(
                    center: gestureState.center ?? baseCenter,
                    scale: next,
                    rotation: gestureState.rotation ?? baseRotation
                )
            case .ended, .cancelled, .failed:
                endRecognizer(fromPan: false)
            default:
                break
            }
        }

        @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
            switch g.state {
            case .began:
                let point = g.numberOfTouches > 0
                    ? g.location(ofTouch: 0, in: host)
                    : g.location(in: host)
                beginIfNeeded(at: point, allowEmpty: false)
                fallthrough
            case .changed:
                guard activeItem != nil else { return }
                if abs(g.rotation) > 0.02 { didTransform = true }
                applyLive(
                    center: gestureState.center ?? baseCenter,
                    scale: gestureState.scale ?? baseScale,
                    rotation: baseRotation + g.rotation
                )
            case .ended, .cancelled, .failed:
                endRecognizer(fromPan: false)
            default:
                break
            }
        }

        private func beginIfNeeded(at point: CGPoint, allowEmpty: Bool) {
            if activeItem != nil {
                activeRecognizers += 1
                return
            }
            if let item = hitTest(point) {
                trackingEmptyTap = false
                activeItem = item
                activeRecognizers = 1
                baseCenter = item.center
                baseScale = item.scale
                baseRotation = item.rotation
                centerAnchor = item.center
                fingerAnchor = point
                let box = MarkupTextLayout.axisAlignedBounds(item: item, canvasSize: canvasSize)
                clampHalf = CGSize(width: box.width / 2, height: box.height / 2)
                wasSnapped = false
                didTransform = false
                gestureState.activeID = item.id
                gestureState.isInteracting = true
                gestureState.center = item.center
                gestureState.scale = item.scale
                gestureState.rotation = item.rotation
            } else if allowEmpty {
                trackingEmptyTap = true
                didTransform = false
            }
        }

        private func applyLive(center: MarkupPoint, scale: CGFloat, rotation: CGFloat) {
            guard var item = activeItem else { return }
            item.scale = scale
            item.rotation = rotation
            var snapped = MarkupTextSnap.apply(
                center: center,
                rotation: rotation,
                canvasSize: canvasSize,
                previouslySnapped: wasSnapped
            )
            if snapped.didSnap {
                selectionHaptic.selectionChanged()
                wasSnapped = true
            } else if !snapped.showVerticalGuide && !snapped.showHorizontalGuide && abs(snapped.rotation) > 0.001 {
                wasSnapped = false
            }
            item.center = snapped.center
            item.rotation = snapped.rotation
            let clamped = clampCached(snapped.center)
            snapped.center = clamped

            let livePoint = CGPoint(
                x: clamped.x * canvasSize.width,
                y: clamped.y * canvasSize.height
            )
            let hovering = trashFrame.contains(livePoint)
            gestureState.center = clamped
            gestureState.scale = scale
            gestureState.rotation = snapped.rotation
            gestureState.showVerticalGuide = snapped.showVerticalGuide
            gestureState.showHorizontalGuide = snapped.showHorizontalGuide
            gestureState.trashHovering = hovering
        }

        private func endRecognizer(fromPan: Bool) {
            if activeItem != nil {
                activeRecognizers = max(0, activeRecognizers - 1)
                guard activeRecognizers == 0 else { return }

                let item = activeItem!
                let center = gestureState.center ?? item.center
                let scale = gestureState.scale ?? item.scale
                let rotation = gestureState.rotation ?? item.rotation
                let hovering = gestureState.trashHovering
                let id = item.id
                let moved = didTransform
                activeItem = nil
                gestureState.reset()
                didTransform = false
                trackingEmptyTap = false
                if hovering {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDelete(id, center, scale)
                } else if moved {
                    onCommit(id, center, scale, rotation)
                } else {
                    onEdit(id)
                }
            } else if fromPan, trackingEmptyTap {
                let wasTap = !didTransform
                trackingEmptyTap = false
                didTransform = false
                if wasTap {
                    onTapEmpty(touchDownPoint)
                }
            }
        }

        private func clampCached(_ center: MarkupPoint) -> MarkupPoint {
            let inset: CGFloat = 8
            var cx = center.x * canvasSize.width
            var cy = center.y * canvasSize.height
            let minX = inset + clampHalf.width
            let maxX = canvasSize.width - inset - clampHalf.width
            let minY = inset + clampHalf.height
            let maxY = canvasSize.height - inset - clampHalf.height
            if minX < maxX { cx = min(max(cx, minX), maxX) }
            if minY < maxY { cy = min(max(cy, minY), maxY) }
            return MarkupPoint(
                x: cx / max(canvasSize.width, 1),
                y: cy / max(canvasSize.height, 1)
            )
        }

        private func hitTest(_ point: CGPoint) -> MarkupTextItem? {
            for item in texts.reversed() {
                if MarkupTextLayout.contains(point: point, item: item, canvasSize: canvasSize) {
                    return item
                }
            }
            return nil
        }
    }
}

final class GestureHostView: UIView {}
