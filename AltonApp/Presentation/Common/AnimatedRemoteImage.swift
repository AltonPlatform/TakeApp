import ImageIO
import Nuke
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Decodes multi-frame GIF/WebP into `UIImage.animatedImage` via ImageIO.
enum AnimatedImageDecoder {
    private static let maxFrameCount = 150
    private static let maxSlotCount = 400
    private static let minDelay: TimeInterval = 0.02
    private static let defaultDelay: TimeInterval = 0.1

    /// First frame only. The GIF grid uses this so a cell does not decode the whole animation.
    nonisolated static func still(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        return stillFrame(source: source, index: 0, maxPixelSize: maxPixelSize)
    }

    /// Builds an animated (or still) image. Safe to call off the main actor.
    /// `isCancelled` is checked between frames so leaving the GIF tab can stop the decode.
    nonisolated static func make(
        data: Data,
        maxPixelSize: CGFloat,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        if count == 1 {
            return stillFrame(source: source, index: 0, maxPixelSize: maxPixelSize)
        }

        let step = count > maxFrameCount
            ? Int(ceil(Double(count) / Double(maxFrameCount)))
            : 1

        var frames: [UIImage] = []
        var delays: [TimeInterval] = []
        frames.reserveCapacity((count + step - 1) / step)
        delays.reserveCapacity((count + step - 1) / step)

        var index = 0
        while index < count {
            if isCancelled() { return nil }
            var delay = frameDelay(source: source, index: index)
            var end = index + 1
            while end < min(index + step, count) {
                delay += frameDelay(source: source, index: end)
                end += 1
            }
            if let image = stillFrame(source: source, index: index, maxPixelSize: maxPixelSize) {
                frames.append(image)
                delays.append(max(delay, minDelay))
            }
            index = end
        }

        guard !frames.isEmpty else { return nil }
        if frames.count == 1 { return frames[0] }

        let total = delays.reduce(0, +)
        guard total > 0 else {
            return UIImage.animatedImage(with: frames, duration: Double(frames.count) * defaultDelay)
        }

        if let expanded = expandFrames(frames: frames, delays: delays) {
            return UIImage.animatedImage(with: expanded, duration: total)
        }
        return UIImage.animatedImage(with: frames, duration: total)
    }

    nonisolated private static func stillFrame(
        source: CGImageSource,
        index: Int,
        maxPixelSize: CGFloat
    ) -> UIImage? {
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            index,
            thumbOptions as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return defaultDelay
        }
        let dict =
            (props[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            ?? (props[kCGImagePropertyWebPDictionary] as? [CFString: Any])
        guard let dict else { return defaultDelay }

        let unclamped = dict[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            ?? dict[kCGImagePropertyWebPUnclampedDelayTime] as? Double
        let clamped = dict[kCGImagePropertyGIFDelayTime] as? Double
            ?? dict[kCGImagePropertyWebPDelayTime] as? Double
        let raw = unclamped ?? clamped ?? defaultDelay
        return raw < minDelay ? defaultDelay : raw
    }

    /// Repeats frames by GCD of delays (centiseconds). Returns nil if too many slots.
    nonisolated static func expandFrames(frames: [UIImage], delays: [TimeInterval]) -> [UIImage]? {
        guard frames.count == delays.count, !frames.isEmpty else { return nil }
        let cents = delays.map { max(1, Int(($0 * 100).rounded())) }
        guard let gcd = cents.reduce(nil as Int?, { partial, value in
            guard let partial else { return value }
            return Self.gcd(partial, value)
        }), gcd > 0 else { return nil }

        let slotCount = cents.reduce(0) { $0 + $1 / gcd }
        guard slotCount > 0, slotCount <= maxSlotCount else { return nil }

        var expanded: [UIImage] = []
        expanded.reserveCapacity(slotCount)
        for (frame, cent) in zip(frames, cents) {
            let repeats = cent / gcd
            for _ in 0..<repeats {
                expanded.append(frame)
            }
        }
        return expanded
    }

    nonisolated private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let t = x % y
            x = y
            y = t
        }
        return x
    }
}

/// Memory cache for decoded animated images keyed by URL + max pixel size.
enum AnimatedImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    nonisolated static func key(url: URL, maxPixelSize: CGFloat) -> NSString {
        "\(url.absoluteString)|\(Int(maxPixelSize))" as NSString
    }

    nonisolated static func image(forKey key: NSString) -> UIImage? {
        cache.object(forKey: key)
    }

    nonisolated static func store(_ image: UIImage, forKey key: NSString) {
        let frames = max(image.images?.count ?? 1, 1)
        let pixel = image.cgImage.map { $0.width * $0.height } ?? Int(image.size.width * image.size.height)
        let cost = max(pixel, 1) * 4 * frames
        cache.setObject(image, forKey: key, cost: cost)
    }
}

/// Remote GIF/WebP that actually animates (Nuke alone only returns the first frame).
struct AnimatedRemoteImage: UIViewRepresentable {
    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFill
    var maxPixelSize: CGFloat = 480
    var onPixelSize: ((CGSize?) -> Void)?
    /// Polled between frames. The GIF grid sets this so a tab change aborts ImageIO.
    var stopsWhen: @Sendable () -> Bool = { false }
    var onReady: (() -> Void)?

    func makeUIView(context: Context) -> AnimatedImageUIView {
        let view = AnimatedImageUIView(frame: .zero)
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: AnimatedImageUIView, context: Context) {
        uiView.contentMode = contentMode
        let urlString = url.absoluteString
        guard context.coordinator.loadedURL != urlString
            || abs(context.coordinator.maxPixelSize - maxPixelSize) > 0.5 else {
            return
        }
        context.coordinator.loadedURL = urlString
        context.coordinator.maxPixelSize = maxPixelSize
        context.coordinator.cancelInFlight()
        uiView.prepareForReuse()

        let cacheKey = AnimatedImageCache.key(url: url, maxPixelSize: maxPixelSize)
        if let cached = AnimatedImageCache.image(forKey: cacheKey) {
            apply(cached, to: uiView)
            DispatchQueue.main.async { onReady?() }
            return
        }

        let request = ImageRequest(url: url)
        let flag = GIFDecodeCancel()
        context.coordinator.decodeCancel = flag
        let stopsWhen = stopsWhen
        let task = Task {
            do {
                let (data, _) = try await ImagePipeline.shared.data(for: request)
                guard !Task.isCancelled, !flag.isCancelled else { return }
                let decoded = await Task.detached(priority: .utility) {
                    AnimatedImageDecoder.make(data: data, maxPixelSize: maxPixelSize) {
                        flag.isCancelled || stopsWhen()
                    }
                }.value
                guard !Task.isCancelled, !flag.isCancelled, let decoded else {
                    await MainActor.run { onReady?() }
                    return
                }
                AnimatedImageCache.store(decoded, forKey: cacheKey)
                await MainActor.run {
                    guard context.coordinator.loadedURL == urlString else { return }
                    apply(decoded, to: uiView)
                    onReady?()
                }
            } catch is CancellationError {
                await MainActor.run { onReady?() }
            } catch {
                await MainActor.run {
                    guard context.coordinator.loadedURL == urlString else { return }
                    onPixelSize?(nil)
                    onReady?()
                }
            }
        }
        context.coordinator.task = task
    }

    static func dismantleUIView(_ uiView: AnimatedImageUIView, coordinator: Coordinator) {
        coordinator.cancelInFlight()
        uiView.prepareForReuse()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func apply(_ image: UIImage, to uiView: AnimatedImageUIView) {
        uiView.setAnimatedImage(image)
        let size = image.size
        let scale = image.scale
        onPixelSize?(CGSize(width: size.width * scale, height: size.height * scale))
    }

    final class Coordinator {
        var loadedURL: String?
        var maxPixelSize: CGFloat = 0
        var task: Task<Void, Never>?
        var decodeCancel: GIFDecodeCancel?

        func cancelInFlight() {
            decodeCancel?.cancel()
            decodeCancel = nil
            task?.cancel()
            task = nil
        }
    }
}

final class GIFDecodeCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

final class AnimatedImageUIView: UIImageView {
    private var fullAnimatedImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAnimatedImage(_ image: UIImage) {
        fullAnimatedImage = image
        applyMotionPreference()
    }

    func prepareForReuse() {
        stopAnimating()
        image = nil
        animationImages = nil
        fullAnimatedImage = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyMotionPreference()
    }

    private func applyMotionPreference() {
        guard let fullAnimatedImage else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if reduceMotion || window == nil {
            stopAnimating()
            image = fullAnimatedImage.images?.first ?? fullAnimatedImage
        } else {
            image = fullAnimatedImage
            if fullAnimatedImage.images != nil {
                startAnimating()
            }
        }
    }
}
