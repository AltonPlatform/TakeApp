import Foundation
import Observation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import CryptoKit

@MainActor
@Observable
final class CreatePostViewModel {
    static let characterLimit = PostUseCase.characterLimit
    static let maxAttachments = 10
    /// Max edge for uploaded (non-GIF) images — keeps memory and upload size bounded.
    nonisolated static let uploadMaxPixelSize: CGFloat = 2048
    static let maxGIFBytes = 15 * 1024 * 1024
    static let maxEncodedImageBytes = 8 * 1024 * 1024

    var content = "" {
        didSet {
            guard content != oldValue else { return }
            cachedPlainTextLength = PostContentMetrics.plainTextLength(of: content)
            scheduleAutosave()
        }
    }
    var attachments: [PostAttachment] = [] {
        didSet {
            guard attachments != oldValue else { return }
            scheduleAutosave()
        }
    }
    var isSubmitting = false
    var successMessage: String?
    var errorMessage: String?
    var editingPostID: String?

    private let postUseCase: PostUseCase
    private let appState: AppState
    private let draftStore: DraftStore
    /// Stable IDs of PhotosPickerItems already loaded (for merge dedup).
    private var loadedPickerItemIDs: Set<String> = []
    private(set) var attachmentLoadGeneration = 0
    private var cachedPlainTextLength = 0
    private var currentDraftID: UUID?
    private var autosaveTask: Task<Void, Never>?
    private var suppressAutosave = false

    var isEditing: Bool { editingPostID != nil }
    var hasDraftContent: Bool {
        !PostContentMetrics.isPlainTextEmpty(content) || !attachments.isEmpty
    }

    init(
        postUseCase: PostUseCase,
        appState: AppState,
        draftStore: DraftStore,
        editingPost: Post? = nil
    ) {
        self.postUseCase = postUseCase
        self.appState = appState
        self.draftStore = draftStore
        if let editingPost {
            beginEditing(post: editingPost)
        }
    }

    var remainingCharacters: Int {
        Self.characterLimit - cachedPlainTextLength
    }

    var canSubmitContent: Bool {
        remainingCharacters >= 0 && hasDraftContent
    }

    func beginEditing(post: Post) {
        suppressAutosave = true
        defer { suppressAutosave = false }
        editingPostID = post.id
        currentDraftID = nil
        content = post.content ?? ""
        attachments = []
        loadedPickerItemIDs = []
        attachmentLoadGeneration &+= 1
        errorMessage = nil
        successMessage = nil
    }

    /// Restores a local composer draft into the editor.
    func beginDraft(id: UUID) {
        suppressAutosave = true
        defer { suppressAutosave = false }
        guard let payload = try? draftStore.load(id: id) else {
            errorMessage = "Couldn't open draft."
            return
        }
        editingPostID = nil
        currentDraftID = payload.id
        content = payload.content
        attachments = payload.attachments.map {
            PostAttachment(
                id: UUID(),
                data: $0.data,
                contentType: $0.contentType,
                filename: $0.filename,
                pickerItemID: nil
            )
        }
        loadedPickerItemIDs = []
        attachmentLoadGeneration &+= 1
        errorMessage = nil
        successMessage = nil
    }

    /// Appends newly selected picker items without wiping existing attachments.
    /// Returns the generation token for this load so the UI can clear the picker safely.
    @discardableResult
    func addAttachments(from items: [PhotosPickerItem]) async -> Int {
        guard !items.isEmpty else { return attachmentLoadGeneration }

        attachmentLoadGeneration &+= 1
        let generation = attachmentLoadGeneration

        guard await DevicePermissions.requestPhotoLibraryAccess() else {
            guard generation == attachmentLoadGeneration else { return generation }
            errorMessage = "Photo library access is required to attach media."
            return generation
        }
        guard generation == attachmentLoadGeneration else { return generation }

        let remaining = Self.maxAttachments - attachments.count
        guard remaining > 0 else {
            errorMessage = "You can attach up to \(Self.maxAttachments) photos."
            return generation
        }

        let candidates = items.filter { item in
            guard let id = stablePickerItemID(item) else {
                return true
            }
            return !loadedPickerItemIDs.contains(id)
        }
        .prefix(remaining)

        var loaded: [PostAttachment] = []
        var acceptedIDs: [String] = []
        var hadFailures = false

        for item in candidates {
            guard generation == attachmentLoadGeneration else { return generation }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                hadFailures = true
                continue
            }
            guard generation == attachmentLoadGeneration else { return generation }

            let rawType = contentType(for: item, data: data)
            guard let prepared = await prepareAttachmentData(data, contentType: rawType) else {
                hadFailures = true
                continue
            }
            guard generation == attachmentLoadGeneration else { return generation }

            let filename = "attachment.\(fileExtension(for: prepared.contentType))"
            let itemID: String
            if let stable = stablePickerItemID(item) {
                itemID = stable
            } else {
                itemID = await Task.detached(priority: .utility) {
                    Self.contentFingerprint(data)
                }.value
            }
            if loadedPickerItemIDs.contains(itemID) || acceptedIDs.contains(itemID) {
                continue
            }

            loaded.append(
                PostAttachment(
                    id: UUID(),
                    data: prepared.data,
                    contentType: prepared.contentType,
                    filename: filename,
                    pickerItemID: itemID
                )
            )
            acceptedIDs.append(itemID)
        }

        guard generation == attachmentLoadGeneration else { return generation }

        if !loaded.isEmpty {
            attachments.append(contentsOf: loaded)
            loadedPickerItemIDs.formUnion(acceptedIDs)
        } else if hadFailures, errorMessage == nil {
            errorMessage = "Couldn't load one or more photos."
        }

        return generation
    }

    func removeAttachment(_ attachment: PostAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        if let pickerItemID = attachment.pickerItemID {
            loadedPickerItemIDs.remove(pickerItemID)
        }
    }

    /// Clipboard paste → same attachment strip as PhotosPicker (not inline in markdown).
    func appendPastedImages(_ images: [UIImage]) async {
        for image in images {
            guard attachments.count < Self.maxAttachments else {
                errorMessage = "You can attach up to \(Self.maxAttachments) photos."
                return
            }
            _ = await addAttachment(from: image, pickerItemID: nil)
        }
    }

    /// Appends a cropped (or otherwise prepared) still image from the photo editor.
    @discardableResult
    func addAttachment(from image: UIImage, pickerItemID: String?) async -> Bool {
        guard attachments.count < Self.maxAttachments else {
            errorMessage = "You can attach up to \(Self.maxAttachments) photos."
            return false
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.92) else {
            errorMessage = "Couldn't process image."
            return false
        }
        guard let prepared = await prepareAttachmentData(jpeg, contentType: "image/jpeg") else {
            return false
        }

        let itemID = pickerItemID ?? UUID().uuidString
        if let pickerItemID, loadedPickerItemIDs.contains(pickerItemID) {
            return false
        }

        attachments.append(
            PostAttachment(
                id: UUID(),
                data: prepared.data,
                contentType: prepared.contentType,
                filename: "attachment.\(fileExtension(for: prepared.contentType))",
                pickerItemID: itemID
            )
        )
        loadedPickerItemIDs.insert(itemID)
        return true
    }

    /// Replaces an existing attachment with a re-cropped image.
    func replaceAttachment(id: UUID, with image: UIImage) async {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.92) else {
            errorMessage = "Couldn't process image."
            return
        }
        guard let prepared = await prepareAttachmentData(jpeg, contentType: "image/jpeg") else { return }

        let old = attachments[index]
        attachments[index] = PostAttachment(
            id: old.id,
            data: prepared.data,
            contentType: prepared.contentType,
            filename: "attachment.\(fileExtension(for: prepared.contentType))",
            pickerItemID: old.pickerItemID
        )
    }

    /// Flush autosave (or delete empty draft), then clear in-memory composer state.
    func cancelComposer() {
        autosaveTask?.cancel()
        autosaveTask = nil
        if hasDraftContent {
            flushAutosaveNow()
        } else if let currentDraftID {
            try? draftStore.delete(id: currentDraftID)
        }
        clearInMemoryComposer()
    }

    /// Clears draft content and attachments when starting a fresh composer session.
    func resetComposer() {
        autosaveTask?.cancel()
        autosaveTask = nil
        clearInMemoryComposer()
    }

    func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true

        guard canSubmitContent else {
            isSubmitting = false
            if remainingCharacters < 0 {
                errorMessage = "Post is too long."
            }
            return
        }

        // Edit stays synchronous — payload is small.
        if let editingPostID {
            errorMessage = nil
            successMessage = nil
            defer { isSubmitting = false }
            do {
                _ = try await postUseCase.updateTake(postID: editingPostID, content: content)
                successMessage = "Post updated."
                appState.noteTakePublished()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            return
        }

        let payloadContent = content
        let payloadAttachments = attachments
        let hasMedia = !payloadAttachments.isEmpty
        let draftIDToDelete = currentDraftID

        autosaveTask?.cancel()
        autosaveTask = nil

        // Instant UX: clear composer and dismiss; finish upload/publish in the background.
        suppressAutosave = true
        content = ""
        attachments = []
        loadedPickerItemIDs = []
        currentDraftID = nil
        suppressAutosave = false
        errorMessage = nil
        successMessage = hasMedia
            ? "Your post is being processed."
            : "Publishing your post…"

        appState.showToast(
            hasMedia
                ? "Your post is being processed."
                : "Publishing your post…"
        )

        // Unlock after local state is cleared so a second tap cannot duplicate the post.
        isSubmitting = false

        let useCase = postUseCase
        let state = appState
        let store = draftStore
        Task {
            do {
                _ = try await useCase.createAndPublishTake(
                    content: payloadContent,
                    attachments: payloadAttachments
                )
                if let draftIDToDelete {
                    try? store.delete(id: draftIDToDelete)
                }
                state.showToast("Post published.")
                state.noteTakePublished()
            } catch {
                // Keep the draft so the user can retry.
                if let draftIDToDelete {
                    _ = try? store.upsert(
                        id: draftIDToDelete,
                        content: payloadContent,
                        attachments: payloadAttachments.map {
                            ComposerDraftAttachmentPayload(
                                data: $0.data,
                                contentType: $0.contentType,
                                filename: $0.filename
                            )
                        }
                    )
                } else {
                    _ = try? store.upsert(
                        id: nil,
                        content: payloadContent,
                        attachments: payloadAttachments.map {
                            ComposerDraftAttachmentPayload(
                                data: $0.data,
                                contentType: $0.contentType,
                                filename: $0.filename
                            )
                        }
                    )
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                state.showToast(message)
            }
        }
    }

    func makeCameraViewModel() -> CameraViewModel {
        CameraViewModel(postUseCase: postUseCase, appState: appState)
    }

    // MARK: - Autosave

    private func scheduleAutosave() {
        guard !suppressAutosave else { return }
        // Don't persist while editing an already-published post.
        guard editingPostID == nil else { return }

        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            flushAutosaveNow()
        }
    }

    private func flushAutosaveNow() {
        guard editingPostID == nil else { return }
        let payloads = attachments.map {
            ComposerDraftAttachmentPayload(
                data: $0.data,
                contentType: $0.contentType,
                filename: $0.filename
            )
        }
        do {
            currentDraftID = try draftStore.upsert(
                id: currentDraftID,
                content: content,
                attachments: payloads
            )
        } catch {
            PipelineLogger.media.error(
                "draft autosave failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func clearInMemoryComposer() {
        suppressAutosave = true
        content = ""
        attachments = []
        loadedPickerItemIDs = []
        attachmentLoadGeneration &+= 1
        editingPostID = nil
        currentDraftID = nil
        errorMessage = nil
        successMessage = nil
        isSubmitting = false
        suppressAutosave = false
    }

    private func stablePickerItemID(_ item: PhotosPickerItem) -> String? {
        guard let id = item.itemIdentifier, !id.isEmpty else { return nil }
        return id
    }

    nonisolated private static func contentFingerprint(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func prepareAttachmentData(
        _ data: Data,
        contentType: String
    ) async -> (data: Data, contentType: String)? {
        let isGIF = contentType == "image/gif" || data.starts(with: [0x47, 0x49, 0x46])
        if isGIF {
            guard data.count <= Self.maxGIFBytes else {
                errorMessage = "GIF too large (max 15 MB)."
                return nil
            }
            return (data, "image/gif")
        }

        let hasAlpha = await Task.detached(priority: .userInitiated) {
            DownsampledImage.hasAlpha(data: data)
        }.value

        if hasAlpha {
            let png = await Task.detached(priority: .userInitiated) {
                DownsampledImage.pngData(from: data, maxPixelSize: Self.uploadMaxPixelSize)
            }.value
            guard let png else {
                errorMessage = "Couldn't process image."
                return nil
            }
            guard png.count <= Self.maxEncodedImageBytes else {
                errorMessage = "Image with transparency is too large."
                return nil
            }
            return (png, "image/png")
        }

        // Prefer WebP so media-service can copy without a second lossy pass.
        let webp = await Task.detached(priority: .userInitiated) {
            DownsampledImage.webpData(
                from: data,
                maxPixelSize: Self.uploadMaxPixelSize,
                compressionQuality: 0.90
            )
        }.value

        if let webp, webp.count <= Self.maxEncodedImageBytes {
            return (webp, "image/webp")
        }

        let tighterWebP = await Task.detached(priority: .userInitiated) {
            DownsampledImage.webpData(
                from: data,
                maxPixelSize: 1600,
                compressionQuality: 0.80
            )
        }.value
        if let tighterWebP, tighterWebP.count <= Self.maxEncodedImageBytes {
            return (tighterWebP, "image/webp")
        }

        // Fallback JPEG if WebP encode unavailable or still too large.
        let jpeg = await Task.detached(priority: .userInitiated) {
            DownsampledImage.jpegData(
                from: data,
                maxPixelSize: Self.uploadMaxPixelSize,
                compressionQuality: 0.85
            )
        }.value

        if let jpeg {
            if jpeg.count <= Self.maxEncodedImageBytes {
                return (jpeg, "image/jpeg")
            }
            let tighter = await Task.detached(priority: .userInitiated) {
                DownsampledImage.jpegData(
                    from: data,
                    maxPixelSize: 1600,
                    compressionQuality: 0.7
                )
            }.value
            if let tighter, tighter.count <= Self.maxEncodedImageBytes {
                return (tighter, "image/jpeg")
            }
            errorMessage = "Image is too large after compression."
            return nil
        }

        errorMessage = "Couldn't process image."
        return nil
    }

    private func contentType(for item: PhotosPickerItem, data: Data) -> String {
        if let type = item.supportedContentTypes.first {
            return type.preferredMIMEType ?? "image/jpeg"
        }
        if data.starts(with: [0x47, 0x49, 0x46]) {
            return "image/gif"
        }
        return "image/jpeg"
    }

    private func fileExtension(for contentType: String) -> String {
        switch contentType {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic", "image/heif": return "heic"
        default: return "jpg"
        }
    }
}
