import AVFoundation

struct ZoomStop: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    /// Native `AVCaptureDevice.videoZoomFactor`.
    let factor: CGFloat
}

enum CameraZoomStopBuilder {
    /// Builds UI zoom stops using Apple's display multiplier (ultra-wide = 0.5× on Dual Wide).
    static func stops(
        minZoom: CGFloat,
        maxZoom: CGFloat,
        switchOvers: [CGFloat],
        displayMultiplier: CGFloat,
        isBackCamera: Bool
    ) -> [ZoomStop] {
        guard isBackCamera else {
            return [ZoomStop(id: "1", label: "1×", factor: max(1.0, minZoom))]
        }

        let multiplier = max(displayMultiplier, 0.01)
        var candidates: [(display: CGFloat, factor: CGFloat)] = []

        // Ultra-wide when virtual device starts below 1.0 native.
        if minZoom * multiplier < 0.85 {
            candidates.append((display: 0.5, factor: minZoom))
        }

        // Primary "1×" lens.
        let oneXFactor = 1.0 / multiplier
        if oneXFactor >= minZoom - 0.05, oneXFactor <= maxZoom + 0.05 {
            candidates.append((display: 1.0, factor: max(minZoom, min(oneXFactor, maxZoom))))
        } else {
            candidates.append((display: minZoom * multiplier, factor: minZoom))
        }

        for native in switchOvers where native > minZoom + 0.05 {
            let display = native * multiplier
            guard display > 0.9 else { continue }
            candidates.append((display: display, factor: native))
        }

        // Digital 2× when no optical tele stop near 2× display.
        let hasNearTwo = candidates.contains { abs($0.display - 2.0) < 0.25 }
        if !hasNearTwo {
            let twoFactor = 2.0 / multiplier
            if twoFactor <= maxZoom + 0.05 {
                candidates.append((display: 2.0, factor: min(twoFactor, maxZoom)))
            }
        }

        // Optional 3× when the device supports it (triple / digital).
        let hasNearThree = candidates.contains { abs($0.display - 3.0) < 0.35 }
        if !hasNearThree {
            let threeFactor = 3.0 / multiplier
            if threeFactor <= maxZoom + 0.05 {
                candidates.append((display: 3.0, factor: min(threeFactor, maxZoom)))
            }
        }

        var unique: [ZoomStop] = []
        for item in candidates.sorted(by: { $0.factor < $1.factor }) {
            if unique.contains(where: { abs($0.factor - item.factor) < 0.05 }) { continue }
            let label: String
            if abs(item.display - item.display.rounded()) < 0.05 {
                if abs(item.display - 0.5) < 0.05 {
                    label = "0.5×"
                } else {
                    label = "\(Int(item.display.rounded()))×"
                }
            } else {
                label = String(format: "%.1f×", item.display)
            }
            unique.append(
                ZoomStop(
                    id: String(format: "%.2f", item.factor),
                    label: label,
                    factor: item.factor
                )
            )
        }
        return unique
    }

    static func displayLabel(nativeFactor: CGFloat, displayMultiplier: CGFloat) -> String {
        let display = nativeFactor * max(displayMultiplier, 0.01)
        if abs(display - 0.5) < 0.05 { return "0.5×" }
        if abs(display - display.rounded()) < 0.05 {
            return "\(Int(display.rounded()))×"
        }
        return String(format: "%.1f×", display)
    }
}

final class CaptureDeviceManager {
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var currentDevice: AVCaptureDevice?
    private var exposureLockWorkItem: DispatchWorkItem?

    var minZoomFactor: CGFloat {
        currentDevice?.minAvailableVideoZoomFactor ?? 1.0
    }

    var maxZoomFactor: CGFloat {
        guard let device = currentDevice else { return 5.0 }
        return min(device.maxAvailableVideoZoomFactor, 10.0)
    }

    var zoomFactor: CGFloat {
        currentDevice?.videoZoomFactor ?? 1.0
    }

    /// Converts native zoom to the value shown in the system Camera UI.
    var displayZoomMultiplier: CGFloat {
        guard let device = currentDevice else { return 1 }
        if #available(iOS 18.0, *) {
            let multiplier = device.displayVideoZoomFactorMultiplier
            return multiplier > 0 ? CGFloat(multiplier) : 1
        }
        // Dual Wide / Triple: native 1.0 is ultra-wide → display 0.5×.
        let minZoom = device.minAvailableVideoZoomFactor
        if position == .back, minZoom < 0.9 {
            return 0.5
        }
        return 1
    }

    /// Native factor for the primary "1×" display stop.
    var primaryZoomFactor: CGFloat {
        let factor = 1.0 / displayZoomMultiplier
        return min(max(factor, minZoomFactor), maxZoomFactor)
    }

    var hasFlash: Bool {
        currentDevice?.hasFlash == true
    }

    var hasTorch: Bool {
        currentDevice?.hasTorch == true
    }

    var zoomStops: [ZoomStop] {
        guard let device = currentDevice else {
            return [ZoomStop(id: "1", label: "1×", factor: 1.0)]
        }
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        return CameraZoomStopBuilder.stops(
            minZoom: device.minAvailableVideoZoomFactor,
            maxZoom: maxZoomFactor,
            switchOvers: switchOvers,
            displayMultiplier: displayZoomMultiplier,
            isBackCamera: position == .back
        )
    }

    func selectDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        cancelScheduledExposureLock()
        self.position = position
        let device: AVCaptureDevice?

        if position == .back {
            device = Self.discoverBackCamera()
        } else {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        currentDevice = device
        restoreContinuousExposureAndWhiteBalance()
        return device
    }

    func scheduleAutoExposureAndWhiteBalanceLock(after delay: TimeInterval = 1.0) {
        cancelScheduledExposureLock()
        let work = DispatchWorkItem { [weak self] in
            try? self?.lockExposureAndWhiteBalance()
        }
        exposureLockWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelScheduledExposureLock() {
        exposureLockWorkItem?.cancel()
        exposureLockWorkItem = nil
    }

    private func restoreContinuousExposureAndWhiteBalance() {
        guard let device = currentDevice else { return }
        try? device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }

    private func lockExposureAndWhiteBalance() throws {
        guard let device = currentDevice else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isExposureModeSupported(.locked) {
            device.exposureMode = .locked
        }
        if device.isWhiteBalanceModeSupported(.locked) {
            device.whiteBalanceMode = .locked
        }
    }

    func setZoomFactor(_ factor: CGFloat, rampRate: Float = 8.0) throws {
        guard let device = currentDevice else { return }
        let clamped = min(max(factor, device.minAvailableVideoZoomFactor), min(device.maxAvailableVideoZoomFactor, 10.0))

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if rampRate <= 0 {
            device.videoZoomFactor = clamped
        } else {
            device.ramp(toVideoZoomFactor: clamped, withRate: rampRate)
        }
    }

    func setFocus(at normalizedPoint: CGPoint, lock: Bool) throws {
        guard let device = currentDevice else { return }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = normalizedPoint
            device.focusMode = lock ? .locked : .continuousAutoFocus
        }

        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = normalizedPoint
            device.exposureMode = lock ? .locked : .continuousAutoExposure
        }
    }

    var minExposureBias: Float {
        currentDevice?.minExposureTargetBias ?? -2
    }

    var maxExposureBias: Float {
        currentDevice?.maxExposureTargetBias ?? 2
    }

    var currentExposureBias: Float {
        currentDevice?.exposureTargetBias ?? 0
    }

    func setExposureBias(_ bias: Float) throws {
        guard let device = currentDevice else { return }
        let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.exposureMode == .locked {
            // One-shot re-meter so EV changes apply while AE/AF lock is active.
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
        } else if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        device.setExposureTargetBias(clamped, completionHandler: nil)
    }

    func resetExposureBias() throws {
        try setExposureBias(0)
    }

    func setTorchEnabled(_ enabled: Bool) throws {
        guard let device = currentDevice, device.hasTorch else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.torchMode = enabled ? .on : .off
    }

    func setFrameRate(_ frameRate: Int32, session: AVCaptureSession) throws {
        guard let device = currentDevice else { return }

        let clampedRate = Self.clampFrameRate(frameRate, for: device)
        let duration = CMTime(value: 1, timescale: clampedRate)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    func maxSupportedFrameRate() -> Int32 {
        guard let device = currentDevice else { return 30 }
        let maxRate = device.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        return Int32(maxRate.rounded(.down))
    }

    private static func clampFrameRate(_ frameRate: Int32, for device: AVCaptureDevice) -> Int32 {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard !ranges.isEmpty else { return max(frameRate, 1) }

        let minAllowed = Int32(ranges.map(\.minFrameRate).min()!.rounded(.up))
        let maxAllowed = Int32(ranges.map(\.maxFrameRate).max()!.rounded(.down))
        return min(max(frameRate, minAllowed), maxAllowed)
    }

    private static func discoverBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )
        return session.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}
