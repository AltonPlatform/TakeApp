import Accelerate
import SwiftUI
import UIKit

/// Navigation-style slide. The chat stays opaque and blurs as it moves aside.
enum ChatDissolveMotion {
    /// Tap-open. Short on purpose: a long slide plus a live 72pt blur feels late.
    static let openDuration: TimeInterval = 0.25
    static let closeDuration: TimeInterval = 0.4
    static let reduceMotionDuration: TimeInterval = 0.15

    /// On-screen blur radius in points. It is reached at the middle of the swipe.
    static let chatBlur: CGFloat = 72
    /// Finger travel (0...1) at which the chat has fully slid away.
    /// 1 keeps the card on the finger. 0.5 moved it twice as far as the finger.
    static let dismissTravel: CGFloat = 1
    /// Share of `dismissTravel` at which the chat has fully blurred out.
    /// 0.5 keeps it readable through the first half of the swipe.
    static let blurLead: CGFloat = 0.5

    /// Finger travel across the full width maps to progress 1.
    static let edgeSwipeDistanceFactor: CGFloat = 1
    static let edgeCloseProgressThreshold: CGFloat = 0.35
    static let edgeCloseVelocityThreshold: CGFloat = 600
    /// Finger-up cancel. Fixed duration so a fast flick cannot collapse the return into a snap.
    static let cancelDuration: TimeInterval = 0.35

    static func open(reduceMotion: Bool) -> Animation {
        .snappy(duration: reduceMotion ? reduceMotionDuration : openDuration, extraBounce: 0)
    }

    static func close(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? reduceMotionDuration : closeDuration)
    }

    /// Finger-up settle. `initialVelocity` is in chat-progress units per second
    /// (negative while the chat is sliding off to the right).
    static func release(initialVelocity: CGFloat, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else {
            return .easeOut(duration: reduceMotionDuration)
        }
        let velocity = min(3, max(-3, initialVelocity))
        return .interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: velocity)
    }

    /// Open progress, but the dismiss finishes halfway across the finger travel.
    /// 1 = chat fully open, 0 = gone. Values below `1 - dismissTravel` stay at 0.
    static func presentedAmount(_ progress: CGFloat) -> CGFloat {
        let closing = 1 - min(1, max(0, progress))
        return 1 - min(1, closing / dismissTravel)
    }

    /// 0 when the chat is fully open, 1 once it has moved halfway shut.
    static func blurMix(forPresented presented: CGFloat) -> CGFloat {
        let closing = 1 - min(1, max(0, presented))
        guard blurLead > 0 else { return closing > 0 ? 1 : 0 }
        return min(1, closing / blurLead)
    }
}

/// Opaque full-bleed fill so the fading chat covers the status bar and home indicator.
struct ChatScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.accentColor.opacity(0.06),
                Color(.systemGray6).opacity(0.5),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Slides the whole chat with the finger.
/// Blur is a separate pre-rendered plate (`ChatSwipePlate`): a live `.blur()`
/// re-rasterizes the chat on every finger move.
/// `transformEffect` does not change layout, so safe-area insets stay put.
struct ChatLayerTransition: ViewModifier, Animatable {
    /// 1 = fully open, 0 = off to the right.
    var progress: CGFloat
    var width: CGFloat
    var reduceMotion: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(1, max(0, progress))
        let closing = 1 - p
        if reduceMotion {
            content.opacity(p)
        } else {
            // One modifier chain for the whole gesture. Branching at progress == 1
            // reparents the chat and cancels the interactive pop.
            // Live blur is only this short open. A 72pt blur re-rasterizes the chat
            // and makes the push feel late. The finger path uses the plate.
            content
                .blur(radius: 16 * closing)
                .transformEffect(
                    CGAffineTransform(translationX: closing * width, y: 0)
                )
        }
    }
}

/// Sharp plus fully blurred chat, captured once per swipe.
struct ChatPlateImages {
    let sharp: UIImage
    let blurred: UIImage

    static let empty = ChatPlateImages(sharp: UIImage(), blurred: UIImage())
}

/// UIKit view the edge pan snapshots. Held by the inbox so a button-close can
/// capture without waiting for another gesture callback.
final class ChatMotionSource {
    weak var view: UIView?
}

enum ChatPlateImage {
    /// One sharp bitmap plus one downscaled blur. The swipe only crossfades them.
    /// Blur stays on the CPU: a Metal `CIContext` here crashes the A13 GPU during the open transition.
    static func make(from view: UIView) -> ChatPlateImages? {
        let source = fullBleedView(from: view)
        let bounds = source.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        let displayScale = source.traitCollection.displayScale
        format.scale = min(2, displayScale > 0 ? displayScale : 2)
        format.opaque = true
        let sharp = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            source.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        return ChatPlateImages(sharp: sharp, blurred: blurred(sharp))
    }

    private static func blurred(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let fit = min(1, 420 / max(longest, 1))
        let size = CGSize(
            width: max(1, floor(image.size.width * fit)),
            height: max(1, floor(image.size.height * fit))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return boxBlur(small, radius: max(2, ChatDissolveMotion.chatBlur * fit)) ?? small
    }

    private static func boxBlur(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var srcFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passUnretained(colorSpace),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
        var source = vImage_Buffer()
        var error = vImageBuffer_InitWithCGImage(&source, &srcFormat, nil, cgImage, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }
        defer { free(source.data) }

        var dest = vImage_Buffer()
        error = vImageBuffer_Init(&dest, source.height, source.width, 32, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }
        defer { free(dest.data) }

        let limit = max(3, Int(min(source.width, source.height)) / 2)
        let kernel = UInt32(min(limit, max(3, Int(radius)))) | 1
        let flags = vImage_Flags(kvImageEdgeExtend)
        error = vImageBoxConvolve_ARGB8888(&source, &dest, nil, 0, 0, kernel, kernel, nil, flags)
        guard error == kvImageNoError else { return nil }
        error = vImageBoxConvolve_ARGB8888(&dest, &source, nil, 0, 0, kernel, kernel, nil, flags)
        guard error == kvImageNoError else { return nil }
        error = vImageBoxConvolve_ARGB8888(&source, &dest, nil, 0, 0, kernel, kernel, nil, flags)
        guard error == kvImageNoError else { return nil }

        var outError = vImage_Error()
        guard let out = vImageCreateCGImageFromBuffer(&dest, &srcFormat, nil, nil, vImage_Flags(kvImageNoFlags), &outError),
              outError == kvImageNoError
        else { return nil }
        return UIImage(cgImage: out.takeRetainedValue(), scale: 1, orientation: .up)
    }

    /// Gesture host can be a thin overlay. Use the nearest screen-sized chat, not the
    /// window: the outermost match also contains the inbox, and sliding that bitmap
    /// hides the real list until the snapshot is thrown away.
    private static func fullBleedView(from view: UIView) -> UIView {
        let screen = view.window?.bounds ?? UIScreen.main.bounds
        let minWidth = screen.width * 0.95
        let minHeight = screen.height * 0.95
        if view.bounds.width >= minWidth, view.bounds.height >= minHeight {
            return view
        }
        var node: UIView? = view.superview
        while let current = node, !(current is UIWindow) {
            if current.bounds.width >= minWidth, current.bounds.height >= minHeight {
                return current
            }
            node = current.superview
        }
        return view
    }
}

/// Crossfades a pre-blurred snapshot. The inbox slides this view aside; the view itself
/// must not stay parked full-screen or its host covers the list. No per-frame gaussian.
struct ChatSwipePlate: UIViewRepresentable, Animatable {
    var images: ChatPlateImages
    var progress: CGFloat
    var width: CGFloat
    /// False while the finger is down. A release then applies one animated jump back or away.
    var animatesChanges: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func makeUIView(context: Context) -> ChatSwipePlateView {
        let view = ChatSwipePlateView()
        view.setImages(images)
        view.apply(progress: progress, width: width, animated: false)
        view.clearHostingBackground()
        return view
    }

    func updateUIView(_ uiView: ChatSwipePlateView, context: Context) {
        uiView.clearHostingBackground()
        uiView.setImages(images)
        uiView.apply(progress: progress, width: width, animated: animatesChanges)
    }
}

final class ChatSwipePlateView: UIView {
    private let canvas = UIView()
    private let sharpView = UIImageView()
    private let blurredView = UIImageView()
    private let edgeMask = CAGradientLayer()
    private let chevron = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private var renderedProgress: CGFloat = 1
    private var animationGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        canvas.isUserInteractionEnabled = false
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.clipsToBounds = false
        sharpView.contentMode = .scaleToFill
        sharpView.isOpaque = false
        sharpView.backgroundColor = .clear
        blurredView.contentMode = .scaleToFill
        blurredView.isOpaque = false
        blurredView.backgroundColor = .clear
        blurredView.alpha = 0
        canvas.addSubview(sharpView)
        canvas.addSubview(blurredView)
        addSubview(canvas)
        let glyph = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        ))
        glyph.tintColor = .label
        glyph.contentMode = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        chevron.clipsToBounds = true
        chevron.layer.cornerRadius = 22
        chevron.contentView.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: chevron.contentView.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: chevron.contentView.centerYAnchor),
        ])
        addSubview(chevron)
        // Soft leading edge so the sliding card dissolves into the inbox instead of cutting.
        edgeMask.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.35).cgColor,
            UIColor.black.cgColor,
        ]
        edgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeMask.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Setting `frame` clears an in-flight transform, which snaps the finger-up return.
        canvas.bounds = bounds
        canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
        sharpView.frame = canvas.bounds
        blurredView.frame = canvas.bounds
        if canvas.layer.mask === edgeMask {
            edgeMask.frame = canvas.bounds
        }
    }

    /// SwiftUI wraps this view in an opaque host. Left full-screen, that host hides
    /// the inbox in the area the card has already moved off.
    func clearHostingBackground() {
        var ancestor = superview
        var depth = 0
        while let current = ancestor, depth < 3, !(current is UIWindow) {
            current.isOpaque = false
            current.backgroundColor = .clear
            ancestor = current.superview
            depth += 1
        }
    }

    func setImages(_ images: ChatPlateImages) {
        if sharpView.image !== images.sharp {
            sharpView.image = images.sharp
        }
        if blurredView.image !== images.blurred {
            blurredView.image = images.blurred
        }
    }

    /// `progress` 1 = fully open. The card stays opaque and crossfades into the blurred snapshot.
    func apply(progress: CGFloat, width: CGFloat, animated: Bool) {
        let delta = abs(progress - renderedProgress)
        // A finger-up settle arrives as one jump. Drag ticks stay small and must not restart a spring.
        let shouldAnimate = animated && delta > 0.05
        renderedProgress = progress
        if shouldAnimate {
            animationGeneration += 1
            let token = animationGeneration
            UIView.animate(
                withDuration: ChatDissolveMotion.cancelDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.render(progress: progress, width: width)
            } completion: { _ in
                guard token == self.animationGeneration else { return }
            }
        } else {
            animationGeneration += 1
            canvas.layer.removeAllAnimations()
            layer.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            render(progress: progress, width: width)
            CATransaction.commit()
        }
    }

    private func render(progress: CGFloat, width: CGFloat) {
        let presented = ChatDissolveMotion.presentedAmount(progress)
        let closing = 1 - presented
        let blur = ChatDissolveMotion.blurMix(forPresented: presented)
        // Position is the SwiftUI offset of this view. A transform here would slide the
        // bitmap inside an opaque host and the inbox would stay covered.
        canvas.transform = .identity
        alpha = 1
        // The blurred card stays readable, but the inbox (including the compose
        // button) has to show through it. An opaque slab hides that chrome until
        // the snapshot is removed at the end of the swipe.
        canvas.alpha = 1 - 0.62 * blur
        sharpView.alpha = 1 - blur
        blurredView.alpha = blur
        chevron.alpha = 0
        let fade = min(0.22, 72 / max(width, 1))
        edgeMask.locations = [0, NSNumber(value: Float(fade * 0.45)), NSNumber(value: Float(fade))]
        edgeMask.frame = canvas.bounds
        canvas.layer.mask = closing > 0.001 ? edgeMask : nil
    }
}

extension View {
    func chatLayerTransition(
        progress: CGFloat,
        width: CGFloat,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            ChatLayerTransition(
                progress: progress,
                width: width,
                reduceMotion: reduceMotion
            )
        )
    }
}

/// Glass chevron on the chat card's leading edge. Hidden when the card is settled open or shut.
struct ChatSeamChevron: View {
    var progress: CGFloat
    var width: CGFloat
    var height: CGFloat
    var reduceMotion: Bool

    var body: some View {
        let presented = ChatDissolveMotion.presentedAmount(progress)
        let travel = min(presented, 1 - presented)
        let shown: CGFloat = reduceMotion ? 0 : min(1, travel / 0.08)
        Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .directGlass(Circle())
            .position(x: (1 - presented) * width, y: height / 2)
            .opacity(shown)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Aggregates child locks so the inbox edge-back swipe can be disabled.
struct ChatBackSwipeLockedKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Rightward pan from anywhere on the chat, same tracking as an interactive pop.
/// Vertical scrolls still win: the list pan waits only when this gesture actually begins.
struct InboxEdgeBackGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool = true
    var source: ChatMotionSource
    var onBegan: (UIView) -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ progress: CGFloat, _ velocityX: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(source: source)
    }

    func makeUIGestureRecognizer(context: Context) -> InboxBackPanRecognizer {
        let recognizer = InboxBackPanRecognizer()
        recognizer.isEnabled = isEnabled
        context.coordinator.bind(recognizer)
        context.coordinator.source = source
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: InboxBackPanRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
        context.coordinator.source = source
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        source.view = recognizer.view
    }

    final class Coordinator {
        var source: ChatMotionSource
        var onBegan: ((UIView) -> Void)?
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat, CGFloat) -> Void)?

        init(source: ChatMotionSource) {
            self.source = source
        }

        func bind(_ recognizer: InboxBackPanRecognizer) {
            recognizer.onBegan = { [weak self] view in
                self?.source.view = view
                self?.onBegan?(view)
            }
            recognizer.onChanged = { [weak self] progress in
                self?.onChanged?(progress)
            }
            recognizer.onEnded = { [weak self] progress, velocityX in
                self?.onEnded?(progress, velocityX)
            }
        }
    }
}

final class InboxBackPanRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    var onBegan: ((UIView) -> Void)?
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat, CGFloat) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        maximumNumberOfTouches = 1
        addTarget(self, action: #selector(handlePan))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let speed = velocity(in: view)
        return speed.x > 0 && abs(speed.x) > abs(speed.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer.view is UIScrollView
    }

    @objc private func handlePan() {
        let width = max(view?.bounds.width ?? UIScreen.main.bounds.width, 1)
        let distance = width * ChatDissolveMotion.edgeSwipeDistanceFactor
        let translationX = max(0, translation(in: view).x)
        let progress = min(1, translationX / distance)
        let velocityX = velocity(in: view).x

        switch state {
        case .began:
            if let view {
                onBegan?(view)
            }
            onChanged?(progress)
        case .changed:
            onChanged?(progress)
        case .ended, .cancelled, .failed:
            onEnded?(progress, velocityX)
        default:
            break
        }
    }
}
