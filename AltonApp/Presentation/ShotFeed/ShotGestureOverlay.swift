import SwiftUI
import UIKit

enum ShotSpeedZone {
    case left
    case center
    case right
}

struct ShotGestureOverlay: UIViewRepresentable {
    var onSingleTap: () -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onCenterLongPressEnded: () -> Void

    func makeUIView(context: Context) -> VideoGestureView {
        let view = VideoGestureView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.onSingleTap = onSingleTap
        view.onDoubleTap = onDoubleTap
        view.onCenterLongPressEnded = onCenterLongPressEnded
        return view
    }

    func updateUIView(_ uiView: VideoGestureView, context: Context) {
        uiView.onSingleTap = onSingleTap
        uiView.onDoubleTap = onDoubleTap
        uiView.onCenterLongPressEnded = onCenterLongPressEnded
    }
}

struct ShotSpeedZoneOverlay: View {
    let zone: ShotSpeedZone
    var onZoneSpeedBegan: (ShotSpeedZone) -> Void
    var onZoneSpeedChanged: (_ translationX: CGFloat, _ zone: ShotSpeedZone) -> Void
    var onZoneSpeedEnded: () -> Void
    var onZoneSpeedCancelled: () -> Void

    var body: some View {
        ShotSpeedZoneView(
            zone: zone,
            onZoneSpeedBegan: onZoneSpeedBegan,
            onZoneSpeedChanged: onZoneSpeedChanged,
            onZoneSpeedEnded: onZoneSpeedEnded,
            onZoneSpeedCancelled: onZoneSpeedCancelled
        )
    }
}

struct ShotSpeedZoneView: UIViewRepresentable {
    let zone: ShotSpeedZone
    var onZoneSpeedBegan: (ShotSpeedZone) -> Void
    var onZoneSpeedChanged: (_ translationX: CGFloat, _ zone: ShotSpeedZone) -> Void
    var onZoneSpeedEnded: () -> Void
    var onZoneSpeedCancelled: () -> Void

    func makeUIView(context: Context) -> ShotSpeedZoneUIView {
        let view = ShotSpeedZoneUIView(zone: zone)
        view.onZoneSpeedBegan = onZoneSpeedBegan
        view.onZoneSpeedChanged = onZoneSpeedChanged
        view.onZoneSpeedEnded = onZoneSpeedEnded
        view.onZoneSpeedCancelled = onZoneSpeedCancelled
        return view
    }

    func updateUIView(_ uiView: ShotSpeedZoneUIView, context: Context) {
        uiView.zone = zone
        uiView.onZoneSpeedBegan = onZoneSpeedBegan
        uiView.onZoneSpeedChanged = onZoneSpeedChanged
        uiView.onZoneSpeedEnded = onZoneSpeedEnded
        uiView.onZoneSpeedCancelled = onZoneSpeedCancelled
    }
}

final class ShotSpeedZoneUIView: UIView, UIGestureRecognizerDelegate {
    var zone: ShotSpeedZone
    var onZoneSpeedBegan: ((ShotSpeedZone) -> Void)?
    var onZoneSpeedChanged: ((_ translationX: CGFloat, _ zone: ShotSpeedZone) -> Void)?
    var onZoneSpeedEnded: (() -> Void)?
    var onZoneSpeedCancelled: (() -> Void)?

    private var isActive = false
    private var usesHorizontalDrag = false
    private weak var parentScrollView: UIScrollView?

    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        return pan
    }()

    init(zone: ShotSpeedZone) {
        self.zone = zone
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        addGestureRecognizer(panRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if parentScrollView == nil {
            parentScrollView = findAncestorScrollView()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        switch gesture.state {
        case .began:
            isActive = true
            usesHorizontalDrag = false
            parentScrollView?.isScrollEnabled = false
            onZoneSpeedBegan?(zone)
        case .changed:
            guard isActive else { return }

            if !usesHorizontalDrag {
                guard hypot(translation.x, translation.y) >= 10 else { return }
                if abs(velocity.x) <= abs(velocity.y) {
                    cancelInteraction()
                    return
                }
                usesHorizontalDrag = true
            }

            onZoneSpeedChanged?(translation.x, zone)
        case .ended:
            guard isActive else { return }
            resetState()
            onZoneSpeedEnded?()
        case .cancelled, .failed:
            cancelInteraction()
        default:
            break
        }
    }

    private func cancelInteraction() {
        guard isActive else { return }
        resetState()
        onZoneSpeedCancelled?()
    }

    private func resetState() {
        isActive = false
        usesHorizontalDrag = false
        parentScrollView?.isScrollEnabled = true
    }

    private func findAncestorScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === panRecognizer && otherGestureRecognizer === parentScrollView?.panGestureRecognizer
    }
}

final class VideoGestureView: UIView, UIGestureRecognizerDelegate {
    var onSingleTap: (() -> Void)?
    var onDoubleTap: ((CGPoint) -> Void)?
    var onCenterLongPressEnded: (() -> Void)?

    private var longPressMoved = false
    private var isLongPressActive = false
    private weak var parentScrollView: UIScrollView?

    private lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 10
        longPress.delegate = self
        return longPress
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        setupGestures()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachParentScrollViewIfNeeded()
    }

    private func setupGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        addGestureRecognizer(longPressRecognizer)
    }

    private func attachParentScrollViewIfNeeded() {
        guard parentScrollView == nil else { return }
        parentScrollView = findAncestorScrollView()
        guard let parentScrollView else { return }
        longPressRecognizer.require(toFail: parentScrollView.panGestureRecognizer)
    }

    private func speedZone(for x: CGFloat) -> ShotSpeedZone {
        let width = max(bounds.width, 1)
        if x < width * 0.25 { return .left }
        if x > width * 0.75 { return .right }
        return .center
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard !isLongPressActive else { return }
        let zone = speedZone(for: gesture.location(in: self).x)
        guard zone == .center else { return }
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !isLongPressActive else { return }
        onDoubleTap?(gesture.location(in: self))
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let zone = speedZone(for: gesture.location(in: self).x)
        guard zone == .center else { return }

        switch gesture.state {
        case .began:
            longPressMoved = false
            isLongPressActive = true
        case .changed:
            longPressMoved = true
        case .ended:
            guard isLongPressActive else { return }
            let shouldOpenMenu = !longPressMoved
            resetLongPressState()
            if shouldOpenMenu {
                onCenterLongPressEnded?()
            }
        case .cancelled, .failed:
            resetLongPressState()
        default:
            break
        }
    }

    private func resetLongPressState() {
        isLongPressActive = false
        longPressMoved = false
    }

    private func findAncestorScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === longPressRecognizer else { return true }
        attachParentScrollViewIfNeeded()
        if parentScrollView?.isDragging == true || parentScrollView?.isDecelerating == true {
            return false
        }
        let location = longPressRecognizer.location(in: self)
        return speedZone(for: location.x) == .center
    }
}
