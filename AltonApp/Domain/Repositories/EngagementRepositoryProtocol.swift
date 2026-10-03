import Foundation

protocol EngagementRepositoryProtocol: Sendable {
    func toggleLike(postID: String) async throws -> ToggleResult
    func toggleBookmark(postID: String) async throws -> ToggleResult
    func toggleRepost(postID: String) async throws -> RepostResult
    func getShareURL(postID: String) async throws -> URL
    func recordShare(postID: String, channel: String) async throws -> ShareResult
    func recordView(postID: String, source: ViewSource, watchTimeMs: Int) async throws -> RecordViewResult
}

protocol CommentRepositoryProtocol: Sendable {
    func fetchComments(postID: String, cursor: String?, limit: Int) async throws -> CommentPage
    func fetchComment(id: String) async throws -> Comment
    func addComment(
        postID: String,
        content: String,
        showInFeed: Bool,
        parentCommentID: String?,
        stickerID: String?,
        pendingMedia: Bool,
        pendingGif: PendingCommentGif?
    ) async throws -> Comment
    func uploadCommentAttachments(commentID: String, attachments: [PostAttachment]) async throws
    func toggleCommentLike(commentID: String) async throws -> ToggleResult
    func deleteComment(commentID: String) async throws
}

protocol StickerRepositoryProtocol: Sendable {
    func fetchPacks() async throws -> [StickerPackSummary]
    func fetchPack(id: String) async throws -> StickerPackDetail
}

protocol PostActivityRepositoryProtocol: Sendable {
    func fetchActivity(postID: String) async throws -> PostActivity
    func fetchLikers(postID: String, cursor: String?, limit: Int) async throws -> PostLikerPage
}

protocol AnalyticsRepositoryProtocol: Sendable {
    func fetchPostAnalytics(postID: String, from: String?, to: String?) async throws -> PostAnalytics
    func fetchCreatorOverview(from: String?, to: String?) async throws -> CreatorOverview
}
