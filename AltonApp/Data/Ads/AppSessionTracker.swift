import Foundation

/// Tracks app session lifecycle against `/sessions/*` gateway endpoints.
@MainActor
final class AppSessionTracker {
    static let shared = AppSessionTracker()

    private var apiClient: APIClient?
    private(set) var sessionID: String?

    private init() {}

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func startSession() async {
        guard let apiClient else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        do {
            let response: StartSessionResponseDTO = try await apiClient.authorizedRequest(
                .startSession,
                body: StartSessionBodyDTO(platform: "ios", appVersion: version)
            )
            sessionID = response.sessionID
        } catch {
            // Non-fatal on launch.
        }
    }

    func endSession() async {
        guard let apiClient, let sessionID else { return }
        do {
            let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
                .endSession,
                body: EndSessionBodyDTO(sessionID: sessionID)
            )
        } catch {
            // Ignore end failures.
        }
        self.sessionID = nil
    }

    func recordActivity(_ activityType: String) async {
        guard let apiClient, let sessionID else { return }
        do {
            let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
                .recordActivity,
                body: SessionActivityBodyDTO(sessionID: sessionID, activityType: activityType)
            )
        } catch {}
    }
}
