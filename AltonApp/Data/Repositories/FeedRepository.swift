import Foundation

final class FeedRepository: FeedRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchFeed(cursor: String?, limit: Int, mode: String? = nil) async throws -> FeedPage {
        let response: FeedResponseDTO = try await apiClient.authorizedRequest(
            .feed(cursor: cursor, limit: limit, mode: mode)
        )
        return FeedPage(
            items: response.items.compactMap { $0.toDomain() },
            nextCursor: response.nextCursor,
            adSlots: (response.adSlots ?? []).map { $0.toDomain() }
        )
    }
}
