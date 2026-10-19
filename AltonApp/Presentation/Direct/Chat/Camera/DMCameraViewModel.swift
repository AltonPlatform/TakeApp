import AVFoundation
import Observation
import os
import SwiftUI
import UIKit

@MainActor
@Observable
final class DMCameraViewModel {
    enum Phase: Equatable {
        case capturing
        case countdown(Int)
        case reviewing(ChatCapturedPhoto)
        case markup(ChatCapturedPhoto)
    }

    enum Panel: Equatable {
        case none
        case settings
        case filters
    }

    let cameraSession: CameraSession
    let availableFilters: [any CameraFilter] = BuiltInCameraFilter.allFilters

    var phase: Phase = .capturing
    /// Review tap opens markup with the text field already up.
    var markupStartsWithText = false
    var panel: Panel = .none
    var flashController = FlashController()
    var timerDelay: TimerDelay = .none
    var aspect: DMCameraAspect = .fourByThree
    var activeFilterID = "original"
    var beautyIntensity: Double = 0
    /// Grid and horizon level are toggled together (iOS Camera style).
    var showGrid = false
    var zoomFactor: CGFloat = 1
    /// Live label while pinching (e.g. "1.4×"); nil when idle.
    var zoomDisplayLabel: String?
    var focusIndicator: FocusIndicatorState?
    var levelReading: LevelReading?
    var isCameraReady = false
    var isPreparing = true
    var errorMessage: String?
    var screenFlashVisible = false
    var captured: [ChatCapturedPhoto] = []
    var countdownValue: Int?

    private let ownsSession: Bool
    private let timerController = TimerController()
    private let levelMonitor = LevelMonitor()
    private let signposter = OSSignposter(logger: PipelineLogger.camera)
    private var captureTask: Task<Void, Never>?
    private var focusHideTask: Task<Void, Never>?
    private var isShutDown = false
    private var shutdownTask: Task<Void, Never>?
    private var isCapturingPhoto = false
    private var lastZoomApplied: CGFloat = 1
    private var pinchBaseZoom: CGFloat = 1
    private var pendingZoom: CGFloat?
    private var zoomFlushTask: Task<Void, Never>?
    private var exposureDragStartBias: Float = 0
    private var isAdjustingExposure = false
    private var savedScreenBrightness: CGFloat?
    @ObservationIgnored
    private var thermalObserver: NSObjectProtocol?

    var zoomStops: [ZoomStop] { cameraSession.zoomStops }
    var cameraPosition: AVCaptureDevice.Position { cameraSession.cameraPosition }
    var showsFlashControl: Bool { cameraSession.hasFlash || cameraPosition == .front }
    var minExposureBias: Float { cameraSession.minExposureBias }
    var maxExposureBias: Float { cameraSession.maxExposureBias }

    init(sharedSession: CameraSession? = nil) {
        if let sharedSession {
            cameraSession = sharedSession
            ownsSession = false
        } else {
            cameraSession = CameraSession()
            ownsSession = true
        }
        configureTimer()
        let observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyThermalPolicy() }
        }
        thermalObserver = observer
    }

    func prepare() async {
        let state = signposter.beginInterval("dm.camera.open")
        isPreparing = true
        do {
            // The gallery tile already configured and started this shared session.
            // Configuring again installs system controls and can call startRunning,
            // which blocks the preview layer and makes the close animation stall.
            if ownsSession {
                try await cameraSession.configure(
                    enableMicrophone: false,
                    photoProfile: .direct,
                    installsSystemControls: true
                )
            }
            guard !isShutDown else {
                signposter.endInterval("dm.camera.open", state)
                return
            }
            cameraSession.setAutomaticLifecycleEnabled(true)
            cameraSession.resumeIfNeeded()
            syncDisplayedZoom()
            syncProcessing()
            isCameraReady = true
            isPreparing = false
            if showGrid { startLevel() }
            applyThermalPolicy()
            signposter.endInterval("dm.camera.open", state)
        } catch {
            isPreparing = false
            errorMessage = error.localizedDescription
            signposter.endInterval("dm.camera.open", state)
        }
    }

    func pauseForBackground() {
        levelMonitor.stop()
        cameraSession.pauseSession()
        restoreScreenBrightness()
    }

    func resumeFromBackground() {
        guard !isShutDown else { return }
        cameraSession.resumeIfNeeded()
        if showGrid { startLevel() }
    }

    /// Stops frames before the cover animates away. Safe to call more than once.
    func beginClose() {
        guard !isShutDown else { return }
        isShutDown = true
        captureTask?.cancel()
        captureTask = nil
        focusHideTask?.cancel()
        focusHideTask = nil
        zoomFlushTask?.cancel()
        zoomFlushTask = nil
        levelMonitor.stop()
        restoreScreenBrightness()
        timerController.cancel()
        // The lifecycle monitor otherwise restarts this session when the gallery
        // tile starts its own camera, and both keep running.
        cameraSession.setAutomaticLifecycleEnabled(false)
        cameraSession.pauseSession()
    }

    func shutdown() async {
        beginClose()
        if shutdownTask == nil {
            let session = cameraSession
            let owned = ownsSession
            let keep = Set(captured.map(\.fileURL))
            shutdownTask = Task { @MainActor in
                if let thermalObserver {
                    NotificationCenter.default.removeObserver(thermalObserver)
                    self.thermalObserver = nil
                }
                if owned {
                    await session.shutdown()
                }
                TemporaryCaptureStore.purgeUnreferenced(keeping: keep)
            }
        }
        await shutdownTask?.value
    }

    func cycleFlash() { flashController.cycle() }

    func togglePanel(_ target: Panel) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            panel = panel == target ? .none : target
        }
    }

    func closePanel() {
        guard panel != .none else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            panel = .none
        }
    }

    func cycleTimer() {
        // DM: Off → 3s → 10s (skip 5s to match plan).
        switch timerDelay {
        case .none: timerDelay = .three
        case .three: timerDelay = .ten
        default: timerDelay = .none
        }
    }

    func cycleAspect() {
        let all = DMCameraAspect.allCases
        guard let index = all.firstIndex(of: aspect) else { return }
        aspect = all[(index + 1) % all.count]
    }

    func toggleGrid() {
        showGrid.toggle()
        if showGrid {
            startLevel()
        } else {
            levelMonitor.stop()
            levelReading = nil
        }
    }

    func selectFilter(_ filter: any CameraFilter) {
        activeFilterID = filter.id
        syncProcessing()
    }

    func setBeauty(_ value: Double) {
        beautyIntensity = value
        syncProcessing()
    }

    func flipCamera() async {
        do {
            try await cameraSession.flipCamera(enableMicrophone: false)
            applyPrimaryZoom()
            syncProcessing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectZoom(_ factor: CGFloat) {
        zoomFactor = factor
        lastZoomApplied = factor
        zoomDisplayLabel = nil
        cameraSession.setZoomFactor(factor)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func pinchBegan() {
        pinchBaseZoom = zoomFactor
    }

    func pinchScale(_ scale: CGFloat) {
        let minZ = cameraSession.zoomStops.first?.factor
            ?? cameraSession.primaryZoomFactor
        let maxZ = min(cameraSession.deviceManager.maxZoomFactor, 10)
        let next = min(max(pinchBaseZoom * scale, minZ), maxZ)
        pendingZoom = next
        zoomFactor = next
        zoomDisplayLabel = CameraZoomStopBuilder.displayLabel(
            nativeFactor: next,
            displayMultiplier: cameraSession.displayZoomMultiplier
        )
        if zoomFlushTask == nil {
            zoomFlushTask = Task { @MainActor in
                while let pending = pendingZoom {
                    pendingZoom = nil
                    if abs(pending - lastZoomApplied) > 0.01 {
                        lastZoomApplied = pending
                        cameraSession.setZoomFactor(pending)
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                    if Task.isCancelled { break }
                }
                zoomFlushTask = nil
                // Clear live label shortly after pinch settles.
                try? await Task.sleep(for: .milliseconds(400))
                if pendingZoom == nil, zoomFlushTask == nil {
                    zoomDisplayLabel = nil
                }
            }
        }
    }

    /// - Parameters:
    ///   - viewPoint: Normalized preview coordinates for the focus square.
    ///   - devicePoint: Sensor coordinates from `captureDevicePointConverted`.
    func focus(viewPoint: CGPoint, devicePoint: CGPoint, lock: Bool) {
        cameraSession.resetExposureBias()
        cameraSession.focus(at: devicePoint, lock: lock)
        focusIndicator = FocusIndicatorState(
            point: viewPoint,
            isLocked: lock,
            exposureBias: 0,
            isAdjustingExposure: false
        )
        scheduleFocusHide(locked: lock)
    }

    func beginExposureAdjust() {
        isAdjustingExposure = true
        focusHideTask?.cancel()
        exposureDragStartBias = focusIndicator?.exposureBias ?? cameraSession.currentExposureBias
        if focusIndicator == nil {
            focusIndicator = FocusIndicatorState(
                point: CGPoint(x: 0.5, y: 0.5),
                isLocked: false,
                exposureBias: exposureDragStartBias,
                isAdjustingExposure: true
            )
        } else if var indicator = focusIndicator {
            indicator.isAdjustingExposure = true
            focusIndicator = indicator
        }
    }

    func adjustExposure(translationY: CGFloat) {
        // Smaller divisor → more sensitive (≈70 pt of swipe ≈ 1 EV).
        let delta = Float(-translationY / 70)
        let bias = min(
            max(exposureDragStartBias + delta, minExposureBias),
            maxExposureBias
        )
        cameraSession.setExposureBias(bias)
        if var indicator = focusIndicator {
            indicator.exposureBias = bias
            indicator.isAdjustingExposure = true
            focusIndicator = indicator
        }
    }

    func endExposureAdjust() {
        isAdjustingExposure = false
        if var indicator = focusIndicator {
            indicator.isAdjustingExposure = false
            focusIndicator = indicator
            scheduleFocusHide(locked: indicator.isLocked)
        }
    }

    func shutterTapped() {
        guard case .capturing = phase, isCameraReady, !isCapturingPhoto, !isShutDown else { return }
        closePanel()
        if timerDelay == .none {
            captureTask?.cancel()
            captureTask = Task { await captureSingle() }
        } else {
            timerController.start(delay: timerDelay)
        }
    }

    /// Volume / Camera Control. One press, one photo.
    func hardwareCaptureBegan() {}

    func hardwareCaptureEnded(cancelled: Bool) {
        guard !cancelled else { return }
        shutterTapped()
    }

    func discardReview() {
        if case .reviewing(let photo) = phase {
            TemporaryCaptureStore.removeIfManaged(photo.fileURL)
            captured.removeAll { $0.id == photo.id }
        }
        phase = .capturing
        cameraSession.resumeIfNeeded()
    }

    func openMarkup(editingText: Bool = false) {
        guard case .reviewing(let photo) = phase else { return }
        markupStartsWithText = editingText
        phase = .markup(photo)
    }

    func finishMarkup(_ photo: ChatCapturedPhoto) {
        if let index = captured.firstIndex(where: { $0.id == photo.id }) {
            let old = captured[index]
            if old.fileURL != photo.fileURL {
                TemporaryCaptureStore.removeIfManaged(old.fileURL)
            }
            captured[index] = photo
        }
        markupStartsWithText = false
        phase = .reviewing(photo)
    }

    func cancelMarkup() {
        markupStartsWithText = false
        if case .markup(let photo) = phase {
            phase = .reviewing(photo)
        }
    }

    func clearCapturedFiles() {
        for photo in captured {
            TemporaryCaptureStore.removeIfManaged(photo.fileURL)
        }
        captured.removeAll()
    }

    // MARK: - Private

    private func configureTimer() {
        timerController.onTick = { [weak self] value in
            self?.countdownValue = value
            self?.phase = .countdown(value)
        }
        timerController.onComplete = { [weak self] in
            guard let self, !self.isShutDown else { return }
            self.countdownValue = nil
            self.phase = .capturing
            self.captureTask?.cancel()
            self.captureTask = Task { await self.captureSingle() }
        }
    }

    private func startLevel() {
        levelMonitor.start { [weak self] reading in
            Task { @MainActor in
                guard let self else { return }
                let wasLevel = self.levelReading?.isLevel == true
                self.levelReading = reading
                if reading.isLevel, !wasLevel {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                }
            }
        }
    }

    private func syncProcessing() {
        let processor = cameraSession.frameProcessor
        processor.beautyProcessor.intensity = beautyIntensity
        processor.greenScreenProcessor.isEnabled = false
        if let filter = availableFilters.first(where: { $0.id == activeFilterID }) {
            processor.filterEngine.activeFilter = filter.id == "original" ? nil : filter
        }
        applyThermalPolicy()
    }

    private func applyThermalPolicy() {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            cameraSession.frameProcessor.processingQuality = .reduced
            if beautyIntensity > 0 {
                beautyIntensity = 0
                cameraSession.frameProcessor.beautyProcessor.intensity = 0
            }
        default:
            cameraSession.frameProcessor.processingQuality = .full
        }
    }

    func syncDisplayedZoom() {
        let factor = cameraSession.zoomFactor
        zoomFactor = factor
        lastZoomApplied = factor
        pinchBaseZoom = factor
        zoomDisplayLabel = nil
    }

    private func applyPrimaryZoom() {
        let factor = cameraSession.primaryZoomFactor
        zoomFactor = factor
        lastZoomApplied = factor
        pinchBaseZoom = factor
        zoomDisplayLabel = nil
        cameraSession.setZoomFactor(factor, rampRate: 0)
    }

    private func scheduleFocusHide(locked: Bool) {
        focusHideTask?.cancel()
        guard !locked else { return }
        focusHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !isAdjustingExposure else { return }
            if focusIndicator?.isLocked != true {
                focusIndicator = nil
            }
        }
    }

    private func captureSingle() async {
        let state = signposter.beginInterval("dm.camera.shutter")
        isCapturingPhoto = true
        defer { isCapturingPhoto = false }
        do {
            await prepareFrontScreenFlashIfNeeded()
            let url = try await cameraSession.capturePhoto(
                flashMode: flashController.mode.asCameraFlashMode,
                qualityPrioritization: .quality
            )
            restoreScreenBrightness()
            // Stop video/Metal before still finish. PhotoFinisher itself is CPU-only,
            // but FrameProcessor still holds a Metal CIContext while the session runs.
            cameraSession.pauseSession()
            await cameraSession.waitUntilSessionStopped()
            guard !Task.isCancelled, !isShutDown else {
                TemporaryCaptureStore.removeIfManaged(url)
                signposter.endInterval("dm.camera.shutter", state)
                return
            }
            let photo = try await finishCapture(url: url)
            guard !Task.isCancelled, !isShutDown else {
                TemporaryCaptureStore.removeIfManaged(photo.fileURL)
                signposter.endInterval("dm.camera.shutter", state)
                return
            }
            captured.append(photo)
            phase = .reviewing(photo)
            signposter.endInterval("dm.camera.shutter", state)
        } catch {
            restoreScreenBrightness()
            if !Task.isCancelled, !isShutDown {
                errorMessage = error.localizedDescription
            }
            signposter.endInterval("dm.camera.shutter", state)
        }
    }

    private func finishCapture(url: URL) async throws -> ChatCapturedPhoto {
        let state = signposter.beginInterval("dm.camera.finish")
        let options = PhotoFinisher.Options(
            filterID: activeFilterID,
            beautyIntensity: beautyIntensity,
            aspect: aspect,
            mirror: cameraPosition == .front,
            maxLongEdge: DMImageRules.maxLongEdge,
            previewLongEdge: 240
        )
        let result = try await Task.detached(priority: .userInitiated) {
            try PhotoFinisher.finish(sourceURL: url, options: options)
        }.value
        TemporaryCaptureStore.removeIfManaged(url)
        signposter.endInterval("dm.camera.finish", state)
        return ChatCapturedPhoto(
            id: ChatCaptureID.make(),
            fileURL: result.fileURL,
            preview: result.preview
        )
    }

    private func prepareFrontScreenFlashIfNeeded() async {
        guard cameraPosition == .front, flashController.mode != .off else { return }
        savedScreenBrightness = UIScreen.main.brightness
        screenFlashVisible = true
        UIScreen.main.brightness = 1
        try? await Task.sleep(for: .milliseconds(80))
    }

    private func restoreScreenBrightness() {
        screenFlashVisible = false
        if let saved = savedScreenBrightness {
            UIScreen.main.brightness = saved
            savedScreenBrightness = nil
        }
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
