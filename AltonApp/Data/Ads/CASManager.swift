import CleverAdsSolutions
import Foundation

/// CAS.AI mediation bootstrap for native ads.
/// Docs: https://docs.page/cleveradssolutions/docs/iOS/Initialize-CAS
@MainActor
final class CASManager {
    static let shared = CASManager()

    /// Demo CAS ID serves test creatives without a production account.
    /// Replace with App Store / CAS dashboard ID before shipping live ads.
    static var casID: String {
        #if ALTON_DEV || DEBUG
        return "demo"
        #else
        return Bundle.main.bundleIdentifier ?? "com.alton.altonApp"
        #endif
    }

    private(set) var isInitialized = false
    private(set) var isReady = false
    private(set) var lastInitError: String?

    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    /// Initializes CAS once at launch. Enables test ad mode on Debug / Staging.
    func initialize() {
        guard !isInitialized else { return }
        isInitialized = true

        let builder = CAS.buildManager()
        builder.withCompletionHandler { [weak self] config in
            Task { @MainActor in
                guard let self else { return }
                self.lastInitError = config.error
                self.isReady = config.error == nil
                if let error = config.error {
                    PipelineLogger.media.error("CAS init error: \(error, privacy: .public)")
                } else {
                    PipelineLogger.media.debug(
                        "CAS initialized sdk=\(CAS.getSDKVersion(), privacy: .public) country=\(config.countryCode ?? "-", privacy: .public)"
                    )
                    // Prefetch before the user scrolls to an ad slot.
                    NativeAdPool.shared.warmUp(placementID: NativeAdPool.feedPlacementID)
                }
                let waiters = self.readyWaiters
                self.readyWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }

        #if ALTON_DEV || DEBUG
        builder.withTestAdMode(true)
        #endif

        // Consent flow stays enabled; ATT is requested separately via ATTConsentManager.
        builder.create(withCasId: Self.casID)
    }

    func waitUntilReady() async {
        if isReady || lastInitError != nil { return }
        if !isInitialized {
            initialize()
        }
        await withCheckedContinuation { continuation in
            readyWaiters.append(continuation)
        }
    }
}
