import Foundation
import Nuke

/// Prefetches feed thumbnails and nearby full-resolution images via Nuke.
///
/// Thumb requests use the same `.resize(width: 512)` processor as `HugPhoto`
/// so they share Nuke cache keys with the feed strip.
///
/// Thumb policy: `prefetchThumbs` only **adds**/starts work (union). Call
/// `retainThumbs` to cancel scrolled-past URLs, or `stopAll` on feed reset.
/// That way `loadInitial` page warmup is not torn down by the first `onAppear`.
@MainActor
final class FeedImagePrefetcher {
    static let shared = FeedImagePrefetcher()

    private static let thumbProcessors: [any ImageProcessing] = [ImageProcessors.Resize(width: 512)]

    private let thumbPrefetcher: ImagePrefetcher
    private let fullPrefetcher: ImagePrefetcher

    private var activeThumbRequests: [ImageRequest] = []
    private var activeFullRequests: [ImageRequest] = []

    private init() {
        thumbPrefetcher = ImagePrefetcher(pipeline: .shared)
        thumbPrefetcher.priority = .normal
        fullPrefetcher = ImagePrefetcher(pipeline: .shared)
        fullPrefetcher.priority = .low
    }

    /// Start prefetching thumbs (union with in-flight). Empty is a no-op.
    func prefetchThumbs(_ urls: [URL]) {
        let unique = Self.uniqueURLs(urls)
        guard !unique.isEmpty else { return }
        let requests = unique.map(Self.thumbRequest)
        let existingKeys = Set(activeThumbRequests.map(Self.requestKey))
        let fresh = requests.filter { !existingKeys.contains(Self.requestKey($0)) }
        if !fresh.isEmpty {
            thumbPrefetcher.startPrefetching(with: fresh)
        }
        // Merge: keep previous order, append newly started.
        var merged = activeThumbRequests
        let mergedKeys = Set(merged.map(Self.requestKey))
        for request in requests where !mergedKeys.contains(Self.requestKey(request)) {
            merged.append(request)
        }
        activeThumbRequests = merged
    }

    /// Cancel thumb prefetches whose URLs are not in `urls` (e.g. scrolled past).
    /// Empty is a no-op so a reply-only slice does not wipe remaining warmup.
    func retainThumbs(_ urls: [URL]) {
        let keepKeys = Set(Self.uniqueURLs(urls).map { Self.requestKey(Self.thumbRequest($0)) })
        guard !keepKeys.isEmpty else { return }
        let stale = activeThumbRequests.filter { !keepKeys.contains(Self.requestKey($0)) }
        if !stale.isEmpty {
            thumbPrefetcher.stopPrefetching(with: stale)
            activeThumbRequests.removeAll { !keepKeys.contains(Self.requestKey($0)) }
        }
    }

    /// Prefetch full images / GIF / comment media (sliding window; replaces previous set).
    /// Empty is a no-op; call `stopAll()` to cancel on feed reset.
    func prefetchFull(_ urls: [URL]) {
        let unique = Self.uniqueURLs(urls)
        guard !unique.isEmpty else { return }
        let requests = unique.map { url in
            ImageRequest(url: url, priority: .low)
        }
        replaceActive(
            prefetcher: fullPrefetcher,
            previous: &activeFullRequests,
            next: requests
        )
    }

    func stopAll() {
        thumbPrefetcher.stopPrefetching()
        fullPrefetcher.stopPrefetching()
        activeThumbRequests = []
        activeFullRequests = []
    }

    private func replaceActive(
        prefetcher: ImagePrefetcher,
        previous: inout [ImageRequest],
        next: [ImageRequest]
    ) {
        let nextKeys = Set(next.map(Self.requestKey))
        let stale = previous.filter { !nextKeys.contains(Self.requestKey($0)) }
        if !stale.isEmpty {
            prefetcher.stopPrefetching(with: stale)
        }
        if !next.isEmpty {
            prefetcher.startPrefetching(with: next)
        }
        previous = next
    }

    private static func thumbRequest(_ url: URL) -> ImageRequest {
        ImageRequest(url: url, processors: thumbProcessors, priority: .normal)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    private static func requestKey(_ request: ImageRequest) -> String {
        let url = request.imageId ?? ""
        let processors = request.processors.map(\.identifier).joined(separator: "|")
        return "\(url)#\(processors)"
    }
}
