import Foundation
import Observation

@MainActor
@Observable
final class PostEngagementController {
    var shareURL: URL?
    var showComments = false
    var showShareSheet = false
    var errorMessage: String?

    private let engagementUseCase: EngagementUseCase
    private let commentsUseCase: CommentsUseCase
    private var onPostUpdated: ((Post) -> Void)?

    init(engagementUseCase: EngagementUseCase, commentsUseCase: CommentsUseCase) {
        self.engagementUseCase = engagementUseCase
        self.commentsUseCase = commentsUseCase
    }

    func bind(onPostUpdated: @escaping (Post) -> Void) {
        self.onPostUpdated = onPostUpdated
    }

    @discardableResult
    func toggleLike(for post: Post) async -> Post {
        let previous = post
        let optimistic = post.updatingEngagement(
            likeCount: post.likeCount + (post.isLiked ? -1 : 1),
            isLiked: !post.isLiked
        )
        onPostUpdated?(optimistic)

        do {
            let result = try await engagementUseCase.toggleLike(postID: post.id)
            let updated = previous.updatingEngagement(likeCount: result.count, isLiked: result.active)
            onPostUpdated?(updated)
            return updated
        } catch {
            onPostUpdated?(previous)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return previous
        }
    }

    @discardableResult
    func toggleBookmark(for post: Post) async -> Post {
        let previous = post
        let optimistic = post.updatingEngagement(
            saveCount: post.saveCount + (post.isBookmarked ? -1 : 1),
            isBookmarked: !post.isBookmarked
        )
        onPostUpdated?(optimistic)

        do {
            let result = try await engagementUseCase.toggleBookmark(postID: post.id)
            let updated = previous.updatingEngagement(saveCount: result.count, isBookmarked: result.active)
            onPostUpdated?(updated)
            return updated
        } catch {
            onPostUpdated?(previous)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return previous
        }
    }

    @discardableResult
    func toggleRepost(for post: Post) async -> Post {
        let previous = post
        let optimistic = post.updatingEngagement(
            repostCount: post.repostCount + (post.isReposted ? -1 : 1),
            isReposted: !post.isReposted
        )
        onPostUpdated?(optimistic)

        do {
            let result = try await engagementUseCase.toggleRepost(postID: post.id)
            let updated = previous.updatingEngagement(repostCount: result.count, isReposted: result.active)
            onPostUpdated?(updated)
            return updated
        } catch {
            onPostUpdated?(previous)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return previous
        }
    }

    @discardableResult
    func prepareShare(postID: String) async -> Bool {
        do {
            shareURL = try await engagementUseCase.getShareURL(postID: postID)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func completeShare(post: Post, channel: String = "external") async -> Post {
        do {
            let result = try await engagementUseCase.recordShare(postID: post.id, channel: channel)
            if result.newlyRecorded {
                let updated = post.updatingEngagement(shareCount: result.shareCount)
                onPostUpdated?(updated)
                return updated
            }
            return post
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return post
        }
    }

    /// Builds a share payload from the last prepared URL and post metadata.
    func makeSharePayload(for post: Post) -> PostSharePayload? {
        guard let url = shareURL else { return nil }
        return PostSharePayload(
            url: url,
            textExcerpt: post.content,
            username: post.creatorUsername,
            posterURL: post.thumbnailURL ?? post.playbackURL,
            localVideoURL: nil,
            postID: post.id
        )
    }

    @discardableResult
    func share(post: Post, channel: String = "external") async -> Post {
        do {
            let result = try await engagementUseCase.recordShare(postID: post.id, channel: channel)
            shareURL = result.shareURL
            if result.newlyRecorded {
                let updated = post.updatingEngagement(shareCount: result.shareCount)
                onPostUpdated?(updated)
                return updated
            }
            return post
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return post
        }
    }

    func recordView(postID: String, source: ViewSource, watchTimeMs: Int = 0) async {
        _ = try? await engagementUseCase.recordView(
            postID: postID,
            source: source,
            watchTimeMs: watchTimeMs
        )
    }
}
