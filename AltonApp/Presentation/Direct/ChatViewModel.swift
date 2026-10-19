import Foundation
import Observation
import Photos
import PhotosUI
import SwiftUI
import UIKit

@Observable
@MainActor
final class ChatViewModel {
    private let useCase: DirectUseCase
    private let realtime: RealtimeClient
    private let repository: DirectRepository
    private let postUseCase: PostUseCase?
    let currentUserID: String

    var conversation: DMConversation {
        didSet { rebuildRows() }
    }
    var messages: [DMMessage] = [] {
        didSet {
            if suppressRowRebuild { return }
            rebuildRows()
        }
    }
    /// Set while a single row is patched so `messages` does not rebuild the whole list.
    private var suppressRowRebuild = false
    /// Precomputed list metadata (dates, grouping, reply preview, sender). O(n) on messages change.
    private(set) var rows: [ChatRow] = []
    var postCards: [String: DMPostCard] = [:]
    /// Hydrated posts for shared take/shot cards (keyed by postID).
    var sharedPosts: [String: Post] = [:]
    /// Composer text is not observation-tracked — each keystroke must not rebuild the glass bar.
    @ObservationIgnored
    var draft = ""
    /// Bumps only on programmatic draft changes (send / edit / cancel / caption clear).
    var draftRevision = 0
    /// True when trimmed draft is non-empty. Changes only on empty↔non-empty transitions.
    var hasDraftText = false
    var isLoading = false
    var errorMessage: String?
    var peerTyping = false
    var peerLastReadSeq: Int64
    /// Group read receipts: user_id → last_read_seq.
    var groupReadByUser: [String: Int64] = [:]
    var nextBeforeSeq: Int64?
    var hasMoreOlder = false
    var isLoadingOlder = false
    var replyTo: DMMessage?
    var editingMessage: DMMessage?
    var forwardMessage: DMMessage?
    var showAttachSheet = false
    var showPhotoPicker = false
    var photoSelection: [PhotosPickerItem] = []
    var isNearBottom = true
    var unreadWhileScrolled = 0
    /// Row keys that should play the one-shot entrance. Not used for the text morph.
    var freshRowKeys: Set<String> = []
    var growingRowKeys: Set<String> = []
    @ObservationIgnored
    private var draftBeforeEdit: String?
    @ObservationIgnored
    private var typingThrottle = TypingThrottle()
    @ObservationIgnored
    private let draftStore: ChatDraftStore
    @ObservationIgnored
    private var resignObserver: NSObjectProtocol?
    @ObservationIgnored
    private var postCardFetchesInFlight: Set<String> = []
    @ObservationIgnored
    private var sharedPostFetchesInFlight: Set<String> = []

    private var eventsTask: Task<Void, Never>?
    private var typingHideTask: Task<Void, Never>?

    init(
        conversation: DMConversation,
        useCase: DirectUseCase,
        realtime: RealtimeClient,
        repository: DirectRepository,
        currentUserID: String,
        draftStore: ChatDraftStore? = nil,
        postUseCase: PostUseCase? = nil
    ) {
        self.conversation = conversation
        self.useCase = useCase
        self.realtime = realtime
        self.repository = repository
        self.currentUserID = currentUserID
        self.postUseCase = postUseCase
        self.peerLastReadSeq = conversation.peerLastReadSeq
        self.draftStore = draftStore ?? ChatDraftStore(userID: currentUserID)
        if let saved = self.draftStore.load(conversationID: conversation.id) {
            draft = saved
            hasDraftText = ChatComposerLimits.hasNonWhitespaceContent(saved)
            draftRevision = 1
        }
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }

    func isReadByPeer(_ message: DMMessage) -> Bool {
        guard isMine(message), !message.isPending, !message.isFailed else { return false }
        if conversation.isGroup {
            return groupSeenCount(for: message) > 0
        }
        return message.seq <= peerLastReadSeq
    }

    /// Label under the latest message the peer has read.
    func isLastReadByPeer(_ message: DMMessage) -> Bool {
        guard isMine(message), !message.isPending, !message.isFailed else { return false }
        if conversation.isGroup {
            let count = groupSeenCount(for: message)
            guard count > 0 else { return false }
            // Show under the newest own message that anyone has seen.
            let lastSeenSeq = groupReadByUser.values.max() ?? 0
            return message.seq == lastSeenSeq || (message.seq == (messages.last { isMine($0) && !$0.isPending }?.seq ?? -1) && count > 0)
        }
        guard peerLastReadSeq > 0 else { return false }
        return message.seq == peerLastReadSeq
    }

    func seenLabel(for message: DMMessage) -> String? {
        guard isLastReadByPeer(message) else { return nil }
        if conversation.isGroup {
            let n = groupSeenCount(for: message)
            return n > 0 ? "Просмотрели \(n)" : nil
        }
        return "Просмотрено"
    }

    /// Info row for Telegram-style action menu (time + optional edited / group seen).
    func actionInfoLine(for message: DMMessage) -> String {
        let clock = ChatDateCache.time(message.createdAt)
        let day = ChatDateCache.dayLabel(message.createdAt)
        let time: String = {
            if clock.isEmpty { return "" }
            if day.isEmpty { return clock }
            return "\(day), \(clock)"
        }()
        var parts: [String] = []
        if !time.isEmpty { parts.append(time) }
        if message.editedAt != nil { parts.append("edited") }
        if conversation.isGroup, isMine(message) {
            let n = groupSeenCount(for: message)
            if n > 0 { parts.append("seen by \(n)") }
        }
        return parts.joined(separator: " · ")
    }

    func updateDraftFromInput(_ text: String) {
        draft = text
        let has = ChatComposerLimits.hasNonWhitespaceContent(text)
        if has != hasDraftText {
            hasDraftText = has
        }
    }

    private func setDraftProgrammatically(_ text: String) {
        draft = text
        hasDraftText = ChatComposerLimits.hasNonWhitespaceContent(text)
        draftRevision += 1
    }

    /// Text persisted when leaving the chat (never the in-progress edit body).
    private var draftTextToPersist: String {
        if editingMessage != nil {
            return draftBeforeEdit ?? ""
        }
        return draft
    }

    func persistDraft() {
        let text = draftTextToPersist
        if ChatComposerLimits.hasNonWhitespaceContent(text) {
            draftStore.save(conversationID: conversation.id, text: text)
        } else {
            draftStore.clear(conversationID: conversation.id)
        }
    }

    private func clearPersistedDraft() {
        draftStore.clear(conversationID: conversation.id)
    }

    func markRowFresh(_ key: String) {
        freshRowKeys.insert(key)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            freshRowKeys.remove(key)
        }
    }

    /// Grows the new row in place. Does not replay the bubble fade.
    func markRowGrowing(_ key: String) {
        growingRowKeys.insert(key)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            growingRowKeys.remove(key)
        }
    }

    private func noteFresh(_ message: DMMessage) {
        let key = message.clientMsgID.isEmpty ? message.id : message.clientMsgID
        markRowFresh(key)
    }

    private func rebuildRows() {
        rows = ChatRowsBuilder.build(messages: messages, members: conversation.members)
    }

    private func appendMessage(_ message: DMMessage) {
        suppressRowRebuild = true
        messages.append(message)
        suppressRowRebuild = false
        rows = ChatRowsBuilder.appending(
            message,
            onto: rows,
            messages: messages,
            members: conversation.members
        )
    }

    private func replaceMessage(at index: Int, with message: DMMessage) {
        suppressRowRebuild = true
        messages[index] = message
        suppressRowRebuild = false
        rows = ChatRowsBuilder.replacing(rows, message: message)
    }

    private func mutateMessage(at index: Int, _ body: (inout DMMessage) -> Void) {
        guard messages.indices.contains(index) else { return }
        var copy = messages[index]
        body(&copy)
        replaceMessage(at: index, with: copy)
    }

    func groupSeenCount(for message: DMMessage) -> Int {
        groupReadByUser.values.filter { $0 >= message.seq }.count
    }

    func member(forUserID userID: String) -> DMConversationMember? {
        conversation.members.first { $0.userID == userID }
    }

    func isMine(_ message: DMMessage) -> Bool {
        message.senderID == currentUserID || message.senderID == "me"
    }

    private var didStartLive = false
    private var didScheduleInitialLoad = false

    /// Shows the cached thread at once and starts history during the open animation.
    func prepareCached() {
        if messages.isEmpty {
            messages = repository.cachedMessages(conversationID: conversation.id)
        }
        let postIDs = messages.compactMap { message -> String? in
            guard message.kind == .postShare, let postID = message.postID, !postID.isEmpty else { return nil }
            return postID
        }
        for share in repository.cachedShares(postIDs: postIDs) {
            if postCards[share.card.postID] == nil {
                postCards[share.card.postID] = share.card
            }
            if let post = share.post, sharedPosts[post.id] == nil {
                sharedPosts[post.id] = post
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.persistDraft()
                }
            }
        }
        scheduleInitialLoad()
    }

    /// Realtime socket. History is already scheduled from `prepareCached`.
    func startLive() {
        guard !didStartLive else { return }
        didStartLive = true
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            guard let self else { return }
            await realtime.connect()
            for await event in await realtime.events() {
                await self.handle(event)
            }
        }
        scheduleInitialLoad()
    }

    private func scheduleInitialLoad() {
        guard !didScheduleInitialLoad else { return }
        didScheduleInitialLoad = true
        Task { await loadInitial() }
    }

    func stop() {
        persistDraft()
        eventsTask?.cancel()
        typingHideTask?.cancel()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    func loadInitial() async {
        let showSpinner = messages.isEmpty
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }
        do {
            let page = try await useCase.history(conversationID: conversation.id, beforeSeq: nil)
            merge(page)
            if let last = messages.last {
                try await useCase.markRead(conversationID: conversation.id, seq: last.seq)
                await realtime.markRead(conversationID: conversation.id, seq: last.seq)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOlder() async {
        guard hasMoreOlder, !isLoadingOlder, let before = nextBeforeSeq else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await useCase.history(conversationID: conversation.id, beforeSeq: before)
            merge(page, prepend: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns the optimistic `clientMsgID` for a new text send (nil when editing / paste / empty).
    @discardableResult
    func send(clientID explicitID: String? = nil) async -> String? {
        // Photos on the composer card go out with the draft as the caption.
        if !pendingPasteImages.isEmpty {
            await sendPastedImages()
            return nil
        }
        if editingMessage != nil {
            await commitEdit()
            return nil
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let replySeq = replyTo?.seq
        let clientID = explicitID ?? UUID().uuidString
        let optimistic = DMMessage(
            id: clientID,
            conversationID: conversation.id,
            seq: (messages.last?.seq ?? 0) + 1,
            senderID: "me",
            kind: .text,
            body: text,
            postID: nil,
            postType: nil,
            replyToSeq: replySeq,
            clientMsgID: clientID,
            createdAt: ChatDateCache.stampNow(),
            editedAt: nil,
            deletedAt: nil,
            mediaURL: nil,
            mediaThumbURL: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: nil,
            isPending: true,
            isFailed: false
        )
        var clear = Transaction()
        clear.disablesAnimations = true
        withTransaction(clear) {
            setDraftProgrammatically("")
            replyTo = nil
        }
        let draftConversationID = conversation.id
        let store = draftStore
        Task.detached { store.clear(conversationID: draftConversationID) }
        var insert = Transaction()
        insert.disablesAnimations = true
        withTransaction(insert) {
            appendMessage(optimistic)
        }
        // Deliver in a child task so the send-flight animation can start immediately.
        Task { await deliverText(clientMsgID: clientID, text: text, replyToSeq: replySeq) }
        return clientID
    }

    func beginEdit(_ message: DMMessage) {
        guard DMEditRules.canEdit(message, currentUserID: currentUserID) else { return }
        if editingMessage == nil {
            draftBeforeEdit = draft
        }
        replyTo = nil
        editingMessage = message
        setDraftProgrammatically(message.body)
    }

    func cancelEdit() {
        editingMessage = nil
        setDraftProgrammatically(draftBeforeEdit ?? "")
        draftBeforeEdit = nil
    }

    func commitEdit() async {
        guard let editing = editingMessage else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != editing.body else {
            cancelEdit()
            return
        }
        guard let idx = messages.firstIndex(where: {
            $0.id == editing.id
                || (!$0.clientMsgID.isEmpty && $0.clientMsgID == editing.clientMsgID)
                || ($0.seq == editing.seq && editing.seq > 0)
        }) else {
            errorMessage = "Couldn't update this message."
            return
        }
        let targetID = messages[idx].id
        let previousBody = messages[idx].body
        let previousEditedAt = messages[idx].editedAt
        messages[idx].body = text
        messages[idx].editedAt = ChatDateCache.stampNow()
        editingMessage = nil
        setDraftProgrammatically(draftBeforeEdit ?? "")
        draftBeforeEdit = nil
        do {
            let updated = try await useCase.editMessage(messageID: targetID, body: text)
            if let i = messages.firstIndex(where: { $0.id == targetID || $0.id == updated.id }) {
                var merged = updated
                if merged.reactions.isEmpty, !messages[i].reactions.isEmpty {
                    merged.reactions = messages[i].reactions
                }
                messages[i] = merged
            }
        } catch {
            if let i = messages.firstIndex(where: { $0.id == targetID }) {
                messages[i].body = previousBody
                messages[i].editedAt = previousEditedAt
            }
            errorMessage = error.localizedDescription
        }
    }

    func sendAttachedImages(_ images: [UIImage], caption: String?) async {
        showAttachSheet = false
        await sendImageSequence(images, caption: caption)
    }

    func sendAttachedSelection(
        ids: [String],
        captured: [ChatCapturedPhoto],
        caption: String?
    ) async {
        showAttachSheet = false
        var images: [UIImage] = []
        images.reserveCapacity(ids.count)
        for id in ids {
            if ChatCaptureID.isCapture(id) {
                if let photo = captured.first(where: { $0.id == id }),
                   let image = await Self.loadCaptured(photo) {
                    images.append(image)
                }
            } else if let image = await Self.loadLibraryAsset(id) {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            errorMessage = "Couldn’t load selected photos."
            return
        }
        await sendImageSequence(images, caption: caption)
    }

    private nonisolated static func loadCaptured(_ photo: ChatCapturedPhoto) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            try? photo.loadFullImage()
        }.value
    }

    private nonisolated static func loadLibraryAsset(_ localIdentifier: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = result.firstObject else { return nil }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = true
            options.resizeMode = .fast
            let side = min(max(asset.pixelWidth, asset.pixelHeight), 2048)
            var loaded: UIImage?
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                loaded = image
            }
            return loaded
        }.value
    }

    /// Photos that need an aspect crop before send (outside 1:3…3:1).
    var pendingDMCrop: PhotoCropDraft?
    /// True while Done on the crop card is already handing the image to send.
    /// Dismiss of that card must not cancel the send.
    private var isFinishingCrop = false
    /// Images pasted from the clipboard awaiting user confirmation.
    var pendingPasteImages: [UIImage] = []
    /// Remaining images to send after an interactive crop finishes.
    private var pendingImageQueue: [UIImage] = []

    func queuePastedImages(_ images: [UIImage]) {
        let capped = Array(images.prefix(ChatComposerLimits.maxPasteImages))
        guard !capped.isEmpty else { return }
        pendingPasteImages = capped
    }

    func cancelPastedImages() {
        pendingPasteImages = []
    }

    func sendPastedImages(_ images: [UIImage]? = nil) async {
        let images = images ?? pendingPasteImages
        pendingPasteImages = []
        let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        setDraftProgrammatically("")
        clearPersistedDraft()
        guard !images.isEmpty else { return }
        await sendImageSequence(images, caption: caption.isEmpty ? nil : caption)
    }

    func stagePickedPhotos() async {
        let items = photoSelection
        photoSelection = []
        var images: [UIImage] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            if let image {
                images.append(image)
            }
        }
        let capped = Array(images.prefix(ChatComposerLimits.maxPasteImages))
        guard !capped.isEmpty else { return }
        pendingPasteImages = capped
    }

    /// Caption is applied to the first successfully sent image only (WhatsApp-style).
    private var pendingImageCaption: String?

    private func sendImageSequence(_ images: [UIImage], caption: String? = nil) async {
        if let caption, !caption.isEmpty {
            pendingImageCaption = caption
        }
        var queue = images
        while !queue.isEmpty {
            let image = queue.removeFirst()
            if !DMImageRules.isSendable(image) {
                errorMessage = "Image is too small to send."
                continue
            }
            // Compress already center-crops into 1:3…3:1. Stopping here for a crop
            // card drops the photo: dismissing that card cancels the send.
            await sendCompressedImage(image)
        }
        pendingImageQueue = []
        pendingImageCaption = nil
    }

    func finishDMCrop(_ image: UIImage) async {
        let rest = pendingImageQueue
        let caption = pendingImageCaption
        pendingImageQueue = []
        pendingImageCaption = nil
        isFinishingCrop = true
        pendingDMCrop = nil
        defer { isFinishingCrop = false }

        guard DMImageRules.isSendable(image) else {
            errorMessage = "Image is too small to send."
            await sendImageSequence(rest, caption: caption)
            return
        }
        await sendCompressedImage(image, caption: caption)
        await sendImageSequence(rest)
    }

    func cancelDMCrop() {
        guard !isFinishingCrop else { return }
        pendingDMCrop = nil
        pendingImageQueue = []
        pendingImageCaption = nil
    }

    /// Swipe-down on the crop card. Done already copied the queue before clearing the cover.
    func cropCoverDismissed() {
        guard pendingDMCrop == nil, !isFinishingCrop else { return }
        pendingImageQueue = []
        pendingImageCaption = nil
    }

    private func sendCompressedImage(_ image: UIImage, caption explicitCaption: String? = nil) async {
        let caption = explicitCaption ?? pendingImageCaption
        pendingImageCaption = nil
        let clientID = UUID().uuidString
        let replySeq = replyTo?.seq
        replyTo = nil
        // Encode off the main actor. The chat keeps scrolling and sending while this runs.
        let compressed = await Task.detached(priority: .userInitiated) {
            let result = DirectUseCase.compressImageForDM(image)
            if let result {
                ChatLocalImageCache.storeDecoded(clientMsgID: clientID, data: result.data)
            }
            return result
        }.value
        guard let compressed else {
            errorMessage = "Image is too small to send."
            return
        }
        let optimistic = DMMessage(
            id: clientID,
            conversationID: conversation.id,
            seq: (messages.last?.seq ?? 0) + 1,
            senderID: "me",
            kind: .image,
            body: caption ?? "",
            postID: nil,
            postType: nil,
            replyToSeq: replySeq,
            clientMsgID: clientID,
            createdAt: ChatDateCache.stampNow(),
            editedAt: nil,
            deletedAt: nil,
            mediaURL: nil,
            mediaThumbURL: nil,
            mediaWidth: compressed.width,
            mediaHeight: compressed.height,
            mediaStatus: "processing",
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: compressed.data,
            isPending: true,
            isFailed: false
        )
        appendMessage(optimistic)
        noteFresh(optimistic)
        do {
            let sent = try await useCase.sendImage(
                conversationID: conversation.id,
                imageData: compressed.data,
                contentType: "image/jpeg",
                width: compressed.width,
                height: compressed.height,
                clientMsgID: clientID,
                replyToSeq: replySeq,
                caption: caption
            )
            var merged = sent
            // Keep local preview until remote thumb is ready.
            if merged.mediaThumbURL == nil {
                merged.localImageData = compressed.data
            }
            replace(clientMsgID: clientID, with: merged)
        } catch {
            markFailed(clientMsgID: clientID)
            errorMessage = error.localizedDescription
        }
    }

    func sendGIF(_ gif: KlipyGIF) async {
        showAttachSheet = false
        let clientID = UUID().uuidString
        let replySeq = replyTo?.seq
        replyTo = nil
        let optimistic = DMMessage(
            id: clientID,
            conversationID: conversation.id,
            seq: (messages.last?.seq ?? 0) + 1,
            senderID: "me",
            kind: .gif,
            body: "",
            postID: nil,
            postType: nil,
            replyToSeq: replySeq,
            clientMsgID: clientID,
            createdAt: ChatDateCache.stampNow(),
            editedAt: nil,
            deletedAt: nil,
            mediaURL: gif.downloadURL,
            mediaThumbURL: gif.previewURL,
            mediaWidth: gif.width,
            mediaHeight: gif.height,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: nil,
            isPending: true,
            isFailed: false
        )
        appendMessage(optimistic)
        noteFresh(optimistic)
        do {
            let sent = try await useCase.sendGIF(
                conversationID: conversation.id,
                gif: gif,
                clientMsgID: clientID,
                replyToSeq: replySeq
            )
            replace(clientMsgID: clientID, with: sent)
        } catch {
            markFailed(clientMsgID: clientID)
            errorMessage = error.localizedDescription
        }
    }

    func sendSticker(_ sticker: Sticker) async {
        let clientID = UUID().uuidString
        let replySeq = replyTo?.seq
        replyTo = nil
        let optimistic = DMMessage(
            id: clientID,
            conversationID: conversation.id,
            seq: (messages.last?.seq ?? 0) + 1,
            senderID: "me",
            kind: .sticker,
            body: "",
            postID: nil,
            postType: nil,
            replyToSeq: replySeq,
            clientMsgID: clientID,
            createdAt: ChatDateCache.stampNow(),
            editedAt: nil,
            deletedAt: nil,
            mediaURL: sticker.url,
            mediaThumbURL: sticker.thumbURL,
            mediaWidth: sticker.width,
            mediaHeight: sticker.height,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: nil,
            isPending: true,
            isFailed: false,
            stickerID: sticker.id
        )
        appendMessage(optimistic)
        noteFresh(optimistic)
        do {
            let sent = try await useCase.sendSticker(
                conversationID: conversation.id,
                stickerID: sticker.id,
                clientMsgID: clientID,
                replyToSeq: replySeq
            )
            replace(clientMsgID: clientID, with: sent)
        } catch {
            markFailed(clientMsgID: clientID)
            errorMessage = error.localizedDescription
        }
    }

    func insertEmoji(_ emoji: String) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setDraftProgrammatically(draft + trimmed)
    }

    func sendLocation(_ location: DMLocation) async {
        showAttachSheet = false
        let clientID = UUID().uuidString
        let replySeq = replyTo?.seq
        replyTo = nil
        let optimisticLocation = optimisticPayload(
            clientID: clientID,
            kind: .location,
            replySeq: replySeq,
            location: location,
            checklist: nil
        )
        appendMessage(optimisticLocation)
        noteFresh(optimisticLocation)
        do {
            let sent = try await useCase.sendLocation(
                conversationID: conversation.id,
                location: location,
                clientMsgID: clientID,
                replyToSeq: replySeq
            )
            replace(clientMsgID: clientID, with: sent)
        } catch {
            markFailed(clientMsgID: clientID)
            errorMessage = error.localizedDescription
        }
    }

    func sendChecklist(_ checklist: DMChecklist) async {
        showAttachSheet = false
        let clientID = UUID().uuidString
        let replySeq = replyTo?.seq
        replyTo = nil
        let optimisticChecklist = optimisticPayload(
            clientID: clientID,
            kind: .checklist,
            replySeq: replySeq,
            location: nil,
            checklist: checklist
        )
        appendMessage(optimisticChecklist)
        noteFresh(optimisticChecklist)
        do {
            let sent = try await useCase.sendChecklist(
                conversationID: conversation.id,
                checklist: checklist,
                clientMsgID: clientID,
                replyToSeq: replySeq
            )
            replace(clientMsgID: clientID, with: sent)
        } catch {
            markFailed(clientMsgID: clientID)
            errorMessage = error.localizedDescription
        }
    }

    func sendPoll(_ poll: DMPoll) async {
        showAttachSheet = false
        let clientID = UUID().uuidString
        let replySeq = replyTo?.seq
        replyTo = nil
        let optimistic = optimisticPayload(
            clientID: clientID,
            kind: .poll,
            replySeq: replySeq,
            location: nil,
            checklist: nil,
            poll: poll
        )
        appendMessage(optimistic)
        noteFresh(optimistic)
        do {
            let sent = try await useCase.sendPoll(
                conversationID: conversation.id,
                poll: poll,
                clientMsgID: clientID,
                replyToSeq: replySeq
            )
            replace(clientMsgID: clientID, with: sent)
        } catch {
            markFailed(clientMsgID: clientID)
            errorMessage = error.localizedDescription
        }
    }

    func votePoll(messageID: String, optionIDs: [Int]) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }),
              let poll = messages[idx].poll,
              ChatPollState.canVote(poll, hasVoted: ChatPollState.hasVoted(messages[idx].pollVotes, userID: currentUserID), isPending: messages[idx].isPending)
        else { return }
        let snapshot = messages[idx]
        let next = ChatPollState.optimisticVote(
            votes: snapshot.pollVotes,
            tallies: snapshot.pollTallies,
            totalVoters: snapshot.pollTotalVoters,
            userID: currentUserID,
            optionIDs: optionIDs
        )
        mutateMessage(at: idx) {
            $0.pollVotes = next.votes
            $0.pollTallies = next.tallies
            $0.pollTotalVoters = next.totalVoters
        }
        do {
            let updated = try await useCase.votePoll(messageID: messageID, optionIDs: optionIDs)
            if let current = messages.firstIndex(where: { $0.id == messageID }) {
                replaceMessage(at: current, with: mergingPoll(updated, into: messages[current]))
            }
        } catch {
            if let current = messages.firstIndex(where: { $0.id == messageID }) {
                mutateMessage(at: current) {
                    $0.pollVotes = snapshot.pollVotes
                    $0.pollTallies = snapshot.pollTallies
                    $0.pollTotalVoters = snapshot.pollTotalVoters
                }
            }
            errorMessage = error.localizedDescription
        }
    }

    func retractPollVote(messageID: String) async {
        guard let message = messages.first(where: { $0.id == messageID }),
              let poll = message.poll,
              ChatPollState.canRetract(poll, hasVoted: ChatPollState.hasVoted(message.pollVotes, userID: currentUserID))
        else { return }
        await votePoll(messageID: messageID, optionIDs: [])
    }

    func closePoll(messageID: String) async {
        do {
            let updated = try await useCase.closePoll(messageID: messageID)
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                replaceMessage(at: idx, with: mergingPoll(updated, into: messages[idx]))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appendPollOption(messageID: String, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let updated = try await useCase.appendPollOptions(messageID: messageID, options: [trimmed])
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                replaceMessage(at: idx, with: mergingPoll(updated, into: messages[idx]))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergingPoll(_ updated: DMMessage, into existing: DMMessage) -> DMMessage {
        var merged = updated
        if merged.pollVotes.isEmpty, !existing.pollVotes.isEmpty, merged.poll?.anonymous == true {
            merged.pollVotes = existing.pollVotes
        }
        return merged
    }

    func toggleChecklistItem(messageID: String, itemID: Int) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }),
              let checklist = messages[idx].checklist,
              messages[idx].deletedAt == nil,
              !messages[idx].isPending else { return }
        let isAuthor = isMine(messages[idx])
        guard ChatChecklistState.canMark(checklist, isAuthor: isAuthor) else { return }
        let previous = messages[idx].checklistMarks
        let done = !previous.contains { $0.itemID == itemID }
        mutateMessage(at: idx) {
            $0.checklistMarks = ChatChecklistState.toggled(
                marks: previous,
                itemID: itemID,
                userID: currentUserID,
                done: done
            )
        }
        checklistUndo = (messageID, previous)
        await realtime.setChecklistItem(messageID: messageID, itemID: itemID, done: done)
    }

    func appendChecklistItem(messageID: String, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let updated = try await useCase.appendChecklistItems(messageID: messageID, items: [trimmed])
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                var merged = updated
                if merged.checklistMarks.isEmpty {
                    merged.checklistMarks = messages[idx].checklistMarks
                }
                replaceMessage(at: idx, with: merged)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var checklistUndo: (messageID: String, marks: [DMChecklistMark])?

    private func optimisticPayload(
        clientID: String,
        kind: DMMessageKind,
        replySeq: Int64?,
        location: DMLocation?,
        checklist: DMChecklist?,
        poll: DMPoll? = nil
    ) -> DMMessage {
        DMMessage(
            id: clientID,
            conversationID: conversation.id,
            seq: (messages.last?.seq ?? 0) + 1,
            senderID: "me",
            kind: kind,
            body: "",
            postID: nil,
            postType: nil,
            replyToSeq: replySeq,
            clientMsgID: clientID,
            createdAt: ChatDateCache.stampNow(),
            editedAt: nil,
            deletedAt: nil,
            mediaURL: nil,
            mediaThumbURL: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaStatus: nil,
            forwardedFromUserID: nil,
            forwardedFromUsername: nil,
            localImageData: nil,
            isPending: true,
            isFailed: false,
            location: location,
            checklist: checklist,
            checklistMarks: [],
            poll: poll
        )
    }

    func retry(_ message: DMMessage) async {
        guard message.isFailed || message.isPending else { return }
        if let idx = messages.firstIndex(where: { $0.clientMsgID == message.clientMsgID }) {
            messages[idx].isPending = true
            messages[idx].isFailed = false
        }
        switch message.kind {
        case .text:
            await deliverText(
                clientMsgID: message.clientMsgID,
                text: message.body,
                replyToSeq: message.replyToSeq
            )
        case .image:
            guard let data = message.localImageData else {
                markFailed(clientMsgID: message.clientMsgID)
                return
            }
            do {
                let sent = try await useCase.sendImage(
                    conversationID: conversation.id,
                    imageData: data,
                    contentType: "image/jpeg",
                    width: message.mediaWidth,
                    height: message.mediaHeight,
                    clientMsgID: message.clientMsgID,
                    replyToSeq: message.replyToSeq
                )
                replace(clientMsgID: message.clientMsgID, with: sent)
            } catch {
                markFailed(clientMsgID: message.clientMsgID)
            }
        case .gif:
            // GIF retry needs original Klipy metadata; mark failed for re-pick.
            markFailed(clientMsgID: message.clientMsgID)
        case .sticker:
            guard let stickerID = message.stickerID, !stickerID.isEmpty else {
                markFailed(clientMsgID: message.clientMsgID)
                return
            }
            do {
                let sent = try await useCase.sendSticker(
                    conversationID: conversation.id,
                    stickerID: stickerID,
                    clientMsgID: message.clientMsgID,
                    replyToSeq: message.replyToSeq
                )
                replace(clientMsgID: message.clientMsgID, with: sent)
            } catch {
                markFailed(clientMsgID: message.clientMsgID)
            }
        case .location:
            guard let location = message.location else {
                markFailed(clientMsgID: message.clientMsgID)
                return
            }
            do {
                let sent = try await useCase.sendLocation(
                    conversationID: conversation.id,
                    location: location,
                    clientMsgID: message.clientMsgID,
                    replyToSeq: message.replyToSeq
                )
                replace(clientMsgID: message.clientMsgID, with: sent)
            } catch {
                markFailed(clientMsgID: message.clientMsgID)
            }
        case .poll:
            guard let poll = message.poll else {
                markFailed(clientMsgID: message.clientMsgID)
                return
            }
            do {
                let sent = try await useCase.sendPoll(
                    conversationID: conversation.id,
                    poll: poll,
                    clientMsgID: message.clientMsgID,
                    replyToSeq: message.replyToSeq
                )
                replace(clientMsgID: message.clientMsgID, with: sent)
            } catch {
                markFailed(clientMsgID: message.clientMsgID)
            }
        case .checklist:
            guard let checklist = message.checklist else {
                markFailed(clientMsgID: message.clientMsgID)
                return
            }
            do {
                let sent = try await useCase.sendChecklist(
                    conversationID: conversation.id,
                    checklist: checklist,
                    clientMsgID: message.clientMsgID,
                    replyToSeq: message.replyToSeq
                )
                replace(clientMsgID: message.clientMsgID, with: sent)
            } catch {
                markFailed(clientMsgID: message.clientMsgID)
            }
        default:
            markFailed(clientMsgID: message.clientMsgID)
        }
    }

    func delete(_ message: DMMessage) async {
        guard !message.isPending else {
            messages.removeAll { $0.clientMsgID == message.clientMsgID }
            return
        }
        do {
            try await useCase.deleteMessage(messageID: message.id)
            // Keep tombstone in the array for seq continuity / reply quotes,
            // but mark deleted so the chat list skips rendering it.
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx].deletedAt = ChatDateCache.stampNow()
                messages[idx].body = ""
                messages[idx].mediaURL = nil
                messages[idx].mediaThumbURL = nil
                messages[idx].reactions = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static let reactionEmojis = DMReactionCatalog.quick

    func react(to message: DMMessage, emoji: String) async {
        guard message.deletedAt == nil, !message.isPending else { return }
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let previous = messages[idx].reactions
        let mine = previous.first(where: { $0.userID == currentUserID })
        // Toggle off if same emoji.
        if mine?.emoji == emoji {
            mutateMessage(at: idx) { $0.reactions = previous.filter { $0.userID != currentUserID } }
            do {
                let reactions = try await useCase.clearReaction(messageID: message.id)
                mutateMessage(at: idx) { $0.reactions = reactions }
            } catch {
                mutateMessage(at: idx) { $0.reactions = previous }
                errorMessage = error.localizedDescription
            }
            return
        }
        var optimistic = previous.filter { $0.userID != currentUserID }
        optimistic.append(DMMessageReaction(userID: currentUserID, emoji: emoji))
        mutateMessage(at: idx) { $0.reactions = optimistic }
        do {
            let reactions = try await useCase.setReaction(messageID: message.id, emoji: emoji)
            mutateMessage(at: idx) { $0.reactions = reactions }
        } catch {
            mutateMessage(at: idx) { $0.reactions = previous }
            errorMessage = error.localizedDescription
        }
    }

    func doubleTapReact(_ message: DMMessage) async {
        await react(to: message, emoji: "❤️")
    }

    func forward(_ message: DMMessage, to conversationIDs: [String]) async {
        forwardMessage = nil
        guard !conversationIDs.isEmpty else { return }
        do {
            try await useCase.forward(messageID: message.id, conversationIDs: conversationIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func notifyTyping() {
        guard typingThrottle.shouldSend() else { return }
        Task { await realtime.typing(conversationID: conversation.id) }
    }

    func message(forSeq seq: Int64?) -> DMMessage? {
        guard let seq else { return nil }
        return messages.first { $0.seq == seq }
    }

    private func deliverText(clientMsgID: String, text: String, replyToSeq: Int64?) async {
        do {
            let sent = try await useCase.sendText(
                conversationID: conversation.id,
                text: text,
                clientMsgID: clientMsgID,
                replyToSeq: replyToSeq
            )
            replace(clientMsgID: clientMsgID, with: sent)
        } catch {
            markFailed(clientMsgID: clientMsgID)
            errorMessage = error.localizedDescription
        }
    }

    private func replace(clientMsgID: String, with sent: DMMessage) {
        if let idx = messages.firstIndex(where: { $0.clientMsgID == clientMsgID || $0.id == clientMsgID }) {
            replaceMessage(at: idx, with: sent)
        } else {
            messages.append(sent)
            messages.sort { $0.seq < $1.seq }
        }
        ensurePostCard(for: sent)
    }

    private func ensurePostCard(for message: DMMessage) {
        guard message.kind == .postShare,
              let postID = message.postID,
              !postID.isEmpty,
              postCards[postID] == nil,
              message.seq > 0
        else { return }
        guard !postCardFetchesInFlight.contains(postID) else { return }
        postCardFetchesInFlight.insert(postID)
        Task { @MainActor in
            defer { postCardFetchesInFlight.remove(postID) }
            guard postCards[postID] == nil else { return }
            if let cards = try? await useCase.postCards(
                conversationID: conversation.id,
                seq: message.seq
            ) {
                for card in cards {
                    postCards[card.postID] = card
                }
            }
        }
    }

    /// Hydrates a full `Post` for shared take/shot cards. A cached post paints
    /// first; the network copy replaces it and is written back for the next open.
    func loadSharedPost(postID: String) {
        guard !postID.isEmpty else { return }
        guard let postUseCase else { return }
        guard !sharedPostFetchesInFlight.contains(postID) else { return }
        sharedPostFetchesInFlight.insert(postID)
        Task { @MainActor in
            defer { sharedPostFetchesInFlight.remove(postID) }
            if let post = try? await postUseCase.fetchPost(id: postID) {
                sharedPosts[postID] = post
                await repository.rememberSharedPost(post)
            }
        }
    }

    func updateSharedPost(_ post: Post) {
        sharedPosts[post.id] = post
        Task { await repository.rememberSharedPost(post) }
    }

    private func markFailed(clientMsgID: String) {
        if let idx = messages.firstIndex(where: { $0.clientMsgID == clientMsgID }) {
            mutateMessage(at: idx) {
                $0.isPending = false
                $0.isFailed = true
            }
        }
    }

    private func merge(_ page: DMHistoryPage, prepend: Bool = false) {
        nextBeforeSeq = page.nextBeforeSeq
        hasMoreOlder = page.nextBeforeSeq != nil
        for card in page.postCards {
            postCards[card.postID] = card
        }
        if prepend {
            let existing = Set(messages.map(\.id))
            let older = page.messages.filter { !existing.contains($0.id) }
            messages.insert(contentsOf: older, at: 0)
        } else if messages.isEmpty {
            messages = page.messages
        } else {
            var byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
            for msg in page.messages {
                if let idx = messages.firstIndex(where: {
                    $0.isPending && $0.clientMsgID == msg.clientMsgID
                }) {
                    byID.removeValue(forKey: messages[idx].id)
                }
                byID[msg.id] = msg
            }
            messages = byID.values.sorted { $0.seq < $1.seq }
        }
    }

    func removeGroupMember(_ userID: String) async -> String? {
        do {
            if let updated = try await useCase.removeGroupMember(
                conversationID: conversation.id,
                userID: userID
            ) {
                conversation = updated
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var currentMember: DMConversationMember? {
        conversation.members.first { $0.userID == currentUserID }
    }

    var canBanGroupMembers: Bool { currentMember?.canBanMembers == true }
    var canAssignGroupAdmins: Bool { currentMember?.canAssignAdmins == true }

    func banGroupMember(_ userID: String) async {
        do {
            conversation = try await useCase.banGroupMember(
                conversationID: conversation.id,
                memberID: userID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setGroupAdmin(memberID: String, isAdmin: Bool, rights: [String]) async -> String? {
        do {
            conversation = try await useCase.setGroupAdmin(
                conversationID: conversation.id,
                memberID: memberID,
                isAdmin: isAdmin,
                rights: rights
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func handle(_ event: RealtimeEvent) async {
        switch event {
        case .messageNew(let msg) where msg.conversationID == conversation.id:
            if let idx = messages.firstIndex(where: { $0.clientMsgID == msg.clientMsgID || $0.id == msg.id }) {
                replaceMessage(at: idx, with: msg)
            } else {
                messages.append(msg)
                messages.sort { $0.seq < $1.seq }
                if isNearBottom {
                    noteFresh(msg)
                }
                if !isNearBottom && !isMine(msg) {
                    unreadWhileScrolled += 1
                }
            }
            ensurePostCard(for: msg)
            try? await useCase.markRead(conversationID: conversation.id, seq: msg.seq)
        case .conversationUpdated(let update) where update.conversationID == conversation.id:
            conversation = conversation.applying(update)
        case .messageUpdated(let msg) where msg.conversationID == conversation.id:
            if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                var updated = msg
                if updated.localImageData == nil {
                    updated.localImageData = messages[idx].localImageData
                }
                if updated.mediaThumbURL != nil || updated.mediaStatus == "ready" {
                    updated.localImageData = nil
                }
                // Preserve reactions if update payload omitted them.
                if updated.reactions.isEmpty, !messages[idx].reactions.isEmpty,
                   msg.deletedAt == nil {
                    updated.reactions = messages[idx].reactions
                }
                if updated.checklistMarks.isEmpty, !messages[idx].checklistMarks.isEmpty,
                   msg.deletedAt == nil {
                    updated.checklistMarks = messages[idx].checklistMarks
                }
                replaceMessage(at: idx, with: updated)
            }
        case .messageReaction(let conversationID, let messageID, let reactions)
            where conversationID == conversation.id:
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                mutateMessage(at: idx) { $0.reactions = reactions }
            }
            await repository.rememberReactions(messageID: messageID, reactions: reactions)
        case .messagePoll(let conversationID, let messageID, let tallies, let totalVoters, let voters, let closed, let myOptionIDs)
            where conversationID == conversation.id:
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                mutateMessage(at: idx) { message in
                    message.pollTallies = tallies
                    message.pollTotalVoters = totalVoters
                    if var poll = message.poll {
                        poll.closed = closed
                        message.poll = poll
                    }
                    if message.poll?.anonymous == false {
                        message.pollVotes = voters
                    }
                    if let myOptionIDs {
                        var votes = message.pollVotes.filter { $0.userID != currentUserID }
                        votes.append(contentsOf: myOptionIDs.map { DMPollVote(optionID: $0, userID: currentUserID) })
                        message.pollVotes = votes
                    }
                }
            }
        case .messageChecklist(let conversationID, let messageID, let marks)
            where conversationID == conversation.id:
            if let idx = messages.firstIndex(where: { $0.id == messageID }) {
                mutateMessage(at: idx) { $0.checklistMarks = marks }
            }
            if checklistUndo?.messageID == messageID {
                checklistUndo = nil
            }
        case .error(let code, _) where code == "checklist_failed":
            if let undo = checklistUndo,
               let idx = messages.firstIndex(where: { $0.id == undo.messageID }) {
                mutateMessage(at: idx) { $0.checklistMarks = undo.marks }
            }
            checklistUndo = nil
        case .ack(_, _, _, let conversationID, _) where conversationID == conversation.id:
            break
        case .read(let conversationID, let userID, let seq) where conversationID == conversation.id:
            if conversation.isGroup {
                if userID != currentUserID {
                    groupReadByUser[userID] = max(groupReadByUser[userID] ?? 0, seq)
                }
            } else if userID == conversation.peerUserID {
                peerLastReadSeq = max(peerLastReadSeq, seq)
                conversation.peerLastReadSeq = peerLastReadSeq
            }
        case .typing(let conversationID, let userID) where conversationID == conversation.id:
            guard userID != currentUserID else { break }
            if !peerTyping { peerTyping = true }
            typingHideTask?.cancel()
            typingHideTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                peerTyping = false
            }
        case .connected:
            if let last = messages.last(where: { !$0.isPending && !$0.isFailed })?.seq {
                if let page = try? await useCase.syncAfter(conversationID: conversation.id, afterSeq: last) {
                    merge(page)
                }
            }
        default:
            break
        }
    }
}
