import XCTest
@testable import AltonApp

final class NetworkSessionFactoryTests: XCTestCase {
    func testCertPinningPolicyDisabledInDebug() {
        XCTAssertFalse(CertPinningPolicy.isEnabled)
    }

    func testShouldPinAltonsTradeHosts() {
        XCTAssertTrue(CertPinningPolicy.shouldPin(host: "api.altons.trade"))
        XCTAssertTrue(CertPinningPolicy.shouldPin(host: "media.altons.trade"))
        XCTAssertFalse(CertPinningPolicy.shouldPin(host: "example.com"))
    }

    func testNetworkErrorClassifier() {
        XCTAssertTrue(NetworkErrorClassifier.isTransientNetworkFailure(URLError(.timedOut)))
        XCTAssertTrue(NetworkErrorClassifier.isAuthFailure(APIError.unauthorized))
        XCTAssertFalse(NetworkErrorClassifier.isAuthFailure(APIError.validation("bad")))
    }

    func testSessionFactoryUsesConfiguredTimeout() {
        let session = NetworkSessionFactory.makeSession(requestTimeout: 12)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 12)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 48)
    }

    func testMediaUploadSessionUsesLongTimeouts() {
        let session = NetworkSessionFactory.makeMediaUploadSession(
            requestTimeout: 120,
            resourceTimeout: 1800
        )
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 120)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 1800)
        XCTAssertTrue(session.configuration.waitsForConnectivity)
    }

    func testAllowedUploadHostsIncludeR2() {
        let env = AppEnvironment.current
        let mediaHost = env == .development ? "dev-media.altons.trade" : "media.altons.trade"
        XCTAssertTrue(env.isAllowedUploadURL(URL(string: "https://\(mediaHost)/upload/key")!))
        XCTAssertTrue(env.isAllowedUploadURL(
            URL(string: "https://abc123.r2.cloudflarestorage.com/bucket/key")!
        ))
        XCTAssertFalse(env.isAllowedUploadURL(URL(string: "https://evil.example.com/upload")!))
        XCTAssertFalse(env.isAllowedUploadURL(URL(string: "ftp://media.altons.trade/upload")!))
        if env == .development {
            XCTAssertTrue(env.isAllowedUploadURL(URL(string: "http://192.168.1.20:8086/upload/key")!))
            XCTAssertFalse(env.isAllowedUploadURL(URL(string: "http://8.8.8.8/upload/key")!))
        }
    }

    func testReadChunkStopsAtChunkSizeAndAtEndOfFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk-\(UUID().uuidString).bin")
        let payload = Data(repeating: 9, count: 12)
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let first = try MediaUploadClient.readChunk(handle: handle, offset: 0, fileSize: 12, chunkSize: 5)
        let middle = try MediaUploadClient.readChunk(handle: handle, offset: 5, fileSize: 12, chunkSize: 5)
        let tail = try MediaUploadClient.readChunk(handle: handle, offset: 10, fileSize: 12, chunkSize: 5)
        let done = try MediaUploadClient.readChunk(handle: handle, offset: 12, fileSize: 12, chunkSize: 5)

        XCTAssertEqual(first, Data(payload.prefix(5)))
        XCTAssertEqual(middle, Data(payload.dropFirst(5).prefix(5)))
        XCTAssertEqual(tail, Data(payload.suffix(2)))
        XCTAssertTrue(done.isEmpty)
    }

    func testShortNonFinalPartIsRejected() {
        let chunkSize = 5 * 1024 * 1024
        XCTAssertFalse(MediaUploadClient.acceptsPart(byteCount: 0, offset: 0, fileSize: 12_000_000, chunkSize: chunkSize))
        XCTAssertFalse(
            MediaUploadClient.acceptsPart(byteCount: 1024, offset: 0, fileSize: 12_000_000, chunkSize: chunkSize)
        )
        XCTAssertTrue(
            MediaUploadClient.acceptsPart(byteCount: chunkSize, offset: 0, fileSize: 12_000_000, chunkSize: chunkSize)
        )
        XCTAssertTrue(
            MediaUploadClient.acceptsPart(
                byteCount: 1000,
                offset: 12_000_000 - 1000,
                fileSize: 12_000_000,
                chunkSize: chunkSize
            )
        )
    }

    func testObjectKeyAndUploadIDEncoding() {
        let url = URL(string: "https://dev-media.altons.trade/upload/raw-uploads/post/original?expires=1&token=abc")!
        XCTAssertEqual(MediaUploadClient.objectKey(from: url), "raw-uploads/post/original")
        XCTAssertNil(MediaUploadClient.objectKey(from: URL(string: "https://dev-media.altons.trade/raw/original")!))
        XCTAssertNil(MediaUploadClient.objectKey(from: URL(string: "https://dev-media.altons.trade/upload/../secret")!))
        XCTAssertFalse(MediaUploadClient.pathToken("upload/id").contains("/"))
        XCTAssertTrue(MediaUploadClient.pathToken("upload/id").contains("%2F"))
    }

    func testCheckpointResumeKeepsUploadedParts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let journal = directory.appendingPathComponent("multipart-uploads.json")
        let video = directory.appendingPathComponent("clip.mp4")
        try Data(repeating: 7, count: 64).write(to: video)

        let key = "raw-uploads/post-1/original"
        let store = MultipartUploadCheckpointStore(fileURL: journal)
        let durable = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        XCTAssertNotEqual(durable.path, video.path)
        XCTAssertEqual(MediaUploadClient.fileByteCount(durable), 64)
        var checkpoint = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 64))
        checkpoint.uploadID = "upload/id"
        checkpoint.parts = [MultipartCompletedPart(etag: "etag-1", partNumber: 1)]
        checkpoint.bytesUploaded = 32
        store.save(checkpoint)

        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: durable)
        let durableResume = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 64))
        XCTAssertEqual(durableResume.bytesUploaded, 32)
        XCTAssertEqual(durableResume.uploadID, "upload/id")
        XCTAssertEqual(durableResume.parts, [MultipartCompletedPart(etag: "etag-1", partNumber: 1)])

        try FileManager.default.removeItem(at: video)
        let resumed = MultipartUploadCheckpointStore(fileURL: journal)
        XCTAssertEqual(resumed.pendingPostID(fileURL: video), "post-1")
        let pending = try XCTUnwrap(resumed.pendingFileURLs().first)
        XCTAssertEqual(try Data(contentsOf: pending), Data(repeating: 7, count: 64))
        try Data(repeating: 7, count: 64).write(to: video)

        _ = try resumed.bind(postID: "post-1", objectKey: key, fileURL: video)
        let loaded = try XCTUnwrap(resumed.checkpoint(objectKey: key, fileSize: 64))
        XCTAssertEqual(loaded.bytesUploaded, 32)
        XCTAssertEqual(loaded.uploadID, "upload/id")
        XCTAssertEqual(loaded.parts, [MultipartCompletedPart(etag: "etag-1", partNumber: 1)])
        XCTAssertEqual(resumed.pendingPostID(fileURL: video), "post-1")

        try Data(repeating: 1, count: 10).write(to: video)
        _ = try resumed.bind(postID: "post-2", objectKey: key, fileURL: video)
        let reset = try XCTUnwrap(resumed.checkpoint(objectKey: key, fileSize: 10))
        XCTAssertEqual(reset.bytesUploaded, 0)
        XCTAssertNil(reset.uploadID)
        XCTAssertTrue(reset.parts.isEmpty)
        XCTAssertEqual(resumed.pendingPostID(fileURL: video), "post-2")

        resumed.remove(objectKey: key)
        XCTAssertNil(resumed.pendingPostID(fileURL: video))
        XCTAssertFalse(FileManager.default.fileExists(atPath: durable.path))
        let reloaded = MultipartUploadCheckpointStore(fileURL: journal)
        XCTAssertNil(reloaded.checkpoint(objectKey: key, fileSize: 10))
    }

    func testSameSizeReplacementResetsPartsAndKeepsCaption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-replace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let journal = directory.appendingPathComponent("multipart-uploads.json")
        let video = directory.appendingPathComponent("clip.mp4")
        try Data(repeating: 7, count: 64).write(to: video)
        let store = MultipartUploadCheckpointStore(fileURL: journal)
        let key = "raw-uploads/post-1/original"
        store.rememberUploadContext(
            fileURL: video,
            context: ShotUploadContext(caption: "sunset", lat: 1, lon: 2, geoSource: "user", aiGeneratedLabel: true)
        )
        let durable = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        var checkpoint = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 64))
        checkpoint.bytesUploaded = 32
        checkpoint.parts = [MultipartCompletedPart(etag: "etag-1", partNumber: 1)]
        checkpoint.uploadID = "upload-1"
        store.save(checkpoint)

        try Data(repeating: 3, count: 64).write(to: video)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(30)],
            ofItemAtPath: video.path
        )
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        let reset = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 64))
        XCTAssertEqual(reset.bytesUploaded, 0)
        XCTAssertTrue(reset.parts.isEmpty)
        XCTAssertNil(reset.uploadID)
        XCTAssertEqual(try Data(contentsOf: durable), Data(repeating: 3, count: 64))
        XCTAssertEqual(store.uploadContext(fileURL: video)?.caption, "sunset")

        store.detachFile(video)
        XCTAssertNil(store.pendingPostID(fileURL: video))
        XCTAssertTrue(FileManager.default.fileExists(atPath: durable.path))
        store.removeFile(video)
    }

    func testSameModificationDateStillDetectsDifferentBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-mtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let video = directory.appendingPathComponent("clip.mp4")
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try Data(repeating: 7, count: 64).write(to: video)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: video.path)
        let store = MultipartUploadCheckpointStore(fileURL: directory.appendingPathComponent("journal.json"))
        let key = "raw-uploads/post-1/original"
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        var checkpoint = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 64))
        checkpoint.bytesUploaded = 40
        checkpoint.uploadID = "upload-1"
        checkpoint.parts = [MultipartCompletedPart(etag: "e", partNumber: 1)]
        store.save(checkpoint)

        try Data(repeating: 2, count: 64).write(to: video)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: video.path)
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        let reset = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 64))
        XCTAssertEqual(reset.bytesUploaded, 0)
        XCTAssertTrue(reset.parts.isEmpty)
        XCTAssertNil(reset.uploadID)
    }

    func testSameSizeMiddleChangeResetsParts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-middle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let video = directory.appendingPathComponent("clip.mp4")
        var bytes = Data(repeating: 7, count: 200_000)
        try bytes.write(to: video)
        let store = MultipartUploadCheckpointStore(fileURL: directory.appendingPathComponent("journal.json"))
        let key = "raw-uploads/post-1/original"
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        var checkpoint = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 200_000))
        checkpoint.bytesUploaded = 65_536
        checkpoint.uploadID = "upload-1"
        checkpoint.parts = [MultipartCompletedPart(etag: "e", partNumber: 1)]
        store.save(checkpoint)

        bytes[100_000] = 9
        try bytes.write(to: video)
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        let reset = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 200_000))
        XCTAssertEqual(reset.bytesUploaded, 0)
        XCTAssertTrue(reset.parts.isEmpty)
        XCTAssertNil(reset.uploadID)
        XCTAssertTrue(reset.contentHash?.hasPrefix("sha256:") == true)
    }

    func testLegacyEdgeHashKeepsPartsWhenBytesMatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let video = directory.appendingPathComponent("clip.mp4")
        try Data(repeating: 4, count: 200_000).write(to: video)
        let store = MultipartUploadCheckpointStore(fileURL: directory.appendingPathComponent("journal.json"))
        let key = "raw-uploads/post-1/original"
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        var checkpoint = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 200_000))
        checkpoint.bytesUploaded = 65_536
        checkpoint.uploadID = "upload-1"
        checkpoint.parts = [MultipartCompletedPart(etag: "e", partNumber: 1)]
        checkpoint.contentHash = "legacy-edge"
        store.save(checkpoint)

        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        let kept = try XCTUnwrap(store.checkpoint(objectKey: key, fileSize: 200_000))
        XCTAssertEqual(kept.bytesUploaded, 65_536)
        XCTAssertEqual(kept.uploadID, "upload-1")
        XCTAssertEqual(kept.parts, [MultipartCompletedPart(etag: "e", partNumber: 1)])
        XCTAssertTrue(kept.contentHash?.hasPrefix("sha256:") == true)
    }

    @MainActor
    func testCancelKeepsShotUploadActiveUntilTheTaskExits() {
        let state = AppState()
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        let token = state.beginShotUpload(url)
        XCTAssertTrue(state.hasActiveShotUpload)
        XCTAssertTrue(state.isCurrentShotUpload(token))

        state.cancelTrackedShotUpload()
        XCTAssertTrue(state.hasActiveShotUpload)
        XCTAssertFalse(state.isCurrentShotUpload(token))

        state.endShotUpload(url)
        XCTAssertFalse(state.hasActiveShotUpload)
    }

    func testShotUploadCancellationPolicy() {
        XCTAssertEqual(ShotUploadCancellationPolicy.outcome(for: nil), .keepForResume)
        XCTAssertEqual(ShotUploadCancellationPolicy.outcome(for: .draft), .discardLocalCopy)
        XCTAssertEqual(ShotUploadCancellationPolicy.outcome(for: .processing), .keepForResume)
        XCTAssertEqual(ShotUploadCancellationPolicy.outcome(for: .moderation), .accepted)
        XCTAssertEqual(ShotUploadCancellationPolicy.outcome(for: .published), .accepted)
        XCTAssertEqual(ShotUploadCancellationPolicy.outcome(for: .rejected), .accepted)
        XCTAssertTrue(ShotUploadResumePolicy.reusesExistingShot(.draft))
        XCTAssertTrue(ShotUploadResumePolicy.reusesExistingShot(.processing))
        XCTAssertFalse(ShotUploadResumePolicy.reusesExistingShot(.published))
        XCTAssertFalse(ShotUploadResumePolicy.reusesExistingShot(.moderation))
        XCTAssertFalse(ShotUploadCompletionRetry.shouldSendUploadComplete(status: .published, mediaKey: nil))
        XCTAssertFalse(ShotUploadCompletionRetry.shouldSendUploadComplete(status: .processing, mediaKey: "media/post/video.mp4"))
        XCTAssertTrue(ShotUploadCompletionRetry.shouldSendUploadComplete(status: .processing, mediaKey: nil))
        XCTAssertTrue(ShotUploadCompletionRetry.shouldSendUploadComplete(status: .processing, mediaKey: "raw-uploads/post/original"))
        XCTAssertFalse(ShotResumeBatch.shouldDelete(uploadStarted: false))
        XCTAssertTrue(ShotResumeBatch.shouldDelete(uploadStarted: true))
    }

    @MainActor
    func testSecondShotUploadKeepsTheFirstToken() {
        let state = AppState()
        let first = URL(fileURLWithPath: "/tmp/first.mp4")
        let second = URL(fileURLWithPath: "/tmp/second.mp4")
        let firstToken = state.beginShotUpload(first)
        let secondToken = state.beginShotUpload(second)
        XCTAssertTrue(state.isCurrentShotUpload(firstToken))
        XCTAssertTrue(state.isVisibleShotUpload(secondToken))

        state.cancelTrackedShotUpload()
        XCTAssertTrue(state.isCurrentShotUpload(firstToken))
        XCTAssertFalse(state.isCurrentShotUpload(secondToken))
        XCTAssertTrue(state.isVisibleShotUpload(firstToken))
        XCTAssertTrue(state.hasActiveShotUpload)

        state.endShotUpload(second)
        XCTAssertTrue(state.hasActiveShotUpload)
        state.endShotUpload(first)
        XCTAssertFalse(state.hasActiveShotUpload)
    }

    @MainActor
    func testSecondCancelStopsThePreviousShotTask() async {
        let state = AppState()
        let first = URL(fileURLWithPath: "/tmp/first.mp4")
        let second = URL(fileURLWithPath: "/tmp/second.mp4")
        let firstToken = state.beginShotUpload(first)
        let secondToken = state.beginShotUpload(second)
        let firstCancelled = expectation(description: "first cancelled")
        let secondCancelled = expectation(description: "second cancelled")
        let firstTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(60)) }
            catch is CancellationError { firstCancelled.fulfill() }
            catch {}
        }
        let secondTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(60)) }
            catch is CancellationError { secondCancelled.fulfill() }
            catch {}
        }
        state.trackShotUpload(first, firstTask)
        state.trackShotUpload(second, secondTask)

        state.cancelTrackedShotUpload()
        await fulfillment(of: [secondCancelled], timeout: 2)
        XCTAssertTrue(state.isCurrentShotUpload(firstToken))
        XCTAssertFalse(state.isCurrentShotUpload(secondToken))

        state.cancelTrackedShotUpload()
        await fulfillment(of: [firstCancelled], timeout: 2)
        XCTAssertFalse(state.isCurrentShotUpload(firstToken))
        firstTask.cancel()
        secondTask.cancel()
    }

    @MainActor
    func testCancelledCompleteDoesNotResumeAutomatically() {
        let state = AppState()
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        state.suppressAutomaticResume(url)
        XCTAssertFalse(state.allowsAutomaticResume(url))
        _ = state.beginShotUpload(url)
        XCTAssertTrue(state.allowsAutomaticResume(url))
    }

    func testExplicitResumeFlagSurvivesProcessRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-explicit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let video = directory.appendingPathComponent("clip.mp4")
        try Data(repeating: 7, count: 32).write(to: video)
        let journal = directory.appendingPathComponent("journal.json")
        let key = "raw-uploads/post-1/original"
        let store = MultipartUploadCheckpointStore(fileURL: journal)
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        store.markCompleteUnconfirmed(objectKey: key)
        XCTAssertTrue(store.requiresExplicitResume(fileURL: video))
        XCTAssertTrue(store.completeMayHaveLanded(objectKey: key))

        let reloaded = MultipartUploadCheckpointStore(fileURL: journal)
        XCTAssertTrue(reloaded.requiresExplicitResume(fileURL: video))
        XCTAssertTrue(reloaded.completeMayHaveLanded(objectKey: key))
        reloaded.allowAutomaticResume(fileURL: video)
        XCTAssertFalse(reloaded.requiresExplicitResume(fileURL: video))
        XCTAssertTrue(reloaded.completeMayHaveLanded(objectKey: key))
        XCTAssertTrue(reloaded.blocksAutomaticResume(fileURL: video))

        let pausedOnly = directory.appendingPathComponent("paused.mp4")
        try Data(repeating: 8, count: 32).write(to: pausedOnly)
        _ = try reloaded.bind(postID: "post-2", objectKey: "raw-uploads/post-2/original", fileURL: pausedOnly)
        reloaded.requireExplicitResume(fileURL: pausedOnly)
        XCTAssertTrue(reloaded.requiresExplicitResume(fileURL: pausedOnly))
        XCTAssertFalse(reloaded.completeMayHaveLanded(objectKey: "raw-uploads/post-2/original"))
        reloaded.allowAutomaticResume(fileURL: pausedOnly)
        XCTAssertFalse(reloaded.blocksAutomaticResume(fileURL: pausedOnly))
    }

    func testAcceptedCompleteStaysOutOfAutomaticResumeUntilMediaIsAttached() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-accepted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let video = directory.appendingPathComponent("clip.mp4")
        try Data(repeating: 9, count: 32).write(to: video)
        let journal = directory.appendingPathComponent("journal.json")
        let key = "raw-uploads/post-1/original"
        let store = MultipartUploadCheckpointStore(fileURL: journal)
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        store.markServerAcceptedComplete(objectKey: key)

        XCTAssertTrue(store.pendingFileURLs().isEmpty)
        XCTAssertFalse(store.blocksAutomaticResume(fileURL: video))
        XCTAssertEqual(store.serverAcceptedCompletes(), [AcceptedShotUpload(postID: "post-1", objectKey: key)])
        XCTAssertEqual(store.pendingPostID(fileURL: video), "post-1")

        let reloaded = MultipartUploadCheckpointStore(fileURL: journal)
        XCTAssertEqual(reloaded.serverAcceptedCompletes().map(\.postID), ["post-1"])
        XCTAssertTrue(reloaded.pendingFileURLs().isEmpty)
        reloaded.removePost("post-1")
        XCTAssertTrue(reloaded.serverAcceptedCompletes().isEmpty)
        XCTAssertNil(reloaded.pendingPostID(fileURL: video))
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
    }

    func testAcceptedJournalDropsAMissingPostAndKeepsAFailedFetch() {
        XCTAssertEqual(AcceptedShotJournal.action(for: .missing, resendIncomplete: true), .drop)
        XCTAssertEqual(AcceptedShotJournal.action(for: .unavailable, resendIncomplete: true), .keep)
        XCTAssertEqual(
            AcceptedShotJournal.action(
                for: .loaded(status: .published, mediaKey: "video/hash/playback.mp4"),
                resendIncomplete: true
            ),
            .drop
        )
        XCTAssertEqual(
            AcceptedShotJournal.action(for: .loaded(status: .processing, mediaKey: nil), resendIncomplete: true),
            .resend
        )
        XCTAssertEqual(
            AcceptedShotJournal.action(for: .loaded(status: .processing, mediaKey: nil), resendIncomplete: false),
            .keep
        )
        XCTAssertFalse(AcceptedShotWatch.shouldStart(resendIncomplete: false, watchRunning: true))
        XCTAssertTrue(AcceptedShotWatch.shouldStart(resendIncomplete: true, watchRunning: true))
        XCTAssertTrue(AcceptedShotWatch.shouldStart(resendIncomplete: false, watchRunning: false))
        XCTAssertTrue(AcceptedShotWatch.clearsResentAfterPreviousFinishes(resendIncomplete: true))
        XCTAssertFalse(AcceptedShotWatch.clearsResentAfterPreviousFinishes(resendIncomplete: false))
        XCTAssertTrue(AcceptedShotWatch.mayMutateAcceptedState(watchGeneration: 2, activeGeneration: 2))
        XCTAssertFalse(AcceptedShotWatch.mayMutateAcceptedState(watchGeneration: 1, activeGeneration: 2))
        XCTAssertTrue(AcceptedShotResend.allows(passRequestsResend: true, alreadySucceeded: false))
        XCTAssertFalse(AcceptedShotResend.allows(passRequestsResend: true, alreadySucceeded: true))
        XCTAssertFalse(AcceptedShotResend.allows(passRequestsResend: false, alreadySucceeded: false))

        // stop→recover: await the cancelled task (ending) when current was cleared.
        XCTAssertEqual(
            AcceptedShotWatch.previousTaskToAwait(current: Optional<Int>.none, ending: Optional(7)),
            7
        )
        XCTAssertEqual(
            AcceptedShotWatch.previousTaskToAwait(current: Optional(3), ending: Optional(7)),
            3
        )
    }

    func testDetachKeepsCaptionForTheNextDraft() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-caption-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let video = directory.appendingPathComponent("clip.mp4")
        try Data(repeating: 5, count: 32).write(to: video)
        let store = MultipartUploadCheckpointStore(fileURL: directory.appendingPathComponent("journal.json"))
        let key = "raw-uploads/post-1/original"
        store.rememberUploadContext(
            fileURL: video,
            context: ShotUploadContext(caption: "sunset", lat: 1, lon: 2, geoSource: "user", aiGeneratedLabel: nil)
        )
        _ = try store.bind(postID: "post-1", objectKey: key, fileURL: video)
        store.detachFile(video)
        _ = try store.bind(postID: "post-2", objectKey: "raw-uploads/post-2/original", fileURL: video)
        XCTAssertEqual(store.uploadContext(fileURL: video)?.caption, "sunset")
        XCTAssertEqual(store.uploadContext(fileURL: video)?.lat, 1)
        XCTAssertEqual(store.checkpoint(objectKey: "raw-uploads/post-2/original", fileSize: 32)?.bytesUploaded, 0)
    }

    func testChunkedUploadSendsEveryByteThenResumes() async throws {
        let previousChunk = MediaUploadClient.chunkSize
        let previousStore = MultipartUploadCheckpointStore.current
        MediaUploadClient.chunkSize = 5
        defer {
            MediaUploadClient.chunkSize = previousChunk
            MultipartUploadCheckpointStore.current = previousStore
            MultipartStubURLProtocol.responder = nil
            MultipartStubURLProtocol.requests = []
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart-http-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = directory.appendingPathComponent("clip.mp4")
        let payload = Data(repeating: 9, count: 12)
        try payload.write(to: video)
        let store = MultipartUploadCheckpointStore(fileURL: directory.appendingPathComponent("journal.json"))
        MultipartUploadCheckpointStore.current = store

        MultipartStubURLProtocol.responder = Self.multipartResponder
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultipartStubURLProtocol.self]
        let client = MediaUploadClient(session: URLSession(configuration: configuration), maxAttempts: 1)
        let uploadURL = URL(string: "https://dev-media.altons.trade/upload/raw-uploads/post/original?expires=1&token=t")!

        try await client.upload(fileURL: video, to: uploadURL, contentType: "video/mp4")
        let first = MultipartStubURLProtocol.requests
        XCTAssertEqual(first.filter { $0.httpMethod == "PUT" }.count, 3)
        XCTAssertEqual(first.filter { $0.url?.path.hasSuffix("/multipart") == true }.count, 1)
        let completed = try XCTUnwrap(first.last { $0.url?.path.hasSuffix("/complete") == true })
        let parts = try JSONDecoder().decode([MultipartCompletedPart].self, from: Self.bodyData(completed))
        XCTAssertEqual(parts.map(\.partNumber), [1, 2, 3])
        XCTAssertEqual(store.checkpoint(objectKey: "raw-uploads/post/original", fileSize: 12)?.bytesUploaded, 12)

        MultipartStubURLProtocol.requests = []
        var partial = try XCTUnwrap(store.checkpoint(objectKey: "raw-uploads/post/original", fileSize: 12))
        partial.assembled = false
        partial.bytesUploaded = 5
        partial.parts = [MultipartCompletedPart(etag: "etag-1", partNumber: 1)]
        partial.uploadID = "up-1"
        store.save(partial)
        try await client.upload(fileURL: video, to: uploadURL, contentType: "video/mp4")
        let second = MultipartStubURLProtocol.requests
        XCTAssertEqual(second.filter { $0.httpMethod == "PUT" }.count, 2)
        XCTAssertFalse(second.contains { $0.url?.path.hasSuffix("/multipart") == true })
        let resumedComplete = try XCTUnwrap(second.last { $0.url?.path.hasSuffix("/complete") == true })
        let resumedParts = try JSONDecoder().decode([MultipartCompletedPart].self, from: Self.bodyData(resumedComplete))
        XCTAssertEqual(resumedParts.map(\.partNumber), [1, 2, 3])
    }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func multipartResponder(_ request: URLRequest) -> (Int, Data) {
        let path = request.url?.path ?? ""
        if request.httpMethod == "POST", path.hasSuffix("/multipart") {
            return (200, Data(#"{"upload_id":"up-1"}"#.utf8))
        }
        if request.httpMethod == "PUT" {
            let part = path.split(separator: "/").last.map(String.init) ?? "0"
            return (200, Data("{\"etag\":\"etag-\(part)\",\"partNumber\":\(part)}".utf8))
        }
        return (204, Data())
    }
}

private final class MultipartStubURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var responder: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        Self.lock.lock()
        Self.requests.append(request)
        let responder = Self.responder
        Self.lock.unlock()
        let (status, body) = responder?(request) ?? (500, Data())
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
