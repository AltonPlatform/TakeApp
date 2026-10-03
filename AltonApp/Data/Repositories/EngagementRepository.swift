import Foundation

final class EngagementRepository: EngagementRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func toggleLike(postID: String) async throws -> ToggleResult {
        let response: ToggleResponseDTO = try await apiClient.authorizedRequest(.toggleLike(postID: postID))
        return ToggleResult(active: response.active, count: Int(response.count))
    }

    func toggleBookmark(postID: String) async throws -> ToggleResult {
        let response: ToggleResponseDTO = try await apiClient.authorizedRequest(.toggleBookmark(postID: postID))
        return ToggleResult(active: response.active, count: Int(response.count))
    }

    func toggleRepost(postID: String) async throws -> RepostResult {
        let response: RepostResponseDTO = try await apiClient.authorizedRequest(.toggleRepost(postID: postID))
        return RepostResult(
            active: response.active,
            count: Int(response.count),
            repostID: response.repostID
        )
    }

    func recordShare(postID: String, channel: String) async throws -> ShareResult {
        let response: ShareResponseDTO = try await apiClient.authorizedRequest(
            .recordShare(postID: postID),
            body: ShareRequestDTO(channel: channel)
        )
        guard let url = URL(string: response.shareURL) else {
            throw APIError.invalidURL
        }
        return ShareResult(
            shareCount: Int(response.shareCount),
            shareURL: url,
            newlyRecorded: response.newlyRecorded
        )
    }

    func getShareURL(postID: String) async throws -> URL {
        let response: ShareUrlResponseDTO = try await apiClient.authorizedRequest(.shareURL(postID: postID))
        guard let url = URL(string: response.shareURL) else {
            throw APIError.invalidURL
        }
        return url
    }

    func recordView(postID: String, source: ViewSource, watchTimeMs: Int) async throws -> RecordViewResult {
        let response: RecordViewResponseDTO = try await apiClient.authorizedRequest(
            .recordView(postID: postID),
            body: RecordViewRequestDTO(source: source.rawValue, watchTimeMs: watchTimeMs)
        )
        return RecordViewResult(accepted: response.accepted)
    }
}

final class CommentRepository: CommentRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient
    private let mediaUploadClient: MediaUploadClient

    init(apiClient: APIClient, mediaUploadClient: MediaUploadClient = MediaUploadClient()) {
        self.apiClient = apiClient
        self.mediaUploadClient = mediaUploadClient
    }

    func fetchComments(postID: String, cursor: String?, limit: Int) async throws -> CommentPage {
        let response: CommentsResponseDTO = try await apiClient.authorizedRequest(
            .comments(postID: postID, cursor: cursor, limit: limit)
        )
        return CommentPage(
            comments: response.comments.map { $0.toDomain() },
            nextCursor: response.nextCursor
        )
    }

    func fetchComment(id: String) async throws -> Comment {
        let response: CommentDTO = try await apiClient.authorizedRequest(.comment(id: id))
        return response.toDomain()
    }

    func addComment(
        postID: String,
        content: String,
        showInFeed: Bool,
        parentCommentID: String?,
        stickerID: String?,
        pendingMedia: Bool,
        pendingGif: PendingCommentGif?
    ) async throws -> Comment {
        let response: CommentDTO = try await apiClient.authorizedRequest(
            .addComment(postID: postID),
            body: AddCommentRequestDTO(
                content: content,
                showInFeed: showInFeed,
                parentCommentID: parentCommentID,
                stickerID: stickerID,
                pendingMedia: pendingMedia,
                pendingGif: pendingGif
            )
        )
        return response.toDomain()
    }

    func uploadCommentAttachments(commentID: String, attachments: [PostAttachment]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, attachment) in attachments.enumerated() {
                group.addTask {
                    let uploadInfo: UploadURLResponseDTO = try await self.apiClient.authorizedRequest(
                        .commentUploadURL(commentID: commentID),
                        body: UploadURLRequestDTO(
                            contentType: attachment.contentType,
                            mediaType: "image",
                            index: index
                        )
                    )

                    try await self.mediaUploadClient.upload(
                        data: attachment.data,
                        to: try self.requireUploadURL(uploadInfo.uploadURL),
                        contentType: attachment.contentType
                    )

                    let _: UploadCompleteResponseDTO = try await self.apiClient.authorizedRequest(
                        .commentUploadComplete(commentID: commentID),
                        body: UploadCompleteRequestDTO(
                            objectKey: uploadInfo.objectKey,
                            mediaType: "image"
                        )
                    )
                }
            }

            for try await _ in group {}
        }
    }

    func toggleCommentLike(commentID: String) async throws -> ToggleResult {
        let response: ToggleResponseDTO = try await apiClient.authorizedRequest(.commentLike(id: commentID))
        return ToggleResult(active: response.active, count: Int(response.count))
    }

    func deleteComment(commentID: String) async throws {
        let _: DeleteCommentResponseDTO = try await apiClient.authorizedRequest(.deleteComment(commentID: commentID))
    }

    private func requireUploadURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw) else {
            throw APIError.validation("Invalid upload URL.")
        }
        guard AppEnvironment.current.isAllowedUploadURL(url) else {
            throw APIError.validation("Untrusted upload host.")
        }
        return url
    }
}

final class AnalyticsRepository: AnalyticsRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchPostAnalytics(postID: String, from: String?, to: String?) async throws -> PostAnalytics {
        let response: PostAnalyticsResponseDTO = try await apiClient.authorizedRequest(
            .postAnalytics(postID: postID, from: from, to: to)
        )
        return response.toDomain()
    }

    func fetchCreatorOverview(from: String?, to: String?) async throws -> CreatorOverview {
        let response: CreatorOverviewResponseDTO = try await apiClient.authorizedRequest(
            .creatorOverview(from: from, to: to)
        )
        return response.toDomain()
    }
}

final class PostActivityRepository: PostActivityRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchActivity(postID: String) async throws -> PostActivity {
        let response: PostActivityResponseDTO = try await apiClient.authorizedRequest(.postActivity(postID: postID))
        return response.toDomain()
    }

    func fetchLikers(postID: String, cursor: String?, limit: Int) async throws -> PostLikerPage {
        let response: PostLikersResponseDTO = try await apiClient.authorizedRequest(
            .postLikers(postID: postID, cursor: cursor, limit: limit)
        )
        return PostLikerPage(
            likers: response.likers.map { $0.toDomain() },
            nextCursor: response.nextCursor
        )
    }
}

final class StickerRepository: StickerRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchPacks() async throws -> [StickerPackSummary] {
        let response: StickerPacksResponseDTO = try await apiClient.authorizedRequest(.stickerPacks)
        return response.packs.map { $0.toDomain() }
    }

    func fetchPack(id: String) async throws -> StickerPackDetail {
        let response: StickerPackDetailDTO = try await apiClient.authorizedRequest(.stickerPack(id: id))
        guard let pack = response.toDomain() else {
            throw APIError.validation("Invalid sticker pack.")
        }
        return pack
    }
}
