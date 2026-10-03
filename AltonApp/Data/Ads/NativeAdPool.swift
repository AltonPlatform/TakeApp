import CleverAdsSolutions
import Foundation

/// Preloads CAS native ads so feed slots bind instantly instead of loading on appear.
@MainActor
final class NativeAdPool: NSObject {
    static let shared = NativeAdPool()

    /// Matches `TakesFeedViewModel` default placement. Also the CAS inventory
    /// used by shot-feed slots — demo/test creatives fill this placement.
    nonisolated static let feedPlacementID = "feed_native"
    /// Alton analytics / monetization placement for the shot feed.
    nonisolated static let shotFeedPlacementID = "shot_feed_native"

    /// CAS only fills `feed_native` in demo/test mode. Shot slots still report
    /// `shot_feed_native` to our backend, but claim creatives from this pool.
    nonisolated static let casNativePlacementID = feedPlacementID

    private let targetReadyCount = 3
    private var queues: [String: [NativeAdContent]] = [:]
    private var loaders: [String: CASNativeLoader] = [:]
    private var isFilling: [String: Bool] = [:]

    private override init() {
        super.init()
    }

    /// Keep a small ready queue (call after CAS is ready / when feed opens).
    func warmUp(placementID: String = NativeAdPool.feedPlacementID) {
        fillIfNeeded(placementID: placementID)
    }

    /// Number of non-expired creatives ready to claim.
    func readyCount(placementID: String) -> Int {
        purgeExpired(placementID: placementID)
        return queues[placementID]?.count ?? 0
    }

    /// Pop a ready ad if available and refill the queue in the background.
    func claim(placementID: String) -> NativeAdContent? {
        purgeExpired(placementID: placementID)
        guard var queue = queues[placementID], !queue.isEmpty else {
            fillIfNeeded(placementID: placementID)
            return nil
        }
        let ad = queue.removeFirst()
        queues[placementID] = queue
        fillIfNeeded(placementID: placementID)
        return ad
    }

    private func fillIfNeeded(placementID: String) {
        purgeExpired(placementID: placementID)
        let ready = queues[placementID]?.count ?? 0
        let needed = targetReadyCount - ready
        guard needed > 0 else { return }
        guard isFilling[placementID] != true else { return }

        let loader: CASNativeLoader
        if let existing = loaders[placementID] {
            guard !existing.isAdLoading else { return }
            loader = existing
        } else {
            let created = CASNativeLoader(casID: CASManager.casID)
            created.delegate = self
            created.adChoicesPlacement = .topRight
            created.isStartVideoMuted = true
            loaders[placementID] = created
            loader = created
        }

        isFilling[placementID] = true
        loader.placement = placementID

        if needed == 1 {
            loader.loadAd()
        } else {
            loader.load(maxNumberOfAds: needed)
        }
    }

    private func purgeExpired(placementID: String) {
        guard let queue = queues[placementID] else { return }
        let alive = queue.filter { !$0.isExpired }
        for dead in queue where dead.isExpired {
            dead.destroy()
        }
        queues[placementID] = alive
    }

    private func finishLoading(placementID: String) {
        isFilling[placementID] = false
        fillIfNeeded(placementID: placementID)
    }

    private func currentFillingPlacementID() -> String {
        isFilling.first(where: \.value)?.key ?? Self.feedPlacementID
    }
}

extension NativeAdPool: CASNativeLoaderDelegate {
    nonisolated func nativeAdDidLoadContent(_ ad: NativeAdContent) {
        Task { @MainActor in
            let placementID = currentFillingPlacementID()
            queues[placementID, default: []].append(ad)
            if loaders[placementID]?.isAdLoading != true {
                finishLoading(placementID: placementID)
            }
        }
    }

    nonisolated func nativeAdDidFailToLoad(error: AdError) {
        Task { @MainActor in
            PipelineLogger.media.error(
                "CAS native pool load failed: \(error.localizedDescription, privacy: .public)"
            )
            for (placementID, filling) in isFilling where filling {
                if loaders[placementID]?.isAdLoading != true {
                    finishLoading(placementID: placementID)
                }
            }
        }
    }
}

/// Keeps one `CASNativeAdLoader` per shot-feed slot so pager reconfigure
/// does not drop a claimed creative or restart the attach loop.
@MainActor
final class NativeAdSlotCache {
    static let shared = NativeAdSlotCache()

    private var loaders: [String: CASNativeAdLoader] = [:]

    private init() {}

    func loader(slotID: String, casPlacementID: String) -> CASNativeAdLoader {
        if let existing = loaders[slotID] {
            return existing
        }
        let created = CASNativeAdLoader(placementID: casPlacementID)
        loaders[slotID] = created
        return created
    }

    func releaseAll() {
        for loader in loaders.values {
            loader.destroyCurrentAd()
        }
        loaders.removeAll()
    }
}
