import Observation
import Foundation

struct UploadBannerState: Equatable {
    var message: String
    /// `nil` = indeterminate spinner; `0...1` = determinate bar.
    var progress: Double?
    /// Failed shot upload that continues when the banner is tapped or the app returns.
    var canResume: Bool = false
}

@MainActor
@Observable
final class AppState {
    var isPremium = false

    /// Ephemeral banner shown above the tab bar (auto-clears).
    private(set) var toastMessage: String?
    /// Sticky upload / processing banner (shot publish, etc.).
    private(set) var uploadBanner: UploadBannerState?
    /// Bumped when a background take publish finishes successfully — feed should refresh.
    private(set) var takePublishGeneration = 0
    /// Bumped when a background shot publish finishes (or is accepted pending).
    private(set) var shotPublishGeneration = 0

    private var toastClearTask: Task<Void, Never>?
    private var uploadBannerClearTask: Task<Void, Never>?
    private var shotUploadsInFlight: Set<String> = []
    private var shotUploadTokens: [String: Int] = [:]
    private var shotUploadTokenSeed = 0
    private var trackedShotUploadToken: Int?
    private var shotUploadTasks: [String: Task<Void, Never>] = [:]
    private var explicitResumePaths: Set<String> = []
    private(set) var resumableShotURL: URL?

    func showToast(_ message: String, duration: TimeInterval = 3.0) {
        toastClearTask?.cancel()
        toastMessage = message
        toastClearTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    func clearToast() {
        toastClearTask?.cancel()
        toastClearTask = nil
        toastMessage = nil
    }

    func showUploadBanner(_ message: String, progress: Double? = nil, canResume: Bool = false) {
        uploadBannerClearTask?.cancel()
        uploadBannerClearTask = nil
        uploadBanner = UploadBannerState(message: message, progress: progress, canResume: canResume)
    }

    /// Final status that auto-dismisses after `duration`.
    func finishUploadBanner(_ message: String, duration: TimeInterval = 3.0) {
        uploadBannerClearTask?.cancel()
        uploadBanner = UploadBannerState(message: message, progress: nil, canResume: false)
        uploadBannerClearTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            if uploadBanner?.message == message {
                uploadBanner = nil
            }
        }
    }

    func clearUploadBanner() {
        uploadBannerClearTask?.cancel()
        uploadBannerClearTask = nil
        uploadBanner = nil
    }

    func noteTakePublished() {
        takePublishGeneration &+= 1
    }

    func noteShotPublished() {
        shotPublishGeneration &+= 1
    }

    func beginShotUpload(_ fileURL: URL) -> Int {
        shotUploadTokenSeed += 1
        let token = shotUploadTokenSeed
        shotUploadTokens[fileURL.path] = token
        trackedShotUploadToken = token
        shotUploadsInFlight.insert(fileURL.path)
        explicitResumePaths.remove(fileURL.path)
        if resumableShotURL == fileURL {
            resumableShotURL = nil
        }
        return token
    }

    func endShotUpload(_ fileURL: URL) {
        shotUploadsInFlight.remove(fileURL.path)
        shotUploadTasks[fileURL.path] = nil
        explicitResumePaths.remove(fileURL.path)
        if let token = shotUploadTokens.removeValue(forKey: fileURL.path), token == trackedShotUploadToken {
            trackedShotUploadToken = newestRemainingShotUploadToken()
        }
        if resumableShotURL == fileURL {
            resumableShotURL = nil
        }
    }

    func markShotUploadPaused(_ fileURL: URL) {
        shotUploadsInFlight.remove(fileURL.path)
        shotUploadTasks[fileURL.path] = nil
        if let token = shotUploadTokens.removeValue(forKey: fileURL.path), token == trackedShotUploadToken {
            trackedShotUploadToken = newestRemainingShotUploadToken()
        }
        resumableShotURL = fileURL
    }

    func trackShotUpload(_ fileURL: URL, _ task: Task<Void, Never>) {
        shotUploadTasks[fileURL.path] = task
    }

    var trackedShotUploadCount: Int { shotUploadTasks.count }

    /// A cancelled `upload-complete` stays on disk until the user taps Resume.
    /// Returning to the app must not send that request again.
    func suppressAutomaticResume(_ fileURL: URL) {
        explicitResumePaths.insert(fileURL.path)
    }

    func allowsAutomaticResume(_ fileURL: URL) -> Bool {
        !explicitResumePaths.contains(fileURL.path)
    }

    /// Cancels the visible attempt only. Other in-flight shots keep their tasks.
    /// The in-flight set stays until that task exits, so resume cannot start a copy
    /// that the cancelled task would then delete.
    func cancelTrackedShotUpload() {
        let path = shotUploadTokens.first { $0.value == trackedShotUploadToken }?.key
        if let tracked = trackedShotUploadToken {
            shotUploadTokens = shotUploadTokens.filter { $0.value != tracked }
        }
        if let path {
            shotUploadTasks[path]?.cancel()
            shotUploadTasks[path] = nil
        }
        trackedShotUploadToken = newestRemainingShotUploadToken()
        resumableShotURL = nil
    }

    func isCurrentShotUpload(_ token: Int) -> Bool {
        shotUploadTokens.values.contains(token)
    }

    /// Progress and banners follow the attempt the user most recently started or cancelled back to.
    func isVisibleShotUpload(_ token: Int) -> Bool {
        token == trackedShotUploadToken
    }

    private func newestRemainingShotUploadToken() -> Int? {
        shotUploadTokens.values.max()
    }

    var hasActiveShotUpload: Bool {
        !shotUploadsInFlight.isEmpty
    }

    func isShotUploadInFlight(_ fileURL: URL) -> Bool {
        shotUploadsInFlight.contains(fileURL.path)
    }
}
