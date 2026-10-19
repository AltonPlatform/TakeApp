import AVFoundation
import UIKit

enum CameraPhotoProfile: Sendable {
    case shot
    case direct
}

final class PhotoCaptureProcessor: NSObject {
    private let photoOutput = AVCapturePhotoOutput()
    private let waiterLock = NSLock()
    /// One waiter per `AVCapturePhotoSettings.uniqueID`.
    private var waiters: [Int64: CheckedContinuation<URL, Error>] = [:]
    private(set) var profile: CameraPhotoProfile = .shot

    func configure(session: AVCaptureSession, profile: CameraPhotoProfile = .shot) throws {
        self.profile = profile
        guard !session.outputs.contains(where: { $0 === photoOutput }) else {
            applyProfileLocked()
            return
        }
        guard session.canAddOutput(photoOutput) else {
            throw CaptureError.configurationFailed
        }
        session.addOutput(photoOutput)
        applyProfileLocked()
    }

    func applyProfile(_ profile: CameraPhotoProfile) {
        self.profile = profile
        applyProfileLocked()
    }

    private func applyProfileLocked() {
        switch profile {
        case .shot:
            photoOutput.maxPhotoQualityPrioritization = .quality
        case .direct:
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }
    }

    /// Applies the smallest supported max-photo size with long edge ≥ 2048 when available.
    func applyDirectPhotoDimensions(from device: AVCaptureDevice?) {
        guard profile == .direct else { return }
        if #available(iOS 16.0, *) {
            let formats = device?.activeFormat.supportedMaxPhotoDimensions ?? []
            if let pick = PhotoFinisher.preferredPhotoDimensions(from: formats) {
                photoOutput.maxPhotoDimensions = pick
            }
        }
    }

    func capture(
        flashMode: CameraFlashMode,
        mirrored: Bool,
        qualityPrioritization: AVCapturePhotoOutput.QualityPrioritization? = nil
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(flashMode.avFlashMode) {
                settings.flashMode = flashMode.avFlashMode
            }
            let prioritization = qualityPrioritization
                ?? (profile == .direct ? .speed : .quality)
            if photoOutput.maxPhotoQualityPrioritization.rawValue >= prioritization.rawValue {
                settings.photoQualityPrioritization = prioritization
            }

            if let connection = photoOutput.connection(with: .video) {
                connection.isVideoMirrored = mirrored
            }

            waiterLock.lock()
            waiters[settings.uniqueID] = continuation
            waiterLock.unlock()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func takeWaiter(for uniqueID: Int64) -> CheckedContinuation<URL, Error>? {
        waiterLock.lock()
        let waiter = waiters.removeValue(forKey: uniqueID)
        waiterLock.unlock()
        return waiter
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let waiter = takeWaiter(for: photo.resolvedSettings.uniqueID)
        if let error {
            waiter?.resume(throwing: error)
            return
        }

        let url = TemporaryCaptureStore.photoURL()
        do {
            guard let data = photo.fileDataRepresentation() else {
                throw CaptureError.photoCaptureFailed
            }
            try data.write(to: url)
            waiter?.resume(returning: url)
        } catch {
            waiter?.resume(throwing: error)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        // Processing already resumed a successful capture. Only a leftover waiter plus an error
        // means the file never arrived.
        guard let error else { return }
        takeWaiter(for: resolvedSettings.uniqueID)?.resume(throwing: error)
    }
}
