import CleverAdsSolutions
import Foundation

/// Holds one claimed native ad for a SwiftUI slot (content + impression/click callbacks).
@MainActor
final class CASNativeAdLoader: NSObject, ObservableObject {
    @Published private(set) var adContent: NativeAdContent?
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false

    var onClick: (() -> Void)?
    var onImpression: ((AdContentInfo) -> Void)?

    private let placementID: String
    private var didStart = false
    private var pollTask: Task<Void, Never>?

    init(placementID: String) {
        self.placementID = placementID
    }

    /// Prefer an already-preloaded ad; otherwise poll the pool.
    /// `maxAttempts` nil keeps waiting (shot pager must not die on a 5s miss).
    func attachFromPool(maxAttempts: Int? = 50) {
        if adContent != nil, adContent?.isExpired != true { return }
        if didStart, isLoading { return }
        didStart = true
        pollFromPool(maxAttempts: maxAttempts)
    }

    private func pollFromPool(maxAttempts: Int?) {
        pollTask?.cancel()

        if let ready = NativeAdPool.shared.claim(placementID: placementID) {
            adopt(ready)
            return
        }

        isLoading = true
        loadFailed = false
        NativeAdPool.shared.warmUp(placementID: placementID)

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var attempts = 0
            while !Task.isCancelled {
                if let ad = NativeAdPool.shared.claim(placementID: self.placementID) {
                    self.adopt(ad)
                    return
                }
                attempts += 1
                if let maxAttempts, attempts >= maxAttempts {
                    self.isLoading = false
                    self.loadFailed = true
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func destroyCurrentAd() {
        pollTask?.cancel()
        pollTask = nil
        adContent?.impressionDelegate = nil
        adContent?.delegate = nil
        adContent?.destroy()
        adContent = nil
        isLoading = false
        didStart = false
    }

    private func adopt(_ ad: NativeAdContent) {
        ad.delegate = self
        ad.impressionDelegate = self
        adContent = ad
        isLoading = false
        loadFailed = false
        NativeAdPool.shared.warmUp(placementID: placementID)
    }
}

extension CASNativeAdLoader: CASNativeContentDelegate {
    nonisolated func nativeAd(_ ad: NativeAdContent, didFailToPresentWithError error: AdError) {
        Task { @MainActor in
            PipelineLogger.media.error(
                "CAS native present failed: \(error.localizedDescription, privacy: .public)"
            )
            if adContent == nil || adContent?.isExpired == true {
                loadFailed = true
            }
        }
    }

    nonisolated func nativeAdDidClickContent(_ ad: NativeAdContent) {
        Task { @MainActor in
            onClick?()
        }
    }
}

extension CASNativeAdLoader: CASImpressionDelegate {
    nonisolated func adDidRecordImpression(info: AdContentInfo) {
        Task { @MainActor in
            onImpression?(info)
        }
    }
}
