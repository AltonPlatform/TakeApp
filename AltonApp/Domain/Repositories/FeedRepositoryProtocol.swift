import Foundation

protocol FeedRepositoryProtocol: Sendable {
    func fetchFeed(cursor: String?, limit: Int, mode: String?) async throws -> FeedPage
}
