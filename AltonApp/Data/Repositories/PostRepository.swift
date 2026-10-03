import Foundation

final class PostRepository: PostRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClient
    private let mediaUploadClient: MediaUploadClient

    init(apiClient: APIClient, mediaUploadClient: MediaUploadClient = MediaUploadClient()) {
        self.apiClient = apiClient
        self.mediaUploadClient = mediaUploadClient
    }

    func createTakePost(content: String?) async throws -> Post {
        let response: CreatePostResponseDTO = try await apiClient.authorizedRequest(
            .createPost,
            body: CreatePostRequestDTO(
                postType: "take",
                content: content,
                mediaKey: nil,
                imageKey: nil,
                lat: nil,
                lon: nil,
                geoSource: nil,
                aiGeneratedLabel: nil
            )
        )
        return response.toDomain()
    }

    func createShotPost(
        content: String?,
        lat: Double? = nil,
        lon: Double? = nil,
        geoSource: String? = nil,
        aiGeneratedLabel: Bool? = nil
    ) async throws -> Post {
        let response: CreatePostResponseDTO = try await apiClient.authorizedRequest(
            .createPost,
            body: CreatePostRequestDTO(
                postType: "shot",
                content: content,
                mediaKey: nil,
                imageKey: nil,
                lat: lat,
                lon: lon,
                geoSource: geoSource,
                aiGeneratedLabel: aiGeneratedLabel
            )
        )
        return response.toDomain()
    }

    func fetchPost(id: String) async throws -> Post {
        let dto: PostDTO = try await apiClient.authorizedRequest(.post(id: id))
        return dto.toDomain()
    }

    func publishPost(id: String) async throws {
        PipelineLogger.media.info("publish postId=\(id, privacy: .public)")
        let _: PublishPostResponseDTO = try await apiClient.authorizedRequest(
            .publishPost(id: id)
        )
        PipelineLogger.media.info("publish complete postId=\(id, privacy: .public)")
    }

    func deletePost(id: String) async throws {
        let _: DeletePostResponseDTO = try await apiClient.authorizedRequest(.deletePost(id: id))
    }

    func updatePost(id: String, content: String?, mediaKey: String?) async throws -> Post {
        let dto: PostDTO = try await apiClient.authorizedRequest(
            .updatePost(id: id),
            body: UpdatePostBodyDTO(content: content, mediaKey: mediaKey)
        )
        return dto.toDomain()
    }

    func schedulePost(id: String, publishAt: Date) async throws -> Post {
        let formatter = ISO8601DateFormatter()
        let dto: PostDTO = try await apiClient.authorizedRequest(
            .schedulePost(id: id),
            body: SchedulePostBodyDTO(publishAt: formatter.string(from: publishAt))
        )
        return dto.toDomain()
    }

    func fetchDrafts(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        let response: PostsPageDTO = try await apiClient.authorizedRequest(
            .drafts(cursor: cursor, limit: limit)
        )
        return (response.posts.map { $0.toDomain() }, response.nextCursor)
    }

    func fetchScheduled(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        let response: PostsPageDTO = try await apiClient.authorizedRequest(
            .scheduled(cursor: cursor, limit: limit)
        )
        return (response.posts.map { $0.toDomain() }, response.nextCursor)
    }

    func createPoll(postID: String, question: String, options: [String], expiresAt: Date?) async throws -> Poll {
        let expires = expiresAt.map { ISO8601DateFormatter().string(from: $0) }
        let response: PollResponseDTO = try await apiClient.authorizedRequest(
            .createPoll(postID: postID),
            body: CreatePollBodyDTO(question: question, options: options, expiresAt: expires)
        )
        return response.toDomain()
    }

    func votePoll(pollID: String, optionIndex: Int) async throws -> Poll {
        let response: PollResponseDTO = try await apiClient.authorizedRequest(
            .votePoll(id: pollID),
            body: VotePollBodyDTO(optionIndex: optionIndex)
        )
        return response.toDomain()
    }

    func fetchPoll(postID: String) async throws -> Poll {
        let response: PollResponseDTO = try await apiClient.authorizedRequest(.getPoll(postID: postID))
        return response.toDomain()
    }

    func fetchLinkPreview(url: String) async throws -> LinkPreview? {
        let response: LinkPreviewResponseDTO = try await apiClient.authorizedRequest(
            .linkPreview(url: url)
        )
        return response.toDomain()
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

    func uploadTakeAttachments(postID: String, attachments: [PostAttachment]) async throws -> Post {
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, attachment) in attachments.enumerated() {
                group.addTask {
                    let uploadInfo: UploadURLResponseDTO = try await self.apiClient.authorizedRequest(
                        .uploadURL(postID: postID),
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
                        .uploadComplete(postID: postID),
                        body: UploadCompleteRequestDTO(
                            objectKey: uploadInfo.objectKey,
                            mediaType: "image"
                        )
                    )

                    return (index, uploadInfo.objectKey)
                }
            }

            var keyed: [(Int, String)] = []
            for try await item in group {
                keyed.append(item)
            }
            let mediaKeys = keyed.sorted { $0.0 < $1.0 }.map(\.1)

            return Post(
                id: postID,
                creatorID: "",
                creatorUsername: nil,
                creatorDisplayName: nil,
                creatorAvatarURL: nil,
                postType: .take,
                status: .draft,
                content: nil,
                mediaKey: mediaKeys.joined(separator: ","),
                thumbnailKey: nil,
                playbackURL: nil,
                thumbnailURL: nil,
                imageURLs: [],
                viewCount: 0,
                likeCount: 0,
                commentCount: 0,
                saveCount: 0,
                shareCount: 0,
                repostCount: 0,
                isLiked: false,
                isBookmarked: false,
                isReposted: false,
                createdAt: nil
            )
        }
    }

    func pendingShotPostID(fileURL: URL) -> String? {
        MultipartUploadCheckpointStore.current.pendingPostID(fileURL: fileURL)
    }

    func pendingShotFileURLs() -> [URL] {
        MultipartUploadCheckpointStore.current.pendingFileURLs()
    }

    func shotUploadContext(fileURL: URL) -> ShotUploadContext? {
        MultipartUploadCheckpointStore.current.uploadContext(fileURL: fileURL)
    }

    func rememberShotUploadContext(fileURL: URL, context: ShotUploadContext) {
        MultipartUploadCheckpointStore.current.rememberUploadContext(fileURL: fileURL, context: context)
    }

    func detachPendingShotUpload(fileURL: URL) {
        MultipartUploadCheckpointStore.current.detachFile(fileURL)
    }

    func discardPendingShotUpload(fileURL: URL) {
        MultipartUploadCheckpointStore.current.removeFile(fileURL)
    }

    func shotRequiresExplicitResume(fileURL: URL) -> Bool {
        MultipartUploadCheckpointStore.current.blocksAutomaticResume(fileURL: fileURL)
    }

    func allowAutomaticShotResume(fileURL: URL) {
        MultipartUploadCheckpointStore.current.allowAutomaticResume(fileURL: fileURL)
    }

    func requireExplicitShotResume(fileURL: URL) {
        MultipartUploadCheckpointStore.current.requireExplicitResume(fileURL: fileURL)
    }

    func acceptedShotUploads() -> [AcceptedShotUpload] {
        MultipartUploadCheckpointStore.current.serverAcceptedCompletes()
    }

    func removeShotJournal(postID: String) {
        MultipartUploadCheckpointStore.current.removePost(postID)
    }

    func resendShotUploadComplete(postID: String, objectKey: String) async throws {
        let _: UploadCompleteResponseDTO = try await apiClient.authorizedRequest(
            .uploadComplete(postID: postID),
            body: UploadCompleteRequestDTO(
                objectKey: objectKey,
                mediaType: "video"
            )
        )
    }

    func uploadShot(postID: String, fileURL: URL) async throws -> Post {
        try await uploadShot(postID: postID, fileURL: fileURL, progress: nil)
    }

    func uploadShot(
        postID: String,
        fileURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Post {
        PipelineLogger.media.info(
            "video pipeline start postId=\(postID, privacy: .public) \(PipelineLogger.fileSummary(fileURL), privacy: .public)"
        )
        let uploadInfo: UploadURLResponseDTO = try await apiClient.authorizedRequest(
            .uploadURL(postID: postID),
            body: UploadURLRequestDTO(
                contentType: "video/mp4",
                mediaType: "video",
                index: nil
            )
        )

        let durableURL = try MultipartUploadCheckpointStore.current.bind(
            postID: postID,
            objectKey: uploadInfo.objectKey,
            fileURL: fileURL
        )

        try await mediaUploadClient.upload(
            fileURL: durableURL,
            to: try requireUploadURL(uploadInfo.uploadURL),
            contentType: "video/mp4",
            progress: progress
        )
        try Task.checkCancellation()

        if MultipartUploadCheckpointStore.current.completeMayHaveLanded(objectKey: uploadInfo.objectKey),
           let existing = await postAfterCancelledComplete(postID),
           !ShotUploadCompletionRetry.shouldSendUploadComplete(status: existing.status, mediaKey: existing.mediaKey) {
            MultipartUploadCheckpointStore.current.remove(objectKey: uploadInfo.objectKey)
            return existing
        }

        do {
            let _: UploadCompleteResponseDTO = try await apiClient.authorizedRequest(
                .uploadComplete(postID: postID),
                body: UploadCompleteRequestDTO(
                    objectKey: uploadInfo.objectKey,
                    mediaType: "video"
                )
            )
        } catch {
            if NetworkErrorClassifier.isCancellation(error) {
                switch await cancelledUploadCompleteResolution(postID: postID) {
                case .accepted(let post):
                    MultipartUploadCheckpointStore.current.remove(objectKey: uploadInfo.objectKey)
                    return post
                case .discard:
                    throw error
                case .keep:
                    PipelineLogger.media.info(
                        "video upload-complete unconfirmed postId=\(postID, privacy: .public)"
                    )
                    MultipartUploadCheckpointStore.current.markCompleteUnconfirmed(objectKey: uploadInfo.objectKey)
                    throw ShotUploadCompletionUnconfirmed()
                }
            }
            throw error
        }
        MultipartUploadCheckpointStore.current.markServerAcceptedComplete(objectKey: uploadInfo.objectKey)

        PipelineLogger.media.info(
            "video upload-complete postId=\(postID, privacy: .public) objectKey=\(uploadInfo.objectKey, privacy: .public)"
        )

        // Prefer live post state over a synthetic stub (media still processing).
        if let fresh = try? await fetchPost(id: postID) {
            if !ShotUploadCompletionRetry.shouldSendUploadComplete(status: fresh.status, mediaKey: fresh.mediaKey) {
                MultipartUploadCheckpointStore.current.remove(objectKey: uploadInfo.objectKey)
            }
            return fresh
        }

        return Post(
            id: postID,
            creatorID: "",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .shot,
            status: .processing,
            content: nil,
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: nil,
            imageURLs: [],
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: nil
        )
    }

    private enum CancelledCompleteResolution {
        case accepted(Post)
        case discard
        case keep
    }

    /// Status is read from a fresh task so the cancelled upload does not abort the check.
    private func postAfterCancelledComplete(_ postID: String) async -> Post? {
        await Task { () -> Post? in
            try? await self.fetchPost(id: postID)
        }.value
    }

    private func cancelledUploadCompleteResolution(postID: String) async -> CancelledCompleteResolution {
        let post = await postAfterCancelledComplete(postID)
        guard let post else { return .keep }
        switch ShotUploadCancellationPolicy.outcome(for: post.status) {
        case .accepted:
            return .accepted(post)
        case .discardLocalCopy:
            return .discard
        case .keepForResume:
            return .keep
        }
    }
}
