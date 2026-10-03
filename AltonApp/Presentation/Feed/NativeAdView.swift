import CleverAdsSolutions
import SwiftUI

/// Feed native ad slot backed by CAS.AI (`NativeAdPool` + post-like `NativeAdPostCard`).
struct NativeAdView: View {
    let placementID: String
    let adRepository: AdRepository
    var adjacentPostID: String? = nil
    var feedSessionID: String? = nil

    @StateObject private var loader: CASNativeAdLoader
    @State private var impressionID: String?
    @State private var didRecordImpression = false
    @State private var didWireCallbacks = false

    init(
        placementID: String,
        adRepository: AdRepository,
        adjacentPostID: String? = nil,
        feedSessionID: String? = nil
    ) {
        self.placementID = placementID
        self.adRepository = adRepository
        self.adjacentPostID = adjacentPostID
        self.feedSessionID = feedSessionID
        _loader = StateObject(wrappedValue: CASNativeAdLoader(placementID: placementID))
    }

    var body: some View {
        Group {
            if let ad = loader.adContent, !ad.isExpired {
                NativeAdPostCardRepresentable(adContent: ad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if loader.loadFailed {
                EmptyView()
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }
        }
        .task {
            if !didWireCallbacks {
                didWireCallbacks = true
                wireCallbacks()
            }
            await CASManager.shared.waitUntilReady()
            NativeAdPool.shared.warmUp(placementID: placementID)
            loader.attachFromPool()
        }
    }

    private func wireCallbacks() {
        loader.onImpression = { info in
            Task { await recordImpressionIfNeeded(info: info) }
        }
        loader.onClick = {
            Task { await recordClickIfNeeded() }
        }
    }

    private func recordImpressionIfNeeded(info: AdContentInfo) async {
        guard !didRecordImpression else { return }
        didRecordImpression = true
        let adUnitID = info.sourceUnitID.isEmpty
            ? "cas.\(placementID)"
            : info.sourceUnitID
        impressionID = try? await adRepository.recordImpression(
            placementID: placementID,
            adUnitID: adUnitID,
            feedSessionID: feedSessionID,
            postIDAdjacent: adjacentPostID,
            source: "feed"
        )

        if let impressionID, !impressionID.isEmpty, info.revenue > 0 {
            try? await adRepository.recordRevenue(
                impressionID: impressionID,
                adNetwork: info.sourceName.isEmpty ? "cas.ai" : info.sourceName,
                ecpmUsd: info.revenue * 1000,
                revenueUsd: info.revenue,
                currency: "USD",
                adjacentPostIDs: adjacentPostID.map { [$0] } ?? []
            )
        }
    }

    private func recordClickIfNeeded() async {
        guard let impressionID, !impressionID.isEmpty else { return }
        try? await adRepository.recordClick(impressionID: impressionID)
    }
}

/// Full-screen shot-feed native ad slot backed by CAS.AI.
struct NativeAdShotView: View {
    let placementID: String
    let position: Int
    let adRepository: AdRepository
    var adjacentPostID: String? = nil
    var feedSessionID: String? = nil
    var isActive: Bool = false
    var isPreloading: Bool = false

    @ObservedObject private var loader: CASNativeAdLoader
    @State private var impressionID: String?
    @State private var didRecordImpression = false
    @State private var didWireCallbacks = false

    init(
        placementID: String,
        position: Int,
        adRepository: AdRepository,
        adjacentPostID: String? = nil,
        feedSessionID: String? = nil,
        isActive: Bool = false,
        isPreloading: Bool = false
    ) {
        self.placementID = placementID
        self.position = position
        self.adRepository = adRepository
        self.adjacentPostID = adjacentPostID
        self.feedSessionID = feedSessionID
        self.isActive = isActive
        self.isPreloading = isPreloading
        // CAS demo inventory fills `feed_native`. Keep `placementID` for Alton analytics.
        _loader = ObservedObject(
            wrappedValue: NativeAdSlotCache.shared.loader(
                slotID: "ad-\(placementID)-\(position)",
                casPlacementID: NativeAdPool.casNativePlacementID
            )
        )
    }

    private var shouldPresentAd: Bool {
        isActive || isPreloading
    }

    var body: some View {
        ZStack {
            Color.black
            if let ad = loader.adContent, !ad.isExpired, shouldPresentAd {
                NativeAdShotCardRepresentable(adContent: ad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shouldPresentAd {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if !didWireCallbacks {
                didWireCallbacks = true
                wireCallbacks()
            }
            await CASManager.shared.waitUntilReady()
            NativeAdPool.shared.warmUp(placementID: NativeAdPool.casNativePlacementID)
            loader.attachFromPool(maxAttempts: nil)
        }
    }

    private func wireCallbacks() {
        loader.onImpression = { info in
            Task { await recordImpressionIfNeeded(info: info) }
        }
        loader.onClick = {
            Task { await recordClickIfNeeded() }
        }
    }

    private func recordImpressionIfNeeded(info: AdContentInfo) async {
        guard !didRecordImpression else { return }
        didRecordImpression = true
        let adUnitID = info.sourceUnitID.isEmpty
            ? "cas.\(placementID)"
            : info.sourceUnitID
        impressionID = try? await adRepository.recordImpression(
            placementID: placementID,
            adUnitID: adUnitID,
            feedSessionID: feedSessionID,
            postIDAdjacent: adjacentPostID,
            source: "shot_feed"
        )

        if let impressionID, !impressionID.isEmpty, info.revenue > 0 {
            try? await adRepository.recordRevenue(
                impressionID: impressionID,
                adNetwork: info.sourceName.isEmpty ? "cas.ai" : info.sourceName,
                ecpmUsd: info.revenue * 1000,
                revenueUsd: info.revenue,
                currency: "USD",
                adjacentPostIDs: adjacentPostID.map { [$0] } ?? []
            )
        }
    }

    private func recordClickIfNeeded() async {
        guard let impressionID, !impressionID.isEmpty else { return }
        try? await adRepository.recordClick(impressionID: impressionID)
    }
}
