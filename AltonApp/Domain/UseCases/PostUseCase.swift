import Foundation

enum ShotPublishProgress: Equatable, Sendable {
    case preparing
    case uploading(Double)
    case processing
    case finished
}

enum ShotPublishOutcome: Equatable, Sendable {
    /// Fully live in feed.
    case published(Post)
    /// Bytes are on the server; transcode/moderation still running.
    case acceptedPending(Post)
}

/// `upload-complete` was cancelled after the bytes were sent, and a follow-up
/// status check could not tell whether the server accepted the shot.
struct ShotUploadCompletionUnconfirmed: Error, Equatable {}

enum ShotUploadCancelOutcome: Equatable {
    case accepted
    case discardLocalCopy
    case keepForResume
}

enum ShotUploadCancellationPolicy {
    /// Shots are created as `processing`, so that status does not prove `upload-complete` landed.
    /// Acceptance is a later state. A draft means Cancel won. A missing status stays resumable.
    static func outcome(for status: PostStatus?) -> ShotUploadCancelOutcome {
        switch status {
        case .none, .processing:
            return .keepForResume
        case .draft:
            return .discardLocalCopy
        case .moderation, .published, .rejected:
            return .accepted
        }
    }
}

enum ShotUploadCompletionRetry {
    /// A processed media key or a post that already left `processing` means the complete request landed.
    static func shouldSendUploadComplete(status: PostStatus?, mediaKey: String?) -> Bool {
        if mediaIsAttached(mediaKey) { return false }
        return ShotUploadCancellationPolicy.outcome(for: status) != .accepted
    }

    static func mediaIsAttached(_ mediaKey: String?) -> Bool {
        guard let mediaKey, !mediaKey.isEmpty else { return false }
        return !mediaKey.hasPrefix("raw-uploads/")
    }
}

enum AcceptedShotJournal {
    enum Fetch {
        case missing
        case unavailable
        case loaded(status: PostStatus?, mediaKey: String?)
    }

    enum Action: Equatable {
        case drop
        case resend
        case keep
    }

    /// A deleted post drops the local copy. A failed fetch keeps it.
    /// While the app stays open, later checks only drop a settled post.
    static func action(for fetch: Fetch, resendIncomplete: Bool) -> Action {
        switch fetch {
        case .missing:
            return .drop
        case .unavailable:
            return .keep
        case .loaded(let status, let mediaKey):
            if !ShotUploadCompletionRetry.shouldSendUploadComplete(status: status, mediaKey: mediaKey) {
                return .drop
            }
            return resendIncomplete ? .resend : .keep
        }
    }
}

enum AcceptedShotResend {
    /// A shot that already got a successful resend is not sent again on the next poll.
    /// A failed resend stays eligible while the app remains open.
    static func allows(passRequestsResend: Bool, alreadySucceeded: Bool) -> Bool {
        passRequestsResend && !alreadySucceeded
    }
}

enum AcceptedShotWatch {
    /// A new shot must not cancel a recovery pass that still has to resend older uploads.
    static func shouldStart(resendIncomplete: Bool, watchRunning: Bool) -> Bool {
        !watchRunning || resendIncomplete
    }

    /// A cancelled watch must finish before the success set is cleared, otherwise it can
    /// re-insert a post id and the next pass will skip a needed upload-complete.
    static func clearsResentAfterPreviousFinishes(resendIncomplete: Bool) -> Bool {
        resendIncomplete
    }

    /// Stale watches must not touch the success set or drop the journal.
    static func mayMutateAcceptedState(watchGeneration: Int, activeGeneration: Int) -> Bool {
        watchGeneration == activeGeneration
    }

    /// After `stop`, the cancelled task is kept so the next watch can await it.
    static func previousTaskToAwait<T>(current: T?, ending: T?) -> T? {
        current ?? ending
    }
}

enum ShotResumeBatch {
    /// Cancel deletes the file whose upload already started. Later files in the batch stay on disk.
    static func shouldDelete(uploadStarted: Bool) -> Bool {
        uploadStarted
    }

    /// The shared resume task was cancelled before this file's upload began.
    @MainActor
    static func keepUnstartedFile(url: URL, postUseCase: PostUseCase, appState: AppState) {
        if shouldDelete(uploadStarted: false) {
            postUseCase.discardPendingShotUpload(fileURL: url)
        } else {
            postUseCase.requireExplicitShotResume(fileURL: url)
        }
        appState.endShotUpload(url)
        appState.suppressAutomaticResume(url)
    }
}

enum ShotUploadResumePolicy {
    /// A shot stays `processing` from creation until transcode finishes, so a paused upload must keep that post.
    static func reusesExistingShot(_ status: PostStatus) -> Bool {
        status == .draft || status == .processing
    }
}

@MainActor
final class PostUseCase {
    static let characterLimit = 4000

    private let repository: PostRepositoryProtocol
    private var acceptedShotWatch: Task<Void, Never>?
    /// Cancelled by `stop` / replaced watch; kept until the next watch awaits it.
    private var acceptedShotWatchEnding: Task<Void, Never>?
    private var uploadCompleteResent: Set<String> = []
    private var acceptedShotWatchGeneration = 0

    init(repository: PostRepositoryProtocol) {
        self.repository = repository
    }

    func fetchPost(id: String) async throws -> Post {
        try await repository.fetchPost(id: id)
    }

    func createAndPublishTake(content: String, attachments: [PostAttachment] = []) async throws -> Post {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let plainEmpty = PostContentMetrics.isPlainTextEmpty(content)
        guard !plainEmpty || !attachments.isEmpty else {
            throw APIError.validation("Post content cannot be empty.")
        }
        guard PostContentMetrics.plainTextLength(of: content) <= Self.characterLimit else {
            throw APIError.validation("Post content must be \(Self.characterLimit) characters or fewer.")
        }

        let draft = try await repository.createTakePost(content: (plainEmpty || trimmed.isEmpty) ? nil : trimmed)

        var enriched = draft
        if !attachments.isEmpty {
            enriched = try await repository.uploadTakeAttachments(postID: draft.id, attachments: attachments)
            // Do not publish until media-service has processed every image — keeps the post
            // out of feed/profile (only `published` is listed).
            enriched = try await waitForProcessedTakeImages(
                postID: draft.id,
                expectedCount: attachments.count
            )
        }

        try await repository.publishPost(id: draft.id)
        let fallback = Post(
            id: draft.id,
            creatorID: draft.creatorID,
            creatorUsername: draft.creatorUsername,
            creatorDisplayName: draft.creatorDisplayName,
            creatorAvatarURL: draft.creatorAvatarURL,
            postType: draft.postType,
            status: .published,
            content: draft.content ?? ((plainEmpty || trimmed.isEmpty) ? nil : trimmed),
            mediaKey: enriched.mediaKey,
            thumbnailKey: enriched.thumbnailKey,
            playbackURL: enriched.playbackURL,
            thumbnailURL: enriched.thumbnailURL,
            imageURLs: enriched.imageURLs,
            viewCount: draft.viewCount,
            likeCount: draft.likeCount,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: draft.createdAt,
            sensitiveBlur: enriched.sensitiveBlur,
            moderationAction: enriched.moderationAction,
            moderationReason: enriched.moderationReason,
            canReport: enriched.canReport,
            feedEligible: enriched.feedEligible,
            ageGated: enriched.ageGated,
            mediaBlurFlags: enriched.mediaBlurFlags,
            mediaUnknownFlags: enriched.mediaUnknownFlags,
            subtitlesURL: enriched.subtitlesURL,
            subtitlesLanguage: enriched.subtitlesLanguage
        )
        // Publish-first: status is already published — do not block on moderation settle.
        if let fresh = try? await repository.fetchPost(id: draft.id) {
            return fresh
        }
        return fallback
    }

    /// Optionally polls until v2 wrote an action (or reject) and per-image flags for image takes.
    /// Prefer not blocking publish success on this — publish-first returns as soon as status is published.
    func waitForTakeModeration(
        postID: String,
        fallback: Post,
        timeout: TimeInterval? = nil,
        pollInterval: Duration = .milliseconds(400)
    ) async -> Post {
        if fallback.status == .published || fallback.status == .rejected {
            return fallback
        }
        let resolvedTimeout = timeout ?? Self.takeModerationTimeout(imageCount: fallback.imageURLs.count)
        let deadline = Date().addingTimeInterval(resolvedTimeout)
        var last = fallback
        while Date() < deadline {
            if let fresh = try? await repository.fetchPost(id: postID) {
                last = fresh
                if Self.takeModerationSettled(fresh) {
                    return fresh
                }
            }
            if Date() >= deadline {
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        return last
    }

    /// Vision remode on a 10-image album can exceed a flat minute.
    static func takeModerationTimeout(imageCount: Int) -> TimeInterval {
        min(300, 90 + Double(max(imageCount, 0)) * 18)
    }

    static func takeModerationSettled(_ post: Post) -> Bool {
        // Publish-first: published (or rejected) is already a success terminal for the client.
        if post.status == .published || post.status == .rejected {
            return true
        }
        guard let action = post.moderationAction, Self.isTerminalTakeAction(action) else {
            return false
        }
        let imageCount = post.imageURLs.count
        if imageCount > 0 {
            return post.mediaBlurFlags.count >= imageCount
        }
        return true
    }

    static func isTerminalTakeAction(_ action: String) -> Bool {
        switch action {
        case "publish", "publish_blurred", "publish_age_gated", "reject", "reject_and_escalate":
            return true
        default:
            return false
        }
    }

    /// Polls until processed image keys (not raw-uploads) are attached, or times out.
    private func waitForProcessedTakeImages(postID: String, expectedCount: Int) async throws -> Post {
        let timeout = Date().addingTimeInterval(90)
        var last = try await repository.fetchPost(id: postID)

        while Date() < timeout {
            let processed = Self.processedTakeImageCount(in: last)
            if processed >= expectedCount {
                return last
            }
            try await Task.sleep(for: .milliseconds(600))
            last = try await repository.fetchPost(id: postID)
        }

        let processed = Self.processedTakeImageCount(in: last)
        if processed >= expectedCount {
            return last
        }
        throw APIError.validation("Image processing timed out. Your draft was saved — try again later.")
    }

    /// Counts media keys that look processed (under `media/`), falling back to image URL count.
    static func processedTakeImageCount(in post: Post) -> Int {
        if let mediaKey = post.mediaKey, !mediaKey.isEmpty {
            let keys = mediaKey
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let processed = keys.filter { key in
                key.hasPrefix("media/") || key.hasPrefix("http")
            }
            if !processed.isEmpty {
                return processed.count
            }
            // Some environments attach final keys without the media/ prefix once ready.
            let raw = keys.filter { $0.hasPrefix("raw-uploads/") }
            if raw.count < keys.count {
                return keys.count - raw.count
            }
        }
        return post.imageURLs.count
    }

    func pendingShotFileURLs() -> [URL] {
        repository.pendingShotFileURLs()
    }

    func discardPendingShotUpload(fileURL: URL) {
        repository.discardPendingShotUpload(fileURL: fileURL)
    }

    func shotRequiresExplicitResume(fileURL: URL) -> Bool {
        repository.shotRequiresExplicitResume(fileURL: fileURL)
    }

    func allowAutomaticShotResume(fileURL: URL) {
        repository.allowAutomaticShotResume(fileURL: fileURL)
    }

    func requireExplicitShotResume(fileURL: URL) {
        repository.requireExplicitShotResume(fileURL: fileURL)
    }

    /// Sends `upload-complete` again when asked and the processed video is still missing.
    /// Returns whether a resend failed and should be tried on the next poll.
    /// Drops the journal once the post is settled or gone. A failed fetch keeps the copy.
    @discardableResult
    func reconcileAcceptedShotUploads(
        resendIncomplete: Bool = true,
        watchGeneration: Int? = nil
    ) async -> Bool {
        var resendFailed = false
        for upload in repository.acceptedShotUploads() {
            let fetch: AcceptedShotJournal.Fetch
            do {
                let post = try await repository.fetchPost(id: upload.postID)
                fetch = .loaded(status: post.status, mediaKey: post.mediaKey)
            } catch let error as APIError {
                if case .notFound = error {
                    fetch = .missing
                } else {
                    fetch = .unavailable
                }
            } catch {
                fetch = .unavailable
            }
            let allowResend = AcceptedShotResend.allows(
                passRequestsResend: resendIncomplete,
                alreadySucceeded: uploadCompleteResent.contains(upload.postID)
            )
            switch AcceptedShotJournal.action(for: fetch, resendIncomplete: allowResend) {
            case .drop:
                // Live generation: a stopped/replaced watch must not delete the journal.
                let canMutate = AcceptedShotWatch.mayMutateAcceptedState(
                    watchGeneration: watchGeneration ?? acceptedShotWatchGeneration,
                    activeGeneration: acceptedShotWatchGeneration
                )
                guard canMutate else { continue }
                uploadCompleteResent.remove(upload.postID)
                repository.removeShotJournal(postID: upload.postID)
            case .keep:
                break
            case .resend:
                do {
                    try await repository.resendShotUploadComplete(postID: upload.postID, objectKey: upload.objectKey)
                    if AcceptedShotWatch.mayMutateAcceptedState(
                        watchGeneration: watchGeneration ?? acceptedShotWatchGeneration,
                        activeGeneration: acceptedShotWatchGeneration
                    ) {
                        uploadCompleteResent.insert(upload.postID)
                    }
                } catch {
                    resendFailed = true
                    PipelineLogger.logError(
                        PipelineLogger.media,
                        "reconcile upload-complete failed",
                        error: error
                    )
                    continue
                }
                let settled: AcceptedShotJournal.Fetch
                do {
                    let fresh = try await repository.fetchPost(id: upload.postID)
                    settled = .loaded(status: fresh.status, mediaKey: fresh.mediaKey)
                } catch let error as APIError {
                    if case .notFound = error {
                        settled = .missing
                    } else {
                        settled = .unavailable
                    }
                } catch {
                    settled = .unavailable
                }
                if AcceptedShotJournal.action(for: settled, resendIncomplete: false) == .drop {
                    let canMutate = AcceptedShotWatch.mayMutateAcceptedState(
                        watchGeneration: watchGeneration ?? acceptedShotWatchGeneration,
                        activeGeneration: acceptedShotWatchGeneration
                    )
                    guard canMutate else { continue }
                    uploadCompleteResent.remove(upload.postID)
                    repository.removeShotJournal(postID: upload.postID)
                }
            }
        }
        return resendFailed
    }

    func hasAcceptedShotUploads() -> Bool {
        !repository.acceptedShotUploads().isEmpty
    }

    /// Polls while the app is open so a published or deleted shot drops its local copy.
    func watchAcceptedShotUploads(resendIncomplete: Bool) {
        guard AcceptedShotWatch.shouldStart(
            resendIncomplete: resendIncomplete,
            watchRunning: acceptedShotWatch != nil
        ) else {
            return
        }
        let previous = AcceptedShotWatch.previousTaskToAwait(
            current: acceptedShotWatch,
            ending: acceptedShotWatchEnding
        )
        previous?.cancel()
        acceptedShotWatchGeneration += 1
        let generation = acceptedShotWatchGeneration
        acceptedShotWatchEnding = nil
        var task: Task<Void, Never>?
        task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else {
                if self.acceptedShotWatch == task {
                    self.acceptedShotWatch = nil
                }
                return
            }
            if AcceptedShotWatch.clearsResentAfterPreviousFinishes(resendIncomplete: resendIncomplete) {
                self.uploadCompleteResent.removeAll()
            }
            var resend = resendIncomplete
            while !Task.isCancelled {
                let resendFailed = await self.reconcileAcceptedShotUploads(
                    resendIncomplete: resend,
                    watchGeneration: generation
                )
                resend = resendFailed
                if !self.hasAcceptedShotUploads() || Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(3))
            }
            if self.acceptedShotWatch == task {
                self.acceptedShotWatch = nil
            }
        }
        acceptedShotWatch = task
    }

    func stopAcceptedShotWatch() {
        guard let running = acceptedShotWatch else { return }
        running.cancel()
        acceptedShotWatchGeneration += 1
        acceptedShotWatch = nil
        acceptedShotWatchEnding = running
    }

    func createAndPublishShot(
        localVideoURL: URL,
        caption: String?,
        lat: Double? = nil,
        lon: Double? = nil,
        geoSource: String? = nil,
        aiGeneratedLabel: Bool? = nil,
        onProgress: (@MainActor (ShotPublishProgress) -> Void)? = nil,
        waitForPublished: Bool = true,
        processingTimeout: TimeInterval = 300,
        pollInterval: Duration = .seconds(1)
    ) async throws -> ShotPublishOutcome {
        let stored = repository.shotUploadContext(fileURL: localVideoURL)
        let resuming = caption == nil && lat == nil && lon == nil && geoSource == nil && aiGeneratedLabel == nil
        let resolvedCaption = resuming ? stored?.caption : caption
        let resolvedLat = resuming ? stored?.lat : lat
        let resolvedLon = resuming ? stored?.lon : lon
        let resolvedGeo = resuming ? stored?.geoSource : geoSource
        let resolvedAI = resuming ? stored?.aiGeneratedLabel : aiGeneratedLabel
        repository.rememberShotUploadContext(
            fileURL: localVideoURL,
            context: ShotUploadContext(
                caption: resolvedCaption,
                lat: resolvedLat,
                lon: resolvedLon,
                geoSource: resolvedGeo,
                aiGeneratedLabel: resolvedAI
            )
        )

        let trimmedCaption = resolvedCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let captionLength = PostContentMetrics.plainTextLength(of: trimmedCaption)
        if captionLength > Self.characterLimit {
            throw APIError.validation("Caption must be \(Self.characterLimit) characters or fewer.")
        }

        PipelineLogger.media.info(
            "createAndPublishShot \(PipelineLogger.fileSummary(localVideoURL), privacy: .public) captionLen=\(captionLength)"
        )

        await MainActor.run { onProgress?(.preparing) }
        try Task.checkCancellation()

        func createDraft() async throws -> Post {
            let created = try await repository.createShotPost(
                content: trimmedCaption.isEmpty ? nil : trimmedCaption,
                lat: resolvedLat,
                lon: resolvedLon,
                geoSource: resolvedGeo,
                aiGeneratedLabel: resolvedAI
            )
            PipelineLogger.media.info(
                "video draft created postId=\(created.id, privacy: .public) status=\(created.status.rawValue, privacy: .public)"
            )
            return created
        }

        let draft: Post
        if let existingID = repository.pendingShotPostID(fileURL: localVideoURL) {
            do {
                let existing = try await repository.fetchPost(id: existingID)
                if ShotUploadResumePolicy.reusesExistingShot(existing.status) {
                    draft = existing
                    PipelineLogger.media.info(
                        "shot upload resumed postId=\(draft.id, privacy: .public) status=\(draft.status.rawValue, privacy: .public)"
                    )
                } else {
                    repository.detachPendingShotUpload(fileURL: localVideoURL)
                    draft = try await createDraft()
                }
            } catch {
                guard let apiError = error as? APIError, case .notFound = apiError else { throw error }
                repository.detachPendingShotUpload(fileURL: localVideoURL)
                draft = try await createDraft()
            }
        } else {
            draft = try await createDraft()
        }

        await MainActor.run { onProgress?(.uploading(0)) }
        try Task.checkCancellation()
        var uploaded = try await repository.uploadShot(postID: draft.id, fileURL: localVideoURL) { fraction in
            Task { @MainActor in
                onProgress?(.uploading(fraction))
            }
        }

        // Prefer enriched post after upload-complete when available.
        if let fresh = try? await repository.fetchPost(id: draft.id) {
            uploaded = fresh
        }
        if !ShotUploadCompletionRetry.shouldSendUploadComplete(status: uploaded.status, mediaKey: uploaded.mediaKey) {
            repository.removeShotJournal(postID: draft.id)
        }

        // Server lifecycle: processing → moderation → (auto) published.
        // When the caller opts out of waiting (e.g. video feed), we return immediately
        // after upload — the server publishes asynchronously and sends a push notification.
        if !waitForPublished {
            watchAcceptedShotUploads(resendIncomplete: false)
            await MainActor.run { onProgress?(.finished) }
            PipelineLogger.media.info(
                "createAndPublishShot uploaded (no-wait) postId=\(draft.id, privacy: .public)"
            )
            return .acceptedPending(uploaded)
        }

        await MainActor.run { onProgress?(.processing) }
        do {
            try Task.checkCancellation()
            let published = try await waitForShotTerminalStatus(
                postID: draft.id,
                timeout: processingTimeout,
                pollInterval: pollInterval
            )
            repository.removeShotJournal(postID: draft.id)
            PipelineLogger.media.info(
                "createAndPublishShot done postId=\(published.id, privacy: .public) status=\(published.status.rawValue, privacy: .public)"
            )
            await MainActor.run { onProgress?(.finished) }
            return .published(published)
        } catch is CancellationError {
            PipelineLogger.media.info("createAndPublishShot cancelled after upload postId=\(draft.id, privacy: .public)")
            return .acceptedPending(uploaded)
        } catch let error as APIError {
            // Upload already succeeded — treat processing timeouts as soft success.
            if case .validation(let message) = error,
               message.contains("timed out") || message.contains("under review") {
                PipelineLogger.media.info(
                    "createAndPublishShot pending postId=\(draft.id, privacy: .public) reason=\(message, privacy: .public)"
                )
                return .acceptedPending(uploaded)
            }
            throw error
        } catch {
            if NetworkErrorClassifier.isCancellation(error) {
                return .acceptedPending(uploaded)
            }
            // Transient polling failures after a successful upload should not force a re-upload.
            if NetworkErrorClassifier.isTransientNetworkFailure(error) {
                PipelineLogger.logError(PipelineLogger.media, "createAndPublishShot poll failed after upload", error: error)
                return .acceptedPending(uploaded)
            }
            throw error
        }
    }

    /// Polls until the video leaves processing (published) or is rejected.
    /// Publish-first: once status is published, return immediately — do not wait on moderation.
    func waitForShotTerminalStatus(
        postID: String,
        timeout: TimeInterval = 300,
        pollInterval: Duration = .seconds(1)
    ) async throws -> Post {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try await repository.fetchPost(id: postID)

        while Date() < deadline {
            try Task.checkCancellation()
            switch last.status {
            case .published:
                return last
            case .rejected:
                repository.removeShotJournal(postID: postID)
                throw Self.shotRejectedError(for: last)
            case .moderation, .processing, .draft:
                break
            }

            try await Task.sleep(for: pollInterval)
            try Task.checkCancellation()
            last = try await repository.fetchPost(id: postID)
        }

        switch last.status {
        case .published:
            return last
        case .rejected:
            repository.removeShotJournal(postID: postID)
            throw Self.shotRejectedError(for: last)
        case .moderation:
            repository.removeShotJournal(postID: postID)
            throw APIError.validation("Video is still under review. It will appear when approved.")
        default:
            throw APIError.validation("Video processing timed out. Your draft was saved — try again later.")
        }
    }

    private static func shotRejectedError(for post: Post) -> APIError {
        if let reason = post.moderationReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            let label = ReportReason.displayTitle(for: reason) ?? reason
            return .validation(label)
        }
        return .validation("This shot was rejected by moderation.")
    }

    func updateTake(postID: String, content: String) async throws -> Post {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !PostContentMetrics.isPlainTextEmpty(content), !trimmed.isEmpty else {
            throw APIError.validation("Post content cannot be empty.")
        }
        guard PostContentMetrics.plainTextLength(of: content) <= Self.characterLimit else {
            throw APIError.validation("Post content must be \(Self.characterLimit) characters or fewer.")
        }
        return try await repository.updatePost(id: postID, content: trimmed, mediaKey: nil)
    }

    func fetchDrafts(cursor: String? = nil, limit: Int = 20) async throws -> (posts: [Post], nextCursor: String?) {
        try await repository.fetchDrafts(cursor: cursor, limit: limit)
    }

    func fetchScheduled(cursor: String? = nil, limit: Int = 20) async throws -> (posts: [Post], nextCursor: String?) {
        try await repository.fetchScheduled(cursor: cursor, limit: limit)
    }

    func deletePost(id: String) async throws {
        try await repository.deletePost(id: id)
    }
}

struct PostAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let data: Data
    let contentType: String
    let filename: String
    /// PhotosPicker item identifier used for merge dedup; nil for non-picker sources.
    let pickerItemID: String?

    init(
        id: UUID = UUID(),
        data: Data,
        contentType: String,
        filename: String,
        pickerItemID: String? = nil
    ) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.filename = filename
        self.pickerItemID = pickerItemID
    }

    var isGIF: Bool {
        contentType == "image/gif" || filename.lowercased().hasSuffix(".gif")
    }

    /// GIF or Klipy animated WebP — preview as animation, don't open the still-image editor.
    var playsAsAnimation: Bool {
        isGIF
            || contentType == "image/webp" && filename.lowercased().hasPrefix("klipy-")
    }
}
