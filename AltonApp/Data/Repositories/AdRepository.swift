import Foundation

protocol AdRepositoryProtocol: Sendable {
    func fetchPlacements(placement: String?) async throws -> [AdPlacement]
    func recordImpression(
        placementID: String,
        adUnitID: String,
        feedSessionID: String?,
        postIDAdjacent: String?,
        source: String
    ) async throws -> String?
    func recordClick(impressionID: String) async throws
    func recordRevenue(
        impressionID: String,
        adNetwork: String,
        ecpmUsd: Double,
        revenueUsd: Double,
        currency: String,
        adjacentPostIDs: [String]
    ) async throws
    func fetchMonetizationConfig() async throws -> MonetizationConfig
}

final class AdRepository: AdRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchPlacements(placement: String? = nil) async throws -> [AdPlacement] {
        let response: AdPlacementsResponseDTO = try await apiClient.authorizedRequest(
            .adPlacements(placement: placement)
        )
        return response.placements.map { $0.toDomain() }
    }

    func recordImpression(
        placementID: String,
        adUnitID: String,
        feedSessionID: String?,
        postIDAdjacent: String?,
        source: String
    ) async throws -> String? {
        let response: RecordAdImpressionResponseDTO = try await apiClient.authorizedRequest(
            .recordAdImpression,
            body: RecordAdImpressionBodyDTO(
                placementID: placementID,
                adUnitID: adUnitID,
                feedSessionID: feedSessionID,
                postIDAdjacent: postIDAdjacent,
                source: source
            )
        )
        return response.impressionID
    }

    func recordClick(impressionID: String) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
            .recordAdClick,
            body: RecordAdClickBodyDTO(impressionID: impressionID)
        )
    }

    func recordRevenue(
        impressionID: String,
        adNetwork: String,
        ecpmUsd: Double,
        revenueUsd: Double,
        currency: String,
        adjacentPostIDs: [String]
    ) async throws {
        let _: SuccessResponseDTO = try await apiClient.authorizedRequest(
            .recordAdRevenue,
            body: RecordAdRevenueBodyDTO(
                impressionID: impressionID,
                adNetwork: adNetwork,
                ecpmUsd: ecpmUsd,
                revenueUsd: revenueUsd,
                currency: currency,
                adjacentPostIDs: adjacentPostIDs
            )
        )
    }

    func fetchMonetizationConfig() async throws -> MonetizationConfig {
        let response: MonetizationConfigResponseDTO = try await apiClient.authorizedRequest(.monetizationConfig)
        return response.toDomain()
    }
}
