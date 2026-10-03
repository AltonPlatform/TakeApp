import Foundation

struct EngagementUseCase: Sendable {
    private let repository: EngagementRepositoryProtocol

    init(repository: EngagementRepositoryProtocol) {
        self.repository = repository
    }

    func toggleLike(postID: String) async throws -> ToggleResult {
        try await repository.toggleLike(postID: postID)
    }

    func toggleBookmark(postID: String) async throws -> ToggleResult {
        try await repository.toggleBookmark(postID: postID)
    }

    func toggleRepost(postID: String) async throws -> RepostResult {
        try await repository.toggleRepost(postID: postID)
    }

    func recordShare(postID: String, channel: String = "external") async throws -> ShareResult {
        try await repository.recordShare(postID: postID, channel: channel)
    }

    func getShareURL(postID: String) async throws -> URL {
        try await repository.getShareURL(postID: postID)
    }

    func recordView(postID: String, source: ViewSource, watchTimeMs: Int = 0) async throws -> RecordViewResult {
        try await repository.recordView(postID: postID, source: source, watchTimeMs: watchTimeMs)
    }
}

struct CommentsUseCase: Sendable {
    static let maxAttachments = 4

    private let repository: CommentRepositoryProtocol

    init(repository: CommentRepositoryProtocol) {
        self.repository = repository
    }

    func fetchComments(postID: String, cursor: String? = nil, limit: Int = 100) async throws -> CommentPage {
        try await repository.fetchComments(postID: postID, cursor: cursor, limit: limit)
    }

    func addComment(
        postID: String,
        content: String,
        showInFeed: Bool = true,
        parentCommentID: String? = nil,
        attachments: [PostAttachment] = [],
        stickerID: String? = nil,
        pendingGif: PendingCommentGif? = nil
    ) async throws -> Comment {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSticker = stickerID.map { !$0.isEmpty } ?? false
        let hasGif = pendingGif != nil
        guard !trimmed.isEmpty || !attachments.isEmpty || hasSticker || hasGif else {
            throw APIError.validation("Comment cannot be empty.")
        }
        guard !(hasSticker && hasGif) else {
            throw APIError.validation("A comment cannot include both a sticker and a GIF.")
        }
        guard attachments.count <= Self.maxAttachments else {
            throw APIError.validation("Comments support up to \(Self.maxAttachments) images.")
        }

        var comment = try await repository.addComment(
            postID: postID,
            content: trimmed,
            showInFeed: showInFeed,
            parentCommentID: parentCommentID,
            stickerID: stickerID,
            pendingMedia: !attachments.isEmpty,
            pendingGif: pendingGif
        )

        if !attachments.isEmpty {
            try await repository.uploadCommentAttachments(commentID: comment.id, attachments: attachments)
            comment = try await waitForProcessedCommentImages(
                commentID: comment.id,
                expectedCount: attachments.count
            )
        }

        return comment
    }

    func toggleCommentLike(commentID: String) async throws -> ToggleResult {
        try await repository.toggleCommentLike(commentID: commentID)
    }

    func deleteComment(commentID: String) async throws {
        try await repository.deleteComment(commentID: commentID)
    }

    private func waitForProcessedCommentImages(commentID: String, expectedCount: Int) async throws -> Comment {
        let timeout = Date().addingTimeInterval(90)
        var last = try await repository.fetchComment(id: commentID)

        while Date() < timeout {
            if processedImageCount(in: last) >= expectedCount {
                return last
            }
            try await Task.sleep(for: .milliseconds(600))
            last = try await repository.fetchComment(id: commentID)
        }

        if processedImageCount(in: last) >= expectedCount {
            return last
        }
        throw APIError.validation("Image processing timed out. Try again later.")
    }

    private func processedImageCount(in comment: Comment) -> Int {
        if let mediaKey = comment.mediaKey, !mediaKey.isEmpty {
            let keys = mediaKey
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let processed = keys.filter { $0.hasPrefix("media/") || $0.hasPrefix("http") }
            if !processed.isEmpty {
                return processed.count
            }
            let raw = keys.filter { $0.hasPrefix("raw-uploads/") }
            if raw.count < keys.count {
                return keys.count - raw.count
            }
        }
        return comment.imageURLs.count
    }
}

struct PostAnalyticsUseCase: Sendable {
    private let repository: AnalyticsRepositoryProtocol

    init(repository: AnalyticsRepositoryProtocol) {
        self.repository = repository
    }

    func fetchAnalytics(postID: String, from: String? = nil, to: String? = nil) async throws -> PostAnalytics {
        try await repository.fetchPostAnalytics(postID: postID, from: from, to: to)
    }

    func fetchCreatorOverview(from: String? = nil, to: String? = nil) async throws -> CreatorOverview {
        try await repository.fetchCreatorOverview(from: from, to: to)
    }
}

struct PostActivityUseCase: Sendable {
    private let repository: PostActivityRepositoryProtocol

    init(repository: PostActivityRepositoryProtocol) {
        self.repository = repository
    }

    func fetchActivity(postID: String) async throws -> PostActivity {
        try await repository.fetchActivity(postID: postID)
    }

    func fetchLikers(postID: String, cursor: String? = nil, limit: Int = 20) async throws -> PostLikerPage {
        try await repository.fetchLikers(postID: postID, cursor: cursor, limit: limit)
    }
}

struct StickersUseCase: Sendable {
    private let repository: StickerRepositoryProtocol

    init(repository: StickerRepositoryProtocol) {
        self.repository = repository
    }

    func fetchPacks() async throws -> [StickerPackSummary] {
        try await repository.fetchPacks()
    }

    func fetchPack(id: String) async throws -> StickerPackDetail {
        try await repository.fetchPack(id: id)
    }
}
