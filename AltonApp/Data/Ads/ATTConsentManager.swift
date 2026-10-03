import AppTrackingTransparency
import Foundation

/// Requests App Tracking Transparency authorization and syncs status to the backend.
@MainActor
final class ATTConsentManager {
    static let shared = ATTConsentManager()

    private var apiClient: APIClient?
    private(set) var lastStatus: ATTrackingManager.AuthorizationStatus = .notDetermined

    private init() {}

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    @discardableResult
    func requestTrackingAuthorization() async -> ATTrackingManager.AuthorizationStatus {
        let status = await ATTrackingManager.requestTrackingAuthorization()
        lastStatus = status
        AnalyticsReporting.applyTrackingConsent(status)
        await syncConsent(status: status)
        return status
    }

    private func syncConsent(status: ATTrackingManager.AuthorizationStatus) async {
        guard let apiClient else { return }
        let value: String
        switch status {
        case .authorized: value = "authorized"
        case .denied: value = "denied"
        case .restricted: value = "restricted"
        case .notDetermined: value = "not_determined"
        @unknown default: value = "unknown"
        }
        do {
            let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
                .updateAttConsent,
                body: AttConsentBodyDTO(status: value)
            )
        } catch {
            // Non-fatal: ATT sync should not block launch.
        }
    }
}
