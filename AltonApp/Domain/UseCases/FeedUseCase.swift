import Foundation

enum FeedMode: String, Sendable {
    case forYou
    case following

    var apiValue: String? {
        switch self {
        case .forYou: return nil
        case .following: return "following"
        }
    }
}

@MainActor
final class FeedUseCase {
    private let repository: FeedRepositoryProtocol

    init(repository: FeedRepositoryProtocol) {
        self.repository = repository
    }

    func fetchTakes(
        cursor: String?,
        limit: Int = AppEnvironment.current.defaultFeedLimit,
        mode: FeedMode = .forYou
    ) async throws -> FeedPage {
        let page = try await repository.fetchFeed(cursor: cursor, limit: limit, mode: mode.apiValue)
        let takes = page.items.compactMap { item -> FeedTimelineItem? in
            switch item {
            case .post(let feedItem) where feedItem.post.postType == .take:
                return .post(feedItem)
            case .reply:
                return item
            default:
                return nil
            }
        }
        return FeedPage(items: takes, nextCursor: page.nextCursor, adSlots: page.adSlots)
    }

    func fetchShots(
        cursor: String?,
        limit: Int = AppEnvironment.current.defaultFeedLimit,
        mode: FeedMode = .forYou
    ) async throws -> ShotFeedPage {
        let page = try await repository.fetchFeed(cursor: cursor, limit: limit, mode: mode.apiValue)
        let shots = page.items.compactMap { item -> FeedItem? in
            if case .post(let feedItem) = item, feedItem.post.postType == .shot {
                return feedItem
            }
            return nil
        }
        return ShotFeedPage(items: shots, nextCursor: page.nextCursor, adSlots: page.adSlots)
    }
}
