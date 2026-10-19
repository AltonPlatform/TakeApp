import AVFoundation

/// Live preview for the gallery tile only.
/// One back camera input and a preview layer. No video, photo, or audio outputs and no Metal.
final class AttachCameraPreviewSession: @unchecked Sendable {
    let captureSession = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.alton.camera.attachPreview")
    private let tokenLock = NSLock()
    private var startToken = 0
    private var isConfigured = false

    func start() async throws {
        let allowed = await DevicePermissions.requestCameraAccess()
        guard allowed else {
            throw CaptureError.permissionDenied(.camera)
        }
        let token = snapshotToken()
        try await run {
            // Tab switches (GIF, location, …) bump the token. Skip startRunning so the
            // session lock is not held while the main thread tears the preview layer down.
            guard self.snapshotToken() == token else { return }
            try self.configureLocked()
            guard self.snapshotToken() == token else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    /// Drops an in-flight `start()` and stops the session if it already ran.
    func invalidateStart() {
        tokenLock.lock()
        startToken += 1
        tokenLock.unlock()
        pause()
    }

    /// Stops capture on the session queue, then clears the preview layer on the main thread.
    /// `AVCaptureVideoPreviewLayer.session = nil` on the main thread waits for an in-flight
    /// `startRunning` / `stopRunning`. That wait is what freezes the chat after the sheet closes.
    func detachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        tokenLock.lock()
        startToken += 1
        tokenLock.unlock()
        let session = captureSession
        queue.async {
            if session.isRunning {
                session.stopRunning()
            }
            DispatchQueue.main.async {
                if layer.session === session {
                    layer.session = nil
                }
            }
        }
    }

    func pause() {
        queue.async {
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    func resume() {
        queue.async {
            guard self.isConfigured, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    /// Stops capture and returns after the session has actually stopped.
    func stopAndWait(timeout: TimeInterval = 1.5) async {
        pause()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let running = await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: self.captureSession.isRunning)
                }
            }
            if !running { return }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    deinit {
        let session = captureSession
        queue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func snapshotToken() -> Int {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return startToken
    }

    private func configureLocked() throws {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Do not retake the shared audio session; this tile only shows a picture.
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        if captureSession.canSetSessionPreset(.vga640x480) {
            captureSession.sessionPreset = .vga640x480
        } else if captureSession.canSetSessionPreset(.medium) {
            captureSession.sessionPreset = .medium
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            throw CaptureError.deviceUnavailable
        }
        captureSession.addInput(input)
        isConfigured = true
    }

    private func run(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
