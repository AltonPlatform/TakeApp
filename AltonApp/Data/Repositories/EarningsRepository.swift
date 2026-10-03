import Foundation

protocol EarningsRepositoryProtocol: Sendable {
    func fetchCreatorOverview(from: String?, to: String?) async throws -> CreatorOverview
    func fetchCreatorBalance() async throws -> CreatorBalance
    func requestPayout(amountUsd: Double) async throws -> Payout
    func listPayouts(cursor: String?, limit: Int) async throws -> (payouts: [Payout], nextCursor: String?)
}

final class EarningsRepository: EarningsRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchCreatorOverview(from: String?, to: String?) async throws -> CreatorOverview {
        let response: CreatorOverviewResponseDTO = try await apiClient.authorizedRequest(
            .creatorOverview(from: from, to: to)
        )
        return response.toDomain()
    }

    func fetchCreatorBalance() async throws -> CreatorBalance {
        let response: CreatorBalanceResponseDTO = try await apiClient.authorizedRequest(.creatorBalance)
        return response.toDomain()
    }

    func requestPayout(amountUsd: Double) async throws -> Payout {
        let response: PayoutResponseDTO = try await apiClient.authorizedRequest(
            .requestPayout,
            body: RequestPayoutBodyDTO(amountUsd: amountUsd)
        )
        return response.toDomain()
    }

    func listPayouts(cursor: String?, limit: Int) async throws -> (payouts: [Payout], nextCursor: String?) {
        let response: ListPayoutsResponseDTO = try await apiClient.authorizedRequest(
            .listPayouts(cursor: cursor, limit: limit)
        )
        return (response.payouts.map { $0.toDomain() }, response.nextCursor)
    }
}
