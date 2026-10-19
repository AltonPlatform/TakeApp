import AVFoundation
import SwiftUI
import UIKit

struct DMCameraGridOverlay: View {
    var aspect: DMCameraAspect

    var body: some View {
        GeometryReader { geo in
            let frame = DMCameraAspectMask.visibleRect(in: geo.size, aspect: aspect)
            Path { path in
                for i in 1..<3 {
                    let x = frame.minX + frame.width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY))
                    path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    let y = frame.minY + frame.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: frame.minX, y: y))
                    path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

struct DMCameraLevelOverlay: View {
    var reading: LevelReading?

    var body: some View {
        GeometryReader { geo in
            let degrees = reading?.degrees ?? 0
            let isLevel = reading?.isLevel == true
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: geo.size.width * 0.45, height: 1)
                Capsule()
                    .fill(isLevel ? Color.yellow : Color.white)
                    .frame(width: 56, height: 3)
                    .rotationEffect(.degrees(degrees))
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
        .allowsHitTesting(false)
    }
}

struct DMCameraAspectMask: View {
    var aspect: DMCameraAspect

    private let cornerLength: CGFloat = 22
    private let lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let frame = Self.visibleRect(in: geo.size, aspect: aspect)
            Path { path in
                Self.addCorners(to: &path, in: frame, length: cornerLength)
            }
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
        }
        .allowsHitTesting(false)
    }

    static func visibleRect(in size: CGSize, aspect: DMCameraAspect) -> CGRect {
        let target = aspect.ratio
        let current = size.width / max(size.height, 1)
        if current > target {
            let width = size.height * target
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / target
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }

    private static func addCorners(to path: inout Path, in frame: CGRect, length: CGFloat) {
        let L = min(length, min(frame.width, frame.height) / 3)
        // Top-left
        path.move(to: CGPoint(x: frame.minX, y: frame.minY + L))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + L, y: frame.minY))
        // Top-right
        path.move(to: CGPoint(x: frame.maxX - L, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + L))
        // Bottom-left
        path.move(to: CGPoint(x: frame.minX, y: frame.maxY - L))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX + L, y: frame.maxY))
        // Bottom-right
        path.move(to: CGPoint(x: frame.maxX - L, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - L))
    }
}

struct DMFocusIndicatorView: View {
    var state: FocusIndicatorState
    var minBias: Float = -2
    var maxBias: Float = 2

    private let railHeight: CGFloat = 88

    var body: some View {
        GeometryReader { geo in
            let point = CGPoint(
                x: state.point.x * geo.size.width,
                y: state.point.y * geo.size.height
            )
            let range = max(maxBias - minBias, 0.001)
            // Bias up → sun higher on the rail (matches swipe-up = brighter).
            let t = CGFloat((state.exposureBias - minBias) / range)
            let sunY = point.y + railHeight / 2 - t * railHeight

            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(state.isLocked ? Color.yellow : Color.yellow.opacity(0.9), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                    .position(point)

                if state.isLocked {
                    Text("AE/AF LOCK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow, in: Capsule())
                        .position(x: point.x, y: max(24, point.y - 52))
                }

                Capsule()
                    .fill(Color.yellow.opacity(0.85))
                    .frame(width: 3, height: railHeight)
                    .position(x: min(geo.size.width - 28, point.x + 52), y: point.y)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .position(x: min(geo.size.width - 28, point.x + 52), y: sunY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Full-screen live preview with UIKit gestures (pinch zoom, tap focus, long-press lock, vertical EV pan).
struct DMCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onPinchBegan: () -> Void
    var onPinchScale: (CGFloat) -> Void
    var onFocus: (_ viewPoint: CGPoint, _ devicePoint: CGPoint, _ lock: Bool) -> Void
    var onExposurePanBegan: () -> Void
    var onExposurePanChanged: (_ translationY: CGFloat) -> Void
    var onExposurePanEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPinchBegan: onPinchBegan,
            onPinchScale: onPinchScale,
            onFocus: onFocus,
            onExposurePanBegan: onExposurePanBegan,
            onExposurePanChanged: onExposurePanChanged,
            onExposurePanEnded: onExposurePanEnded
        )
    }

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attach(to: view)
        return view
    }

    static func dismantleUIView(_ uiView: PreviewHostView, coordinator: Coordinator) {
        // Detach before dealloc. Doing it on this turn blocks the main thread
        // when start/stop still holds the capture lock, and the chat stays stuck
        // after the cover closes.
        _ = coordinator
        let layer = uiView.previewLayer
        DispatchQueue.main.async {
            layer.session = nil
        }
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        context.coordinator.onPinchBegan = onPinchBegan
        context.coordinator.onPinchScale = onPinchScale
        context.coordinator.onFocus = onFocus
        context.coordinator.onExposurePanBegan = onExposurePanBegan
        context.coordinator.onExposurePanChanged = onExposurePanChanged
        context.coordinator.onExposurePanEnded = onExposurePanEnded
    }

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPinchBegan: () -> Void
        var onPinchScale: (CGFloat) -> Void
        var onFocus: (_ viewPoint: CGPoint, _ devicePoint: CGPoint, _ lock: Bool) -> Void
        var onExposurePanBegan: () -> Void
        var onExposurePanChanged: (_ translationY: CGFloat) -> Void
        var onExposurePanEnded: () -> Void

        private weak var host: PreviewHostView?
        private var pinchBase: CGFloat = 1

        init(
            onPinchBegan: @escaping () -> Void,
            onPinchScale: @escaping (CGFloat) -> Void,
            onFocus: @escaping (CGPoint, CGPoint, Bool) -> Void,
            onExposurePanBegan: @escaping () -> Void,
            onExposurePanChanged: @escaping (CGFloat) -> Void,
            onExposurePanEnded: @escaping () -> Void
        ) {
            self.onPinchBegan = onPinchBegan
            self.onPinchScale = onPinchScale
            self.onFocus = onFocus
            self.onExposurePanBegan = onExposurePanBegan
            self.onExposurePanChanged = onExposurePanChanged
            self.onExposurePanEnded = onExposurePanEnded
        }

        func attach(to view: PreviewHostView) {
            host = view
            view.isMultipleTouchEnabled = true

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.45
            longPress.delegate = self
            view.addGestureRecognizer(longPress)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.require(toFail: longPress)
            tap.delegate = self
            view.addGestureRecognizer(tap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                onPinchBegan()
            case .changed, .ended:
                onPinchScale(gesture.scale)
            default:
                break
            }
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let host else { return }
            emitFocus(at: gesture.location(in: host), lock: false)
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let host else { return }
            emitFocus(at: gesture.location(in: host), lock: true)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let host else { return }
            let translation = gesture.translation(in: host)
            switch gesture.state {
            case .began:
                onExposurePanBegan()
            case .changed:
                onExposurePanChanged(translation.y)
            case .ended, .cancelled, .failed:
                onExposurePanEnded()
            default:
                break
            }
        }

        private func emitFocus(at location: CGPoint, lock: Bool) {
            guard let host else { return }
            let bounds = host.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
            let viewPoint = CGPoint(x: location.x / bounds.width, y: location.y / bounds.height)
            let devicePoint = host.previewLayer.captureDevicePointConverted(fromLayerPoint: location)
            onFocus(viewPoint, devicePoint, lock)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Pinch with nothing else; pan and tap must not fight.
            if gestureRecognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer {
                return false
            }
            return false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let host else {
                return true
            }
            let velocity = pan.velocity(in: host)
            // Prefer vertical pans for exposure; let horizontal scrolls pass (none today).
            return abs(velocity.y) >= abs(velocity.x)
        }
    }
}

struct DMCountdownOverlay: View {
    var value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 8)
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
    }
}

struct DMCameraSettingsStrip: View {
    var timerDelay: TimerDelay
    var aspect: DMCameraAspect
    var showGrid: Bool
    var onCycleTimer: () -> Void
    var onCycleAspect: () -> Void
    var onToggleGrid: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            CameraGlassButton(
                systemName: "timer",
                label: timerDelay.label,
                isActive: timerDelay != .none,
                action: onCycleTimer
            )
            CameraGlassButton(
                systemName: "crop",
                label: aspect.title,
                isActive: aspect != .fourByThree,
                action: onCycleAspect
            )
            CameraGlassButton(
                systemName: "grid",
                label: "Grid",
                isActive: showGrid,
                action: onToggleGrid
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
    }
}

struct DMCameraFilterPanel: View {
    var filters: [any CameraFilter]
    var selectedFilterID: String
    var beautyIntensity: Double
    var onSelectFilter: (any CameraFilter) -> Void
    var onBeautyChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 12) {
            FilterCarousel(
                filters: filters,
                selectedFilterID: selectedFilterID,
                onSelect: onSelectFilter
            )

            HStack(spacing: 10) {
                Label("Beauty", systemImage: "face.smiling")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Slider(
                    value: Binding(
                        get: { beautyIntensity },
                        set: { onBeautyChange($0) }
                    ),
                    in: 0...1
                )
                .tint(CameraChrome.accent)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
    }
}
