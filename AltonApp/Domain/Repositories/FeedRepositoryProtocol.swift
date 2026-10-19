import Foundation

protocol FeedRepositoryProtocol: Sendable {
    func fetchFeed(cursor: String?, limit: Int, mode: String?, postType: String?) async throws -> FeedPage
}
