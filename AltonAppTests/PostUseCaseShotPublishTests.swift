import Foundation
import XCTest
@testable import AltonApp

@MainActor
final class PostUseCaseShotPublishTests: XCTestCase {
    func testCreateAndPublishVideoWaitsForPublishedWithoutImmediatePublish() async throws {
        let repo = MockShotPostRepository(
            statusSequence: [.processing, .processing, .moderation, .published]
        )
        let useCase = PostUseCase(repository: repo)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = try await useCase.createAndPublishShot(
            localVideoURL: fileURL,
            caption: "hello",
            onProgress: nil,
            processingTimeout: 5,
            pollInterval: .milliseconds(10)
        )

        guard case .published(let post) = outcome else {
            return XCTFail("Expected published outcome")
        }
        XCTAssertEqual(post.status, .published)
        XCTAssertEqual(repo.createShotCallCount, 1)
        XCTAssertEqual(repo.uploadShotCallCount, 1)
        XCTAssertGreaterThanOrEqual(repo.fetchPostCallCount, 4)
        XCTAssertEqual(repo.publishPostCallCount, 0)
    }

    func testCreateAndPublishVideoReturnsPendingOnProcessingTimeout() async throws {
        let repo = MockShotPostRepository(
            statusSequence: Array(repeating: .processing, count: 40)
        )
        let useCase = PostUseCase(repository: repo)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("clip-timeout.mp4")
        try Data([0x00, 0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = try await useCase.createAndPublishShot(
            localVideoURL: fileURL,
            caption: nil,
            processingTimeout: 0.05,
            pollInterval: .milliseconds(10)
        )

        guard case .acceptedPending = outcome else {
            return XCTFail("Expected acceptedPending after timeout")
        }
        XCTAssertEqual(repo.uploadShotCallCount, 1)
        XCTAssertEqual(repo.publishPostCallCount, 0)
    }

    func testWaitForVideoThrowsOnRejected() async {
        let repo = MockShotPostRepository(statusSequence: [.rejected], rejectedReason: "S1")
        let useCase = PostUseCase(repository: repo)

        do {
            _ = try await useCase.waitForShotTerminalStatus(
                postID: "post-1",
                timeout: 1,
                pollInterval: .milliseconds(10)
            )
            XCTFail("Expected rejection error")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertEqual(message, "Violent Crimes")
        }
    }

    func testCaptionUsesPlainTextLength() async {
        let repo = MockShotPostRepository(statusSequence: [.published])
        let useCase = PostUseCase(repository: repo)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("clip2.mp4")
        try? Data([0x00]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let oversized = String(repeating: "a", count: PostUseCase.characterLimit + 1)
        do {
            _ = try await useCase.createAndPublishShot(localVideoURL: fileURL, caption: oversized)
            XCTFail("Expected validation error")
        } catch {
            XCTAssertTrue(error is APIError)
        }
        XCTAssertEqual(repo.createShotCallCount, 0)
    }

    func testCancelledPublishDoesNotStartANewUpload() async {
        let repo = MockShotPostRepository(statusSequence: [.published])
        let useCase = PostUseCase(repository: repo)
        let state = AppState()
        let url = URL(fileURLWithPath: "/tmp/cancel-\(UUID().uuidString).mp4")
        state.beginShotUpload(url)
        state.showUploadBanner("Uploading shot…", progress: 0)
        let task = Task { @MainActor in
            await CameraViewModel.performBackgroundPublish(
                url: url,
                caption: "sunset",
                lat: nil,
                lon: nil,
                geoSource: nil,
                aiGeneratedLabel: nil,
                postUseCase: useCase,
                appState: state
            )
        }
        task.cancel()
        await task.value

        XCTAssertFalse(state.hasActiveShotUpload)
        XCTAssertEqual(repo.createShotCallCount, 0)
        XCTAssertEqual(repo.uploadShotCallCount, 0)
        XCTAssertEqual(repo.discardCount, 0)
        XCTAssertEqual(repo.explicitResumeURLs, [url])
        XCTAssertEqual(state.uploadBanner?.message, "Upload paused.")
        XCTAssertEqual(state.uploadBanner?.canResume, true)
        XCTAssertFalse(state.allowsAutomaticResume(url))
    }

    func testCancelledResumeBatchKeepsFilesThatHaveNotStarted() async {
        let repo = MockShotPostRepository(statusSequence: [.processing])
        let useCase = PostUseCase(repository: repo)
        let state = AppState()
        let first = URL(fileURLWithPath: "/tmp/batch-a-\(UUID().uuidString).mp4")
        let second = URL(fileURLWithPath: "/tmp/batch-b-\(UUID().uuidString).mp4")
        state.beginShotUpload(first)
        state.beginShotUpload(second)
        let pending = [first, second]
        let task = Task { @MainActor in
            for url in pending {
                if Task.isCancelled {
                    ShotResumeBatch.keepUnstartedFile(url: url, postUseCase: useCase, appState: state)
                    continue
                }
                await CameraViewModel.performBackgroundPublish(
                    url: url,
                    caption: nil,
                    lat: nil,
                    lon: nil,
                    geoSource: nil,
                    aiGeneratedLabel: nil,
                    postUseCase: useCase,
                    appState: state
                )
            }
        }
        task.cancel()
        await task.value

        XCTAssertEqual(repo.discardCount, 0)
        XCTAssertEqual(repo.uploadShotCallCount, 0)
        XCTAssertEqual(Set(repo.explicitResumeURLs.map(\.path)), Set(pending.map(\.path)))
        XCTAssertFalse(state.allowsAutomaticResume(first))
        XCTAssertFalse(state.allowsAutomaticResume(second))
        XCTAssertFalse(state.hasActiveShotUpload)
    }

    func testProcessingShotResumesTheSamePost() async throws {
        let repo = MockShotPostRepository(statusSequence: [.processing, .processing])
        repo.pendingPostID = "post-existing"
        let useCase = PostUseCase(repository: repo)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-\(UUID().uuidString).mp4")

        _ = try await useCase.createAndPublishShot(
            localVideoURL: url,
            caption: nil,
            waitForPublished: false
        )

        XCTAssertEqual(repo.createShotCallCount, 0)
        XCTAssertEqual(repo.detachCount, 0)
        XCTAssertEqual(repo.lastUploadedPostID, "post-existing")
    }

    func testPublishedShotStartsANewPost() async throws {
        let repo = MockShotPostRepository(statusSequence: [.published, .processing])
        repo.pendingPostID = "post-existing"
        let useCase = PostUseCase(repository: repo)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finished-\(UUID().uuidString).mp4")

        _ = try await useCase.createAndPublishShot(
            localVideoURL: url,
            caption: "again",
            waitForPublished: false
        )

        XCTAssertEqual(repo.createShotCallCount, 1)
        XCTAssertEqual(repo.detachCount, 1)
        XCTAssertEqual(repo.lastUploadedPostID, "post-1")
    }

    func testStaleWatchGenerationDoesNotDropAcceptedJournal() async {
        let repo = MockShotPostRepository(statusSequence: [.published])
        repo.acceptedUploads = [
            AcceptedShotUpload(postID: "post-1", objectKey: "raw-uploads/post-1/original")
        ]
        let useCase = PostUseCase(repository: repo)

        // Active generation is 0; a cancelled watch still holding generation 1 must not drop.
        await useCase.reconcileAcceptedShotUploads(resendIncomplete: false, watchGeneration: 1)
        XCTAssertEqual(repo.removeJournalCount, 0)
        XCTAssertEqual(repo.acceptedUploads.count, 1)

        await useCase.reconcileAcceptedShotUploads(resendIncomplete: false, watchGeneration: 0)
        XCTAssertEqual(repo.removeJournalCount, 1)
        XCTAssertTrue(repo.acceptedUploads.isEmpty)
    }

    func testSecondPostTapDoesNotStartAnotherUpload() {
        let repo = MockShotPostRepository(statusSequence: [.processing])
        let useCase = PostUseCase(repository: repo)
        let state = AppState()
        let viewModel = CameraViewModel(postUseCase: useCase, appState: state)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("double-\(UUID().uuidString).mp4")
        viewModel.phase = .publication(videoURL: url)
        viewModel.publishVideo {}
        viewModel.publishVideo {}
        XCTAssertTrue(viewModel.isUploading)
        XCTAssertEqual(state.trackedShotUploadCount, 1)
        state.cancelTrackedShotUpload()
    }
}

@MainActor
private final class MockShotPostRepository: PostRepositoryProtocol {
    private var statuses: [PostStatus]
    private let rejectedReason: String?
    var pendingPostID: String?
    private(set) var createShotCallCount = 0
    private(set) var uploadShotCallCount = 0
    private(set) var fetchPostCallCount = 0
    private(set) var publishPostCallCount = 0
    private(set) var detachCount = 0
    private(set) var discardCount = 0
    private(set) var explicitResumeURLs: [URL] = []
    private(set) var lastUploadedPostID: String?
    var acceptedUploads: [AcceptedShotUpload] = []
    private(set) var removeJournalCount = 0

    init(statusSequence: [PostStatus], rejectedReason: String? = nil) {
        self.statuses = statusSequence
        self.rejectedReason = rejectedReason
    }

    func acceptedShotUploads() -> [AcceptedShotUpload] {
        acceptedUploads
    }

    func removeShotJournal(postID: String) {
        removeJournalCount += 1
        acceptedUploads.removeAll { $0.postID == postID }
    }

    func resendShotUploadComplete(postID: String, objectKey: String) async throws {}

    func createTakePost(content: String?) async throws -> Post {
        fatalError("unused")
    }

    func createShotPost(
        content: String?,
        lat: Double?,
        lon: Double?,
        geoSource: String?,
        aiGeneratedLabel: Bool?
    ) async throws -> Post {
        createShotCallCount += 1
        return makePost(status: .processing, content: content)
    }

    func pendingShotPostID(fileURL: URL) -> String? { pendingPostID }

    func pendingShotFileURLs() -> [URL] { [] }

    func shotUploadContext(fileURL: URL) -> ShotUploadContext? { nil }

    func rememberShotUploadContext(fileURL: URL, context: ShotUploadContext) {}

    func detachPendingShotUpload(fileURL: URL) {
        detachCount += 1
    }

    func discardPendingShotUpload(fileURL: URL) {
        discardCount += 1
    }

    func requireExplicitShotResume(fileURL: URL) {
        explicitResumeURLs.append(fileURL)
    }

    func shotRequiresExplicitResume(fileURL: URL) -> Bool {
        explicitResumeURLs.contains(fileURL)
    }

    func fetchPost(id: String) async throws -> Post {
        fetchPostCallCount += 1
        let status = statuses.isEmpty ? .processing : statuses.removeFirst()
        if statuses.isEmpty {
            // Keep returning the last status for timeout loops.
            statuses = [status]
        }
        return makePost(id: id, status: status, content: nil)
    }

    func updatePost(id: String, content: String?, mediaKey: String?) async throws -> Post {
        fatalError("unused")
    }

    func schedulePost(id: String, publishAt: Date) async throws -> Post {
        fatalError("unused")
    }

    func fetchDrafts(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        fatalError("unused")
    }

    func fetchScheduled(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        fatalError("unused")
    }

    func publishPost(id: String) async throws {
        publishPostCallCount += 1
    }

    func deletePost(id: String) async throws {}

    func uploadTakeAttachments(postID: String, attachments: [PostAttachment]) async throws -> Post {
        fatalError("unused")
    }

    func uploadShot(
        postID: String,
        fileURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Post {
        uploadShotCallCount += 1
        lastUploadedPostID = postID
        progress?(1)
        return makePost(id: postID, status: .processing, content: nil)
    }

    func createPoll(postID: String, question: String, options: [String], expiresAt: Date?) async throws -> Poll {
        fatalError("unused")
    }

    func votePoll(pollID: String, optionIndex: Int) async throws -> Poll {
        fatalError("unused")
    }

    func fetchPoll(postID: String) async throws -> Poll {
        fatalError("unused")
    }

    func fetchLinkPreview(url: String) async throws -> LinkPreview? {
        fatalError("unused")
    }

    private func makePost(id: String = "post-1", status: PostStatus, content: String?) -> Post {
        Post(
            id: id,
            creatorID: "user-1",
            creatorUsername: "user",
            creatorDisplayName: "User",
            creatorAvatarURL: nil,
            postType: .shot,
            status: status,
            content: content,
            mediaKey: status == .published ? "media/post-1/video.mp4" : nil,
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
            createdAt: nil,
            moderationReason: status == .rejected ? rejectedReason : nil
        )
    }
}

final class PostDTOModerationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AgeGateConfirmationStore.shared.reset()
    }

    func testMissingPerImageSlotBlursInsteadOfClean() throws {
        let json = """
        {
          "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
          "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ1",
          "post_type": "take",
          "status": "published",
          "playback_url": "https://cdn.example/0.webp,https://cdn.example/1.webp",
          "moderation": {
            "action": "publish_age_gated",
            "blur": true,
            "age_gate": true,
            "media": [
              { "index": 0, "blur": false }
            ]
          }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(PostDTO.self, from: json)
        let post = dto.toDomain()
        XCTAssertEqual(post.imageURLs.count, 2)
        XCTAssertEqual(post.mediaBlurFlags, [false, true])
        XCTAssertEqual(post.mediaUnknownFlags, [false, true])
        XCTAssertTrue(post.blursImage(at: 1))
        XCTAssertTrue(post.isUnknownImage(at: 1))
        XCTAssertFalse(post.allowsRevealImage(at: 1))
        XCTAssertFalse(post.isUnknownImage(at: 0))
        XCTAssertTrue(post.allowsRevealImage(at: 0))
    }

    func testAgeGateDoesNotBlurCleanTiles() throws {
        let json = """
        {
          "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
          "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ1",
          "post_type": "take",
          "status": "published",
          "playback_url": "https://cdn.example/0.webp,https://cdn.example/1.webp",
          "moderation": {
            "action": "publish_age_gated",
            "blur": false,
            "age_gate": true,
            "media": [
              { "index": 0, "blur": false, "unknown": false },
              { "index": 1, "blur": false, "unknown": false }
            ]
          }
        }
        """.data(using: .utf8)!

        let post = try JSONDecoder().decode(PostDTO.self, from: json).toDomain()
        XCTAssertTrue(post.ageGated)
        XCTAssertEqual(post.mediaBlurFlags, [false, false])
        XCTAssertFalse(post.blursImage(at: 0))
        XCTAssertFalse(post.blursImage(at: 1))
        XCTAssertFalse(post.isUnknownImage(at: 0))
        XCTAssertTrue(post.requiresAgeGate)
        XCTAssertFalse(post.isSensitiveImage(at: 0))
        XCTAssertTrue(post.allowsRevealImage(at: 0))
    }

    func testAgeGateFallsBackFromActionWhenFlagMissing() throws {
        let json = """
        {
          "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
          "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ1",
          "post_type": "take",
          "status": "published",
          "moderation": {
            "action": "publish_age_gated",
            "blur": true
          }
        }
        """.data(using: .utf8)!

        let post = try JSONDecoder().decode(PostDTO.self, from: json).toDomain()
        XCTAssertTrue(post.ageGated)
        XCTAssertEqual(post.moderationAction, "publish_age_gated")
    }

    func testTextOnlyAgeGateDoesNotDependOnMediaFlags() throws {
        let json = """
        {
          "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
          "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ1",
          "post_type": "take",
          "status": "published",
          "content": "hate caption",
          "moderation": {
            "action": "publish_age_gated",
            "blur": true,
            "age_gate": true
          }
        }
        """.data(using: .utf8)!

        AgeGateConfirmationStore.shared.reset()
        defer { AgeGateConfirmationStore.shared.reset() }

        let post = try JSONDecoder().decode(PostDTO.self, from: json).toDomain()
        XCTAssertTrue(post.requiresAgeGate)
        XCTAssertTrue(
            AgeRestrictedMediaGatePolicy.shouldGate(
                isAgeGated: true,
                confirmed: false,
                contentID: post.id,
                confirmedForID: "",
                viewerIsAdult: false
            )
        )
        // Minors stay gated even after a local confirm flag.
        XCTAssertTrue(
            AgeRestrictedMediaGatePolicy.shouldGate(
                isAgeGated: true,
                confirmed: true,
                contentID: post.id,
                confirmedForID: post.id,
                viewerIsAdult: false
            )
        )
        // Verified adults never see the gate.
        XCTAssertFalse(
            AgeRestrictedMediaGatePolicy.shouldGate(
                isAgeGated: true,
                confirmed: false,
                contentID: post.id,
                confirmedForID: "",
                viewerIsAdult: true
            )
        )
        XCTAssertTrue(AgeRestrictedMediaGatePolicy.shouldReset(confirmedForID: post.id, newID: "other"))
        XCTAssertTrue(post.imageURLs.isEmpty)
        XCTAssertTrue(post.mediaBlurFlags.isEmpty)
        XCTAssertTrue(SensitiveMediaOverlayPolicy.revealsOnTap(isSensitive: true, allowsReveal: true))
        XCTAssertFalse(SensitiveMediaOverlayPolicy.revealsOnTap(isSensitive: true, allowsReveal: false))
        XCTAssertEqual(
            SensitiveMediaOverlayPolicy.title(allowsReveal: false),
            "Content unavailable"
        )
        XCTAssertEqual(
            SensitiveMediaOverlayPolicy.subtitle(allowsReveal: false),
            "This image is still being checked"
        )
    }

    func testUnknownSlotBlurs() throws {
        let json = """
        {
          "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
          "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ1",
          "post_type": "take",
          "status": "published",
          "playback_url": "https://cdn.example/0.webp",
          "moderation": {
            "media": [
              { "index": 0, "blur": false, "unknown": true }
            ]
          }
        }
        """.data(using: .utf8)!

        let post = try JSONDecoder().decode(PostDTO.self, from: json).toDomain()
        XCTAssertEqual(post.mediaBlurFlags, [true])
        XCTAssertEqual(post.mediaUnknownFlags, [true])
        XCTAssertTrue(post.blursImage(at: 0))
        XCTAssertTrue(post.isUnknownImage(at: 0))
        XCTAssertFalse(post.allowsRevealImage(at: 0))
        XCTAssertTrue(post.isSensitiveImage(at: 0))
        XCTAssertFalse(SensitiveMediaOverlayPolicy.revealsOnTap(isSensitive: true, allowsReveal: false))
    }

    func testSensitiveNoticeExplainsBlurAndReleasesPlatform() {
        let sensitive = SensitiveMediaNotice.make(
            ageLocked: false,
            isSensitive: true,
            allowsReveal: true,
            reason: "S1"
        )
        XCTAssertEqual(sensitive.title, "Sensitive content")
        XCTAssertTrue(sensitive.explanation.contains("Violent Crimes"))
        XCTAssertTrue(sensitive.canContinue)
        XCTAssertTrue(SensitiveMediaNotice.responsibility.contains("release Alton from responsibility"))

        let age = SensitiveMediaNotice.make(
            ageLocked: true,
            isSensitive: false,
            allowsReveal: true,
            reason: nil
        )
        XCTAssertEqual(age.title, "18+ content")
        XCTAssertTrue(age.explanation.contains("18+"))
        XCTAssertTrue(age.canContinue)

        let both = SensitiveMediaNotice.make(
            ageLocked: true,
            isSensitive: true,
            allowsReveal: true,
            reason: nil
        )
        XCTAssertEqual(both.title, "Sensitive content")
        XCTAssertTrue(both.explanation.contains("18+"))
        XCTAssertTrue(both.explanation.contains("sensitive material"))

        let unknown = SensitiveMediaNotice.make(
            ageLocked: true,
            isSensitive: true,
            allowsReveal: false,
            reason: nil
        )
        XCTAssertEqual(unknown, .unavailable)
        XCTAssertFalse(unknown.canContinue)
    }

    func testSensitiveRevealSessionSkipsNoticeUntilReset() {
        let store = SensitiveRevealSessionStore.shared
        store.reset()
        defer { store.reset() }

        XCTAssertFalse(store.allowsImmediateReveal)
        XCTAssertFalse(SensitiveMediaOverlayPolicy.skipsNotice(canContinue: true, sessionAllowed: false))
        XCTAssertFalse(SensitiveMediaOverlayPolicy.skipsNotice(canContinue: false, sessionAllowed: true))

        store.allowForSession()
        XCTAssertTrue(store.allowsImmediateReveal)
        XCTAssertTrue(SensitiveMediaOverlayPolicy.skipsNotice(canContinue: true, sessionAllowed: true))

        store.reset()
        XCTAssertFalse(store.allowsImmediateReveal)
        XCTAssertFalse(SensitiveMediaOverlayPolicy.skipsNotice(canContinue: true, sessionAllowed: false))
    }

    func testParentPreviewAgeGateAndSessionConfirm() throws {
        let json = """
        {
          "kind": "post",
          "post": {
            "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
            "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ1",
            "post_type": "take",
            "status": "published",
            "content": "reply"
          },
          "parent_post": {
            "id": "01JABCDEFGHJKMNPQRSTVWXYZ2",
            "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ3",
            "content": "hate caption",
            "age_gate": true
          }
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(FeedTimelineItemDTO.self, from: json).toDomain()
        guard case .post(let feed) = item else {
            return XCTFail("expected post item")
        }
        let parent = try XCTUnwrap(feed.quotedParent)
        XCTAssertTrue(parent.ageGated)
        XCTAssertFalse(parent.sensitiveBlur)
        XCTAssertEqual(parent.content, "hate caption")

        let post = Post(
            id: parent.id,
            creatorID: parent.creatorID,
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .take,
            status: .published,
            content: parent.content,
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
            createdAt: nil,
            ageGated: parent.ageGated
        )
        XCTAssertEqual(post.listSnippet, "18+ content")
        XCTAssertFalse(post.allowsCopyingContent)
        XCTAssertFalse(AgeRestrictedContentPolicy.forwardsContentInteraction(isGated: true))
        XCTAssertTrue(
            AgeRestrictedMediaGatePolicy.shouldGate(
                isAgeGated: true,
                confirmed: false,
                contentID: parent.id,
                confirmedForID: "",
                viewerIsAdult: false
            )
        )

        // Session confirm alone does not unlock for non-adults.
        AgeGateConfirmationStore.shared.confirm(parent.id)
        XCTAssertFalse(AgeGateConfirmationStore.shared.isConfirmed(parent.id))
        XCTAssertEqual(post.listSnippet, "18+ content")

        // Verified adult unlocks age-gated content without a per-post confirm.
        AgeGateConfirmationStore.shared.setViewerIsAdult(true)
        XCTAssertTrue(AgeGateConfirmationStore.shared.isConfirmed(parent.id))
        XCTAssertEqual(post.listSnippet, "hate caption")
        XCTAssertTrue(post.allowsCopyingContent)
        XCTAssertFalse(
            AgeRestrictedMediaGatePolicy.shouldGate(
                isAgeGated: true,
                confirmed: false,
                contentID: parent.id,
                confirmedForID: "",
                viewerIsAdult: true
            )
        )

        AgeGateConfirmationStore.shared.reset()
        XCTAssertFalse(AgeGateConfirmationStore.shared.isConfirmed(parent.id))
        XCTAssertEqual(post.listSnippet, "18+ content")
        XCTAssertTrue(AgeRestrictedContentPolicy.hidesContentFromAccessibility(isGated: true))
        XCTAssertFalse(AgeRestrictedContentPolicy.hidesContentFromAccessibility(isGated: false))
        XCTAssertTrue(SensitiveMediaOverlayPolicy.hidesContentFromAccessibility(isGated: true))
    }

    func testParentPreviewSensitiveBlur() throws {
        let json = """
        {
          "kind": "post",
          "post": {
            "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
            "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ1",
            "post_type": "take",
            "status": "published",
            "content": "reply"
          },
          "parent_post": {
            "id": "01JABCDEFGHJKMNPQRSTVWXYZ2",
            "creator_id": "01JABCDEFGHJKMNPQRSTVWXYZ3",
            "content": "nsfw caption",
            "age_gate": false,
            "moderation": {
              "action": "publish_blurred",
              "blur": true,
              "age_gate": false
            }
          }
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(FeedTimelineItemDTO.self, from: json).toDomain()
        guard case .post(let feed) = item else {
            return XCTFail("expected post item")
        }
        let parent = try XCTUnwrap(feed.quotedParent)
        XCTAssertFalse(parent.ageGated)
        XCTAssertTrue(parent.sensitiveBlur)
        XCTAssertTrue(SensitiveMediaOverlayPolicy.shouldLoadContent(isBlurred: true, loadWhenBlurred: false) == false)
        XCTAssertTrue(SensitiveMediaOverlayPolicy.shouldLoadContent(isBlurred: false, loadWhenBlurred: false))
    }

    func testShotMediaLockSplitsAgeAndSensitive() {
        AgeGateConfirmationStore.shared.reset()
        defer { AgeGateConfirmationStore.shared.reset() }

        // Non-adult: age-gated stays locked.
        XCTAssertTrue(ShotMediaLockPolicy.isAgeLocked(ageGated: true))
        XCTAssertFalse(ShotMediaLockPolicy.isAgeLocked(ageGated: false))

        AgeGateConfirmationStore.shared.setViewerIsAdult(true)
        XCTAssertFalse(ShotMediaLockPolicy.isAgeLocked(ageGated: true))

        XCTAssertTrue(
            ShotMediaLockPolicy.isSensitiveLocked(sensitiveBlur: true, sensitiveRevealed: false)
        )
        XCTAssertFalse(
            ShotMediaLockPolicy.isSensitiveLocked(sensitiveBlur: true, sensitiveRevealed: true)
        )
        XCTAssertTrue(
            ShotMediaLockPolicy.isMediaLocked(ageLocked: false, sensitiveLocked: true)
        )
        XCTAssertFalse(
            ShotMediaLockPolicy.isMediaLocked(
                ageLocked: ShotMediaLockPolicy.isAgeLocked(ageGated: true),
                sensitiveLocked: ShotMediaLockPolicy.isSensitiveLocked(
                    sensitiveBlur: true,
                    sensitiveRevealed: true
                )
            )
        )
        XCTAssertTrue(
            SensitiveMediaOverlayPolicy.shouldBlur(
                isSensitive: true,
                revealed: true,
                managesRevealInternally: false
            )
        )
        XCTAssertFalse(
            SensitiveMediaOverlayPolicy.shouldBlur(
                isSensitive: true,
                revealed: true,
                managesRevealInternally: true
            )
        )
        XCTAssertEqual(
            ShotMediaLockPolicy.nextReveal(
                sensitiveBlur: true,
                sensitiveRevealed: false
            ),
            .revealSensitive
        )
        XCTAssertEqual(
            ShotMediaLockPolicy.nextReveal(
                sensitiveBlur: false,
                sensitiveRevealed: false
            ),
            .none
        )
        XCTAssertFalse(
            ShotMediaLockPolicy.allowsPlayer(isMediaLocked: true, isActive: true, isPreloading: true)
        )
        XCTAssertTrue(
            ShotMediaLockPolicy.allowsPlayer(isMediaLocked: false, isActive: false, isPreloading: true)
        )
        // Sensitive blur loads the player; age lock does not.
        XCTAssertTrue(
            ShotMediaLockPolicy.shouldLoadForBlur(isSensitiveLocked: true, isAgeLocked: false)
        )
        XCTAssertFalse(
            ShotMediaLockPolicy.shouldLoadForBlur(isSensitiveLocked: true, isAgeLocked: true)
        )
        XCTAssertFalse(
            ShotMediaLockPolicy.shouldLoadForBlur(isSensitiveLocked: false, isAgeLocked: false)
        )
        // Profile / feed visibility policy.
        let sensitive = Post(
            id: "s1",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .shot,
            status: .published,
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
            createdAt: nil,
            sensitiveBlur: true
        )
        let ageGated = Post(
            id: "a1",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .shot,
            status: .published,
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
            createdAt: nil,
            ageGated: true
        )
        XCTAssertFalse(
            ViewerContentFilterPolicy.allowsPost(
                sensitive,
                viewerIsAdult: false,
                showSensitiveContent: true
            )
        )
        XCTAssertFalse(
            ViewerContentFilterPolicy.allowsPost(
                ageGated,
                viewerIsAdult: false,
                showSensitiveContent: true
            )
        )
        XCTAssertFalse(
            ViewerContentFilterPolicy.allowsPost(
                sensitive,
                viewerIsAdult: true,
                showSensitiveContent: false
            )
        )
        XCTAssertTrue(
            ViewerContentFilterPolicy.allowsPost(
                sensitive,
                viewerIsAdult: true,
                showSensitiveContent: true
            )
        )
        // Own profile keeps sensitive/age-gated for the owner.
        XCTAssertTrue(
            ViewerContentFilterPolicy.allowsPost(
                sensitive,
                viewerIsAdult: false,
                showSensitiveContent: false,
                isOwnProfile: true
            )
        )
        XCTAssertEqual(
            ViewerContentFilterPolicy.blockedOpenMessage(
                for: sensitive,
                viewerIsAdult: false,
                showSensitiveContent: true
            ),
            "This content isn't available for your account."
        )
        XCTAssertEqual(
            ViewerContentFilterPolicy.blockedOpenMessage(
                for: sensitive,
                viewerIsAdult: true,
                showSensitiveContent: false
            ),
            "Sensitive content is hidden. Turn on Show Sensitive Content in Settings to view it."
        )
        XCTAssertNil(
            ViewerContentFilterPolicy.blockedOpenMessage(
                for: sensitive,
                viewerIsAdult: true,
                showSensitiveContent: true
            )
        )
        XCTAssertTrue(PostMediaLayoutProbe.shouldProbeRemoteSize(isSensitive: true, isUnknown: false))
        XCTAssertFalse(PostMediaLayoutProbe.shouldProbeRemoteSize(isSensitive: false, isUnknown: true))
        XCTAssertTrue(PostMediaLayoutProbe.shouldProbeRemoteSize(isSensitive: false, isUnknown: false))
        XCTAssertTrue(PostMediaLayoutProbe.shouldProbeRemoteSize(
            isSensitive: true,
            isUnknown: false,
            isRevealed: true
        ))
        AgeGateConfirmationStore.shared.setViewerIsAdult(false)
        XCTAssertFalse(ParentPreviewNavigationPolicy.allowsNavigate(ageGated: true, ageConfirmed: false))
        AgeGateConfirmationStore.shared.setViewerIsAdult(true)
        XCTAssertTrue(ParentPreviewNavigationPolicy.allowsNavigate(ageGated: true, ageConfirmed: false))
    }
}

@MainActor
final class PostUseCaseTakePublishTests: XCTestCase {
    func testCreateAndPublishTakeReturnsFetchedPostWithoutBlockingOnModeration() async throws {
        let repo = MockTakePostRepository(moderationReadyAfterFetches: 99)
        let useCase = PostUseCase(repository: repo)

        let post = try await useCase.createAndPublishTake(content: "hello")

        XCTAssertEqual(post.status, .published)
        XCTAssertEqual(repo.publishPostCallCount, 1)
        XCTAssertEqual(repo.fetchPostCallCount, 1)
    }

    func testCreateAndPublishTakeUsesSingleFetchAfterPublish() async throws {
        let repo = MockTakePostRepository(moderationReadyAfterFetches: 1)
        let useCase = PostUseCase(repository: repo)

        let post = try await useCase.createAndPublishTake(content: "hello")

        XCTAssertEqual(post.moderationAction, "publish_age_gated")
        XCTAssertEqual(post.mediaBlurFlags, [true, false])
        XCTAssertEqual(repo.fetchPostCallCount, 1)
    }

    func testTakeModerationSettledForPublishedOrRejected() {
        let pending = Post(
            id: "p",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .take,
            status: .published,
            content: "hi",
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
        let gated = Post(
            id: "p",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .take,
            status: .published,
            content: "hi",
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
            createdAt: nil,
            moderationAction: "publish_age_gated"
        )
        let rejected = Post(
            id: "p",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .take,
            status: .rejected,
            content: "hi",
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
        let processing = Post(
            id: "p",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .take,
            status: .processing,
            content: "hi",
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
            createdAt: nil,
            moderationAction: "hold_for_review"
        )
        XCTAssertTrue(PostUseCase.takeModerationSettled(pending))
        XCTAssertTrue(PostUseCase.takeModerationSettled(gated))
        XCTAssertTrue(PostUseCase.takeModerationSettled(rejected))
        XCTAssertFalse(PostUseCase.takeModerationSettled(processing))
        XCTAssertFalse(PostUseCase.isTerminalTakeAction("hold_for_review"))

        let url0 = URL(string: "https://cdn.example/0.webp")!
        let url1 = URL(string: "https://cdn.example/1.webp")!
        let staleTextOnly = Post(
            id: "p",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .take,
            status: .moderation,
            content: "hi",
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: nil,
            imageURLs: [url0, url1],
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: nil,
            moderationAction: "publish",
            mediaBlurFlags: []
        )
        let perImageReady = Post(
            id: "p",
            creatorID: "u",
            creatorUsername: nil,
            creatorDisplayName: nil,
            creatorAvatarURL: nil,
            postType: .take,
            status: .moderation,
            content: "hi",
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: nil,
            imageURLs: [url0, url1],
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: nil,
            moderationAction: "publish",
            mediaBlurFlags: [false, false]
        )
        XCTAssertFalse(PostUseCase.takeModerationSettled(staleTextOnly))
        XCTAssertTrue(PostUseCase.takeModerationSettled(perImageReady))
        XCTAssertEqual(PostUseCase.takeModerationTimeout(imageCount: 0), 90)
        XCTAssertEqual(PostUseCase.takeModerationTimeout(imageCount: 1), 108)
        XCTAssertEqual(PostUseCase.takeModerationTimeout(imageCount: 10), 270)
    }
}

@MainActor
private final class MockTakePostRepository: PostRepositoryProtocol {
    private(set) var fetchPostCallCount = 0
    private(set) var publishPostCallCount = 0
    private let moderationReadyAfterFetches: Int

    init(moderationReadyAfterFetches: Int = 1) {
        self.moderationReadyAfterFetches = moderationReadyAfterFetches
    }

    func createTakePost(content: String?) async throws -> Post {
        Post(
            id: "take-1",
            creatorID: "user-1",
            creatorUsername: "user",
            creatorDisplayName: "User",
            creatorAvatarURL: nil,
            postType: .take,
            status: .draft,
            content: content,
            mediaKey: "media/take-1/image_0.webp,media/take-1/image_1.webp",
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

    func fetchPost(id: String) async throws -> Post {
        fetchPostCallCount += 1
        let ready = fetchPostCallCount >= moderationReadyAfterFetches
        return Post(
            id: id,
            creatorID: "user-1",
            creatorUsername: "user",
            creatorDisplayName: "User",
            creatorAvatarURL: nil,
            postType: .take,
            status: .published,
            content: "hello",
            mediaKey: "media/take-1/image_0.webp,media/take-1/image_1.webp",
            thumbnailKey: nil,
            playbackURL: URL(string: "https://cdn.example/0.webp"),
            thumbnailURL: nil,
            imageURLs: [
                URL(string: "https://cdn.example/0.webp")!,
                URL(string: "https://cdn.example/1.webp")!
            ],
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: nil,
            sensitiveBlur: ready,
            moderationAction: ready ? "publish_age_gated" : nil,
            ageGated: ready,
            mediaBlurFlags: ready ? [true, false] : []
        )
    }

    func createShotPost(
        content: String?,
        lat: Double?,
        lon: Double?,
        geoSource: String?,
        aiGeneratedLabel: Bool?
    ) async throws -> Post { fatalError("unused") }

    func pendingShotPostID(fileURL: URL) -> String? { nil }

    func pendingShotFileURLs() -> [URL] { [] }

    func shotUploadContext(fileURL: URL) -> ShotUploadContext? { nil }

    func rememberShotUploadContext(fileURL: URL, context: ShotUploadContext) {}

    func detachPendingShotUpload(fileURL: URL) {}

    func discardPendingShotUpload(fileURL: URL) {}

    func updatePost(id: String, content: String?, mediaKey: String?) async throws -> Post {
        fatalError("unused")
    }

    func schedulePost(id: String, publishAt: Date) async throws -> Post { fatalError("unused") }

    func fetchDrafts(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        fatalError("unused")
    }

    func fetchScheduled(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?) {
        fatalError("unused")
    }

    func publishPost(id: String) async throws {
        publishPostCallCount += 1
    }

    func deletePost(id: String) async throws {}

    func uploadTakeAttachments(postID: String, attachments: [PostAttachment]) async throws -> Post {
        fatalError("unused")
    }

    func uploadShot(
        postID: String,
        fileURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Post { fatalError("unused") }

    func createPoll(postID: String, question: String, options: [String], expiresAt: Date?) async throws -> Poll {
        fatalError("unused")
    }

    func votePoll(pollID: String, optionIndex: Int) async throws -> Poll { fatalError("unused") }

    func fetchPoll(postID: String) async throws -> Poll { fatalError("unused") }

    func fetchLinkPreview(url: String) async throws -> LinkPreview? { fatalError("unused") }
}
