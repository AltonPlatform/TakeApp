import AVFoundation
import Observation
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class CameraViewModel: FrameProcessorDelegate, CameraSessionDelegate {
    enum Phase: Equatable {
        case capturing
        case countdown(Int)
        case editing(clips: [URL])
        case publication(videoURL: URL)
        case previewPhoto(URL)
        case uploading
    }

    struct SelectedLocation: Equatable {
        var name: String
        var lat: Double
        var lon: Double
    }

    var captureMode: CaptureMode = .video15
    var flashController = FlashController()
    var timerDelay: TimerDelay = .none
    var exposureController = ExposureController()
    var speedController = SpeedController()
    var activeFilterID: String = "original"
    var beautyIntensity: Double = 0
    var exposureBias: Float = 0
    var isGreenScreenEnabled = false
    var greenScreenMode: GreenScreenMode = .personSegmentation
    var greenScreenSensitivity: Double = 0.35
    var greenScreenFeather: Double = 0.5
    var greenScreenBackgroundSource: BackgroundSource = .color(hex: "#1A2640")
    var isRecording = false
    var recordingProgress: Double = 0
    var recordingDuration: TimeInterval = 0
    var phase: Phase = .capturing
    var focusIndicator: FocusIndicatorState?
    var zoomFactor: CGFloat = 1.0
    var errorMessage: String?
    var caption = ""
    var aiGeneratedLabel = false
    var selectedLocation: SelectedLocation?
    var thumbnailTime: CMTime = .zero
    var coverImage: UIImage?
    var isExportingBasicEdit = false
    var isSavingDraft = false
    var isRestoringDraft = false
    var isUploading = false
    var uploadProgress: Double = 0
    var uploadStatusText: String?
    var isInterrupted = false
    private var publishTask: Task<Void, Never>?
    private let draftStore = DraftStore.makePersistent()
    /// Clips held while the full editor is open so we can return to basic editing.
    private var basicEditingClips: [URL] = []
    var isCameraReady = false
    var isPreparing = true
    var isImportingFromGallery = false
    var isGalleryPickerActive = false
    var isAudioEnabled = false
    var audioWarning: String?
    var showPaywall = false
    var showAdvancedControls = false

    let cameraSession: CameraSession
    private let postUseCase: PostUseCase
    private let appState: AppState
    private let timerController = TimerController()
    private var prepareGeneration = 0
    private var hasPreparedSession = false
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var isEditorReshoot = false
    private var editorReshootClips: [URL] = []

    let availableFilters: [any CameraFilter] = BuiltInCameraFilter.allFilters

    var isPremium: Bool { appState.isPremium }
    var cameraPosition: AVCaptureDevice.Position { cameraSession.cameraPosition }
    var zoomStops: [ZoomStop] { cameraSession.zoomStops }
    var previewRenderer: MetalPreviewRenderer { cameraSession.frameProcessor.previewRenderer }

    var showsFlashControl: Bool {
        captureMode.isPhoto ? cameraSession.hasFlash : cameraSession.hasTorch
    }

    init(postUseCase: PostUseCase, appState: AppState) {
        self.postUseCase = postUseCase
        self.appState = appState
        self.cameraSession = CameraSession()
        cameraSession.delegate = self
        cameraSession.frameProcessor.delegate = self
        configureTimerController()
        syncProcessingSettings()
    }

    func prepareIfNeeded() async {
        if hasPreparedSession {
            guard case .capturing = phase else { return }
            cameraSession.setAutomaticLifecycleEnabled(true)
            cameraSession.resumeIfNeeded()
            isCameraReady = true
            isPreparing = false
            isInterrupted = false
            return
        }
        await prepare()
    }

    func prepare() async {
        prepareGeneration += 1
        let generation = prepareGeneration
        isPreparing = true
        isCameraReady = false
        errorMessage = nil
        isInterrupted = false
        CaptureOrientationManager.refreshCachedOrientation()

        do {
            try await cameraSession.configure(enableMicrophone: true)
            guard generation == prepareGeneration else { return }
            cameraSession.startRunning()
            zoomFactor = cameraSession.zoomFactor
            exposureController.syncLimits(from: cameraSession.deviceManager)
            syncProcessingSettings()
            isAudioEnabled = cameraSession.isAudioCaptureEnabled
            audioWarning = isAudioEnabled
                ? nil
                : CaptureError.permissionDenied(.microphone).errorDescription
            isCameraReady = true
            hasPreparedSession = true
            cameraSession.warmUpRecording()
            // Warm Photos auth so the gallery picker isn't blocked on first tap.
            Task.detached(priority: .utility) {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
        } catch {
            guard generation == prepareGeneration else { return }
            errorMessage = error.localizedDescription
            isCameraReady = false
            hasPreparedSession = false
        }
        isPreparing = false
    }

    func stopSessionUnlessPresentingGallery() async {
        guard !isGalleryPickerActive else { return }
        await stopSession()
    }

    func stopSession() async {
        prepareGeneration += 1
        stopRecordingTimer()
        timerController.cancel()
        if isRecording {
            cameraSession.cancelRecording()
            isRecording = false
        }
        await cameraSession.shutdown()
        isInterrupted = false
        isCameraReady = false
        isPreparing = false
        hasPreparedSession = false
        errorMessage = nil
    }

    func beginGalleryPresentation() {
        // Do not stop AVCaptureSession or clear Metal frames — that made the picker slow
        // and looked like the camera freezing. Only mark the flag so onDisappear won't tear down.
        isGalleryPickerActive = true
        isInterrupted = false
        // Ignore capture interruptions while Photos UI is covering the camera.
        cameraSession.setAutomaticLifecycleEnabled(false)
    }

    func endGalleryPresentation() {
        isGalleryPickerActive = false
        isInterrupted = false
        cameraSession.setAutomaticLifecycleEnabled(true)
        // If the system interrupted capture under the picker, resume without a full reconfigure.
        guard case .capturing = phase else { return }
        cameraSession.resumeIfNeeded()
    }

    func selectCaptureMode(_ mode: CaptureMode) {
        if mode.requiresPremium && !isPremium {
            showPaywall = true
            return
        }

        if isRecording {
            Task { await stopRecordingAndPreview() }
        }
        captureMode = mode
        syncProcessingSettings()
    }

    func cycleFlashMode() {
        flashController.cycle()
    }

    func cycleTimerDelay() {
        timerDelay = timerDelay.next()
    }

    func cycleSpeed() {
        speedController.cycle()
        Task {
            try? await cameraSession.setCaptureSpeed(speedController.speed)
        }
    }

    func selectFilter(_ filter: any CameraFilter) {
        activeFilterID = filter.id
        cameraSession.frameProcessor.filterEngine.activeFilter = filter.id == "original" ? nil : filter
    }

    func flipCamera() async {
        do {
            try await cameraSession.flipCamera(enableMicrophone: true)
            zoomFactor = cameraSession.zoomFactor
            syncProcessingSettings()
            CaptureOrientationManager.refreshCachedOrientation()
            cameraSession.warmUpRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectZoom(_ factor: CGFloat) {
        zoomFactor = factor
        cameraSession.setZoomFactor(factor)
    }

    func setZoom(_ factor: CGFloat) {
        zoomFactor = factor
        cameraSession.setZoomFactor(factor)
    }

    func focus(at normalizedPoint: CGPoint, lock: Bool) {
        cameraSession.focus(at: normalizedPoint, lock: lock)
    }

    func setExposureBias(_ bias: Float) {
        let clamped = exposureController.clampedBias(bias)
        exposureBias = clamped
        exposureController.bias = clamped
        cameraSession.setExposureBias(clamped)
    }

    func shutterTapped() {
        switch captureMode {
        case .photo:
            beginPhotoCapture()
        default:
            toggleRecording()
        }
    }

    func toggleRecording() {
        if isRecording {
            Task { await stopRecordingAndPreview() }
        } else if timerDelay == .none {
            startRecording()
        } else {
            timerController.start(delay: timerDelay)
        }
    }

    func discardPreview() {
        var resumeAfterPhotoPreview = false
        switch phase {
        case .previewPhoto(let url):
            TemporaryCaptureStore.removeItem(at: url)
            resumeAfterPhotoPreview = true
        case .publication(let url):
            TemporaryCaptureStore.removeItem(at: url)
        case .editing(let clips):
            clips.forEach { TemporaryCaptureStore.removeItem(at: $0) }
        default:
            break
        }
        phase = .capturing
        caption = ""
        aiGeneratedLabel = false
        selectedLocation = nil
        thumbnailTime = .zero
        coverImage = nil
        basicEditingClips = []
        recordingDuration = 0
        recordingProgress = 0
        isEditorReshoot = false
        editorReshootClips = []
        stopRecordingTimer()
        Task {
            if resumeAfterPhotoPreview {
                cameraSession.resumeIfNeeded()
            } else {
                try? CameraSessionConfigurator.configureAudioSession(cameraPosition: cameraPosition)
                await cameraSession.restoreCaptureAfterEditor()
            }
        }
    }

    func openFullEditorFromPublication() {
        guard case .publication(let url) = phase else { return }
        basicEditingClips = [url]
        phase = .editing(clips: [url])
    }

    func returnToPublicationFromEditor() {
        let clips = basicEditingClips.isEmpty
            ? {
                if case .editing(let c) = phase { return c }
                return []
            }()
            : basicEditingClips
        guard !clips.isEmpty else {
            discardPreview()
            return
        }
        if clips.count == 1 {
            phase = .publication(videoURL: clips[0])
        } else {
            Task { await goToPublication(clips: clips) }
        }
    }

    func completeEditing(with exportURL: URL, sourceClipURLs: [URL]) {
        // Full editor export returns to publication (single exported clip).
        basicEditingClips = [exportURL]
        phase = .publication(videoURL: exportURL)
        coverImage = nil
        thumbnailTime = .zero
        Task { @MainActor in
            coverImage = await CoverFramePicker.generateFrame(from: exportURL, at: .zero)
            for _ in 0..<5 {
                await Task.yield()
            }
            try? await Task.sleep(for: .milliseconds(300))
            TemporaryCaptureStore.purgeUnreferenced(keeping: [exportURL])
            for url in sourceClipURLs where url != exportURL {
                TemporaryCaptureStore.removeIfManaged(url)
            }
        }
    }

    /// Transition directly to the publication screen from a set of clips.
    /// Exports multiple clips if needed and generates a cover frame.
    func goToPublication(clips: [URL]) async {
        guard !clips.isEmpty else { return }
        isExportingBasicEdit = true
        errorMessage = nil
        defer { isExportingBasicEdit = false }

        do {
            let exportURL: URL
            if clips.count == 1 {
                exportURL = clips[0]
            } else {
                exportURL = try await exportClipsLosslessOrEncode(clips)
            }
            basicEditingClips = clips
            phase = .publication(videoURL: exportURL)
            if coverImage == nil {
                coverImage = await CoverFramePicker.generateFrame(from: exportURL, at: thumbnailTime)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if !isCameraReady {
                await cameraSession.restoreCaptureAfterEditor()
                isCameraReady = true
            }
            phase = .capturing
        }
    }

    func backFromPublication() {
        guard case .publication = phase else { return }
        discardPreview()
    }

    private func exportClipsLosslessOrEncode(_ clips: [URL]) async throws -> URL {
        var videoClips: [VideoClip] = []
        for url in clips {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            videoClips.append(VideoClip.make(from: url, duration: duration))
        }
        let project = EditorProject(clips: videoClips)
        project.updateCompositionStartTimes()
        return try await ExportEngine().export(project: project, quality: .p1080) { _ in }
    }

    func startEditorReshoot(existingClips: [URL]) {
        editorReshootClips = existingClips
        isEditorReshoot = true
        phase = .capturing
        recordingDuration = 0
        recordingProgress = 0
        Task {
            try? CameraSessionConfigurator.configureAudioSession(cameraPosition: cameraPosition)
            await cameraSession.restoreCaptureAfterEditor()
        }
    }

    /// Starts background upload and immediately invokes `onStarted` so the camera can dismiss.
    func publishVideo(onStarted: @escaping () -> Void) {
        guard case .publication(let url) = phase else { return }
        guard !isUploading else { return }
        isUploading = true

        let captionCopy = caption
        let aiLabel = aiGeneratedLabel
        let location = selectedLocation
        let thumbTime = thumbnailTime
        errorMessage = nil

        appState.showUploadBanner("Preparing shot…", progress: 0)
        onStarted()

        let useCase = postUseCase
        let state = appState
        let task = Task { @MainActor in
            await Self.performBackgroundPublish(
                url: url,
                caption: captionCopy,
                lat: location?.lat,
                lon: location?.lon,
                geoSource: location.map { _ in "user" },
                aiGeneratedLabel: aiLabel ? true : nil,
                thumbnailTime: thumbTime,
                postUseCase: useCase,
                appState: state
            )
        }
        appState.trackShotUpload(url, task)
    }

    func saveShotDraft() async -> Bool {
        guard case .publication(let url) = phase else { return false }
        isSavingDraft = true
        defer { isSavingDraft = false }
        do {
            let draftDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ShotDrafts", isDirectory: true)
            try FileManager.default.createDirectory(at: draftDir, withIntermediateDirectories: true)
            let dest = draftDir.appendingPathComponent("\(UUID().uuidString).mp4")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)

            var thumbURL: URL?
            if let coverImage,
               let data = coverImage.jpegData(compressionQuality: 0.85) {
                let t = draftDir.appendingPathComponent("\(UUID().uuidString)-cover.jpg")
                try data.write(to: t)
                thumbURL = t
            }

            _ = try draftStore.upsertShotDraft(
                id: nil,
                content: caption,
                videoURL: dest,
                thumbnailURL: thumbURL,
                aiGeneratedLabel: aiGeneratedLabel,
                lat: selectedLocation?.lat,
                lon: selectedLocation?.lon,
                locationName: selectedLocation?.name
            )
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func cancelPublish() {
        publishTask?.cancel()
        publishTask = nil
        appState.clearUploadBanner()
        isUploading = false
        uploadStatusText = nil
    }

    /// Restores a saved shot draft into the publication flow.
    func beginShotDraft(id: UUID) async {
        isRestoringDraft = true
        defer { isRestoringDraft = false }
        do {
            guard let payload = try draftStore.loadShotDraft(id: id) else {
                errorMessage = "Could not find this draft."
                return
            }
            var videoURL = payload.videoURL
            if !FileManager.default.fileExists(atPath: videoURL.path) {
                let legacyPath = videoURL.path.replacingOccurrences(of: "/ShotDrafts/", with: "/VideoDrafts/")
                if FileManager.default.fileExists(atPath: legacyPath) {
                    videoURL = URL(fileURLWithPath: legacyPath)
                }
            }
            // Verify the video file still exists.
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                errorMessage = "The shot file for this draft is missing."
                return
            }
            caption = payload.content
            aiGeneratedLabel = payload.aiGeneratedLabel
            if let lat = payload.lat, let lon = payload.lon {
                selectedLocation = SelectedLocation(
                    name: payload.locationName ?? "",
                    lat: lat,
                    lon: lon
                )
            } else {
                selectedLocation = nil
            }
            thumbnailTime = .zero
            if let thumbURL = payload.thumbnailURL,
               let data = try? Data(contentsOf: thumbURL) {
                coverImage = UIImage(data: data)
            } else {
                coverImage = await CoverFramePicker.generateFrame(from: videoURL, at: .zero)
            }
            basicEditingClips = [videoURL]
            phase = .publication(videoURL: videoURL)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    static func performBackgroundPublish(
        url: URL,
        caption: String?,
        lat: Double?,
        lon: Double?,
        geoSource: String?,
        aiGeneratedLabel: Bool?,
        thumbnailTime: CMTime = .zero,
        postUseCase: PostUseCase,
        appState: AppState
    ) async {
        var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PublishVideo") {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        func endBackgroundTask() {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        defer { endBackgroundTask() }

        if Task.isCancelled {
            ShotResumeBatch.keepUnstartedFile(url: url, postUseCase: postUseCase, appState: appState)
            if !appState.hasActiveShotUpload {
                if postUseCase.shotRequiresExplicitResume(fileURL: url) {
                    appState.showUploadBanner("Upload paused.", canResume: true)
                } else {
                    appState.clearUploadBanner()
                }
            }
            return
        }

        PipelineLogger.camera.info("publishVideo \(PipelineLogger.fileSummary(url), privacy: .public)")
        let uploadToken = appState.beginShotUpload(url)

        // Best-effort cover frame generation (server also derives thumbnails).
        _ = thumbnailTime

        do {
            let outcome = try await postUseCase.createAndPublishShot(
                localVideoURL: url,
                caption: caption,
                lat: lat,
                lon: lon,
                geoSource: geoSource,
                aiGeneratedLabel: aiGeneratedLabel,
                onProgress: { progress in
                    Task { @MainActor in
                        guard appState.isVisibleShotUpload(uploadToken) else { return }
                        switch progress {
                        case .preparing:
                            appState.showUploadBanner("Preparing shot…", progress: 0)
                        case .uploading(let fraction):
                            appState.showUploadBanner("Uploading shot…", progress: fraction)
                        case .processing:
                            break
                        case .finished:
                            break
                        }
                    }
                },
                waitForPublished: false
            )

            TemporaryCaptureStore.removeIfManaged(url)
            let wasVisible = appState.isVisibleShotUpload(uploadToken)
            appState.endShotUpload(url)
            if wasVisible || !appState.hasActiveShotUpload {
                switch outcome {
                case .published(let post):
                    PipelineLogger.camera.info("publishVideo success postId=\(post.id, privacy: .public)")
                    appState.finishUploadBanner("Shot published")
                case .acceptedPending(let post):
                    PipelineLogger.camera.info("publishVideo uploaded postId=\(post.id, privacy: .public)")
                    appState.finishUploadBanner("Video uploaded")
                }
            }
            appState.noteShotPublished()
        } catch {
            if error is ShotUploadCompletionUnconfirmed {
                PipelineLogger.camera.info("publishVideo upload-complete unconfirmed; keeping local copy")
                let wasVisible = appState.isVisibleShotUpload(uploadToken)
                appState.markShotUploadPaused(url)
                appState.suppressAutomaticResume(url)
                for pending in postUseCase.pendingShotFileURLs() {
                    appState.suppressAutomaticResume(pending)
                }
                if wasVisible || !appState.hasActiveShotUpload {
                    appState.showUploadBanner("Upload paused.", canResume: true)
                }
                return
            }
            let cancelled = !appState.isCurrentShotUpload(uploadToken)
                || NetworkErrorClassifier.isCancellation(error)
                || error is CancellationError
            if cancelled {
                let wasVisible = appState.isVisibleShotUpload(uploadToken)
                appState.endShotUpload(url)
                if wasVisible {
                    appState.clearUploadBanner()
                }
                postUseCase.discardPendingShotUpload(fileURL: url)
                return
            }
            PipelineLogger.logError(PipelineLogger.camera, "publishVideo failed", error: error)
            let wasVisible = appState.isVisibleShotUpload(uploadToken)
            appState.markShotUploadPaused(url)
            if wasVisible || !appState.hasActiveShotUpload {
                appState.showUploadBanner("Upload paused.", canResume: true)
            }
        }
    }

    func importFromPhotosPickerItems(_ items: [PhotosPickerItem]) async {
        guard !isImportingFromGallery, !items.isEmpty else { return }
        isImportingFromGallery = true
        isInterrupted = false
        errorMessage = nil

        do {
            var picked: [GalleryPickerPresenter.PickedMedia] = []
            picked.reserveCapacity(min(items.count, 10))

            for item in items.prefix(10) {
                let isVideo = item.supportedContentTypes.contains { type in
                    type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .mpeg4Movie)
                }
                if isVideo {
                    guard let imported = try await item.loadTransferable(type: ImportedMovieFile.self) else {
                        continue
                    }
                    picked.append(.init(url: imported.url, isVideo: true))
                } else if let imported = try await item.loadTransferable(type: ImportedImageFile.self) {
                    picked.append(.init(url: imported.url, isVideo: false))
                }
            }

            guard !picked.isEmpty else {
                errorMessage = "Could not import selected media."
                isImportingFromGallery = false
                return
            }

            await applyImportedGalleryMedia(picked)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isImportingFromGallery = false
        }
    }

    func importFromGalleryFiles(_ items: [GalleryPickerPresenter.PickedMedia]) async {
        guard !isImportingFromGallery, !items.isEmpty else { return }
        isGalleryPickerActive = false
        isInterrupted = false
        isImportingFromGallery = true
        errorMessage = nil
        await applyImportedGalleryMedia(items)
    }

    private func applyImportedGalleryMedia(_ items: [GalleryPickerPresenter.PickedMedia]) async {
        defer { isImportingFromGallery = false }

        if items.count == 1, let only = items.first, !only.isVideo, captureMode.isPhoto {
            phase = .previewPhoto(only.url)
            cameraSession.pauseSession()
            return
        }

        do {
            var clipURLs: [URL] = []
            for item in items {
                if item.isVideo {
                    clipURLs.append(item.url)
                } else {
                    let videoURL = try await StillImageClipRenderer.renderVideo(from: item.url)
                    TemporaryCaptureStore.removeIfManaged(item.url)
                    clipURLs.append(videoURL)
                }
            }
            guard !clipURLs.isEmpty else {
                errorMessage = "Could not import selected media."
                return
            }
            await cameraSession.releaseCaptureForEditor()
            isCameraReady = false
            basicEditingClips = clipURLs
            await goToPublication(clips: clipURLs)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func importFromGalleryFile(url: URL, isVideo: Bool) async {
        await importFromGalleryFiles([.init(url: url, isVideo: isVideo)])
    }

    func importFromGallery(_ item: PhotosPickerItem) async {
        guard !isImportingFromGallery else { return }
        isGalleryPickerActive = false
        isInterrupted = false

        guard await DevicePermissions.requestPhotoLibraryAccess() else {
            errorMessage = "Photo library access is required."
            return
        }

        let isVideo = item.supportedContentTypes.contains { type in
            type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .mpeg4Movie)
        }

        isImportingFromGallery = true
        errorMessage = nil
        defer { isImportingFromGallery = false }

        do {
            if isVideo {
                guard let imported = try await item.loadTransferable(type: ImportedMovieFile.self) else {
                    errorMessage = "Could not import video."
                    return
                }
                await cameraSession.releaseCaptureForEditor()
                isCameraReady = false
                basicEditingClips = [imported.url]
                phase = .publication(videoURL: imported.url)
            } else {
                guard let imported = try await item.loadTransferable(type: ImportedImageFile.self) else {
                    errorMessage = "Could not import photo."
                    return
                }
                phase = .previewPhoto(imported.url)
                cameraSession.pauseSession()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func frameProcessor(_ processor: FrameProcessor, didUpdateDuration duration: TimeInterval, progress: Double) {
        if speedController.speed != .normal {
            recordingDuration = duration
        }
        recordingProgress = progress
    }

    func frameProcessorDidReachDurationLimit(_ processor: FrameProcessor) {
        guard isRecording else { return }
        Task { await stopRecordingAndPreview() }
    }

    func cameraSession(_ session: CameraSession, didChangeInterruption interrupted: Bool) {
        guard !isGalleryPickerActive else {
            if !interrupted { isInterrupted = false }
            return
        }
        isInterrupted = interrupted
    }

    func syncProcessingSettingsPublic() {
        syncProcessingSettings()
    }

    func resumeCamera() {
        cameraSession.resumeIfNeeded()
        isInterrupted = false
    }

    private func configureTimerController() {
        timerController.onTick = { [weak self] remaining in
            self?.phase = .countdown(remaining)
        }
        timerController.onComplete = { [weak self] in
            guard let self else { return }
            self.phase = .capturing
            if self.captureMode.isPhoto {
                Task { await self.capturePhoto() }
            } else {
                self.startRecording()
            }
        }
    }

    func setGreenScreenBackgroundColor(_ color: Color) {
        greenScreenBackgroundSource = .color(hex: hexFromColor(color))
        syncProcessingSettings()
    }

    func importGreenScreenBackground(from item: PhotosPickerItem, isVideo: Bool) async {
        if isVideo {
            guard let imported = try? await item.loadTransferable(type: ImportedMovieFile.self) else { return }
            greenScreenBackgroundSource = .videoURL(imported.url)
        } else {
            guard let imported = try? await item.loadTransferable(type: ImportedImageFile.self) else { return }
            greenScreenBackgroundSource = .image(imported.url)
        }
        syncProcessingSettings()
    }

    private func syncProcessingSettings() {
        let processor = cameraSession.frameProcessor
        processor.beautyProcessor.intensity = beautyIntensity
        processor.faceAwareExposureEnabled = beautyIntensity > 0
        processor.durationLimit = captureMode.durationLimit
        processor.onFaceDetected = { [weak self] point in
            self?.cameraSession.focus(at: point, lock: false)
        }

        let greenScreen = processor.greenScreenProcessor
        if isGreenScreenEnabled {
            let effect = GreenScreenEffect(
                mode: greenScreenMode,
                sensitivity: greenScreenSensitivity,
                feather: greenScreenFeather,
                backgroundSource: greenScreenBackgroundSource
            )
            greenScreen.configure(from: effect)
        } else {
            greenScreen.isEnabled = false
            greenScreen.reset()
        }

        if let filter = availableFilters.first(where: { $0.id == activeFilterID }) {
            processor.filterEngine.activeFilter = filter.id == "original" ? nil : filter
        }
    }

    private func hexFromColor(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private func beginPhotoCapture() {
        if timerDelay == .none {
            Task { await capturePhoto() }
        } else {
            timerController.start(delay: timerDelay)
        }
    }

    private func capturePhoto() async {
        syncProcessingSettings()
        do {
            let url = try await cameraSession.capturePhoto(flashMode: flashController.mode.asCameraFlashMode)
            phase = .previewPhoto(url)
            cameraSession.pauseSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRecording() {
        guard captureMode.isVideo else { return }
        if captureMode.requiresPremium && !isPremium {
            showPaywall = true
            return
        }

        Task {
            syncProcessingSettings()
            CaptureOrientationManager.refreshCachedOrientation()
            cameraSession.frameProcessor.resetRecordingState()
            isRecording = true
            recordingDuration = 0
            recordingProgress = 0
            startRecordingTimer()
            phase = .capturing

            do {
                try await cameraSession.startRecording(flashMode: flashController.mode.asCameraFlashMode)
            } catch {
                isRecording = false
                stopRecordingTimer()
                recordingDuration = 0
                recordingProgress = 0
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopRecordingAndPreview() async {
        guard isRecording else { return }
        isRecording = false
        stopRecordingTimer()
        defer { isInterrupted = false }
        do {
            let url = try await cameraSession.finishRecording(resumeCaptureAfterFinish: false)
            await cameraSession.releaseCaptureForEditor()
            if isEditorReshoot {
                var clips = editorReshootClips
                clips.append(url)
                editorReshootClips = []
                isEditorReshoot = false
                basicEditingClips = clips
                phase = .editing(clips: clips)
            } else {
                await goToPublication(clips: [url])
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .capturing
            cameraSession.resumeIfNeeded()
        }
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        recordingStartedAt = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, let start = self.recordingStartedAt else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
                if let limit = self.captureMode.durationLimit, limit > 0 {
                    self.recordingProgress = min(self.recordingDuration / limit, 1)
                    if self.recordingDuration >= limit {
                        await self.stopRecordingAndPreview()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingTimer = timer
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartedAt = nil
    }
}

private extension FlashMode {
    var asCameraFlashMode: CameraFlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }
}
