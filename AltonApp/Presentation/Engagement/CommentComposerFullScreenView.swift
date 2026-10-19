import SwiftUI
import PhotosUI
import Nuke
import NukeUI

struct CommentComposerFullScreenView: View {
    @Binding var draft: String
    @Binding var attachments: [PostAttachment]
    @Binding var pendingSticker: Sticker?
    @Binding var pendingGIF: KlipyGIF?
    let isSubmitting: Bool
    var maxAttachments: Int = CommentsUseCase.maxAttachments
    var searchUseCase: SearchUseCase? = nil
    var stickersUseCase: StickersUseCase? = nil
    let onCancel: () -> Void
    let onSubmit: () -> Void

    @State private var isPreviewMode = false
    @State private var mentionPicker: MentionPickerModel
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showStickerPicker = false
    @State private var showGIFPicker = false
    @State private var dismissController = KeyboardDismissController()

    init(
        draft: Binding<String>,
        attachments: Binding<[PostAttachment]>,
        pendingSticker: Binding<Sticker?> = .constant(nil),
        pendingGIF: Binding<KlipyGIF?> = .constant(nil),
        isSubmitting: Bool,
        maxAttachments: Int = CommentsUseCase.maxAttachments,
        searchUseCase: SearchUseCase? = nil,
        stickersUseCase: StickersUseCase? = nil,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) {
        _draft = draft
        _attachments = attachments
        _pendingSticker = pendingSticker
        _pendingGIF = pendingGIF
        self.isSubmitting = isSubmitting
        self.maxAttachments = maxAttachments
        self.searchUseCase = searchUseCase
        self.stickersUseCase = stickersUseCase
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        _mentionPicker = State(initialValue: MentionPickerModel(searchUseCase: searchUseCase))
    }

    private var canSubmit: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMedia = !attachments.isEmpty
        let hasSticker = pendingSticker != nil
        let hasGIF = pendingGIF != nil
        return (hasText || hasMedia || hasSticker || hasGIF) && !isSubmitting
    }

    private var remainingSlots: Int {
        max(0, maxAttachments - attachments.count)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownEditorView(
                        text: $draft,
                        isPreviewMode: $isPreviewMode,
                        characterLimit: 2000,
                        editorMinHeight: 240,
                        style: .composer,
                        onPasteImages: { images in
                            let loaded = ComposerPasteAttachments.attachments(
                                from: images,
                                remainingSlots: remainingSlots,
                                filenamePrefix: "comment"
                            )
                            attachments.append(contentsOf: loaded)
                        }
                    )

                    if let pendingSticker {
                        PendingStickerChip(sticker: pendingSticker) {
                            self.pendingSticker = nil
                        }
                    }

                    if let pendingGIF {
                        PendingGIFChip(gif: pendingGIF) {
                            self.pendingGIF = nil
                        }
                    }

                    if !attachments.isEmpty {
                        ComposerAttachmentStrip(
                            attachments: attachments,
                            onRemove: { attachment in
                                attachments.removeAll { $0.id == attachment.id }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if mentionPicker.isVisible {
                    MentionAutocompleteView(users: mentionPicker.users) { user in
                        var text = draft
                        mentionPicker.insert(user, into: &text)
                        draft = text
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .liquidGlassKeyboardDismiss(controller: dismissController, bottomInset: 56)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(ComposerPalette.monochrome.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isPreviewMode ? "Edit" : "Preview") {
                        isPreviewMode.toggle()
                    }
                    .foregroundStyle(ComposerPalette.monochrome.primary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: max(1, remainingSlots),
                        matching: .images
                    ) {
                        Image(systemName: "photo")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(remainingSlots > 0 ? Color.secondary : Color.secondary.opacity(0.35))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(remainingSlots == 0)
                    .accessibilityLabel("Attach photos")

                    Button {
                        showGIFPicker = true
                    } label: {
                        Text("GIF")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("GIF")

                    if let stickersUseCase {
                        Button {
                            showStickerPicker = true
                        } label: {
                            Image(systemName: "face.smiling")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stickers")
                        .sheet(isPresented: $showStickerPicker) {
                            CommentStickerPickerSheet(stickersUseCase: stickersUseCase) { sticker in
                                pendingGIF = nil
                                pendingSticker = sticker
                            }
                        }
                    }

                    Button {
                        var text = draft
                        mentionPicker.showAfterInsertingAt(into: &text)
                        draft = text
                    } label: {
                        Image(systemName: "at")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mention user")

                    Spacer()
                    Button(action: onSubmit) {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Reply")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(minWidth: 72)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(canSubmit ? Color.primary : Color(.systemGray4), in: Capsule())
                        .foregroundStyle(canSubmit ? Color(.systemBackground) : .secondary)
                    }
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .onChange(of: draft) { _, newValue in
                mentionPicker.update(from: newValue)
            }
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadSelectedPhotos(items) }
            }
            .sheet(isPresented: $showGIFPicker) {
                CommentGIFPickerSheet { gif in
                    pendingSticker = nil
                    pendingGIF = gif
                }
            }
        }
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        defer { selectedPhotoItems = [] }
        guard remainingSlots > 0 else { return }
        guard await DevicePermissions.requestPhotoLibraryAccess() else { return }

        var loaded: [PostAttachment] = []
        for item in items.prefix(remainingSlots) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let contentType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let ext = contentType.contains("png") ? "png" : "jpg"
            loaded.append(
                PostAttachment(
                    id: UUID(),
                    data: data,
                    contentType: contentType,
                    filename: "comment-\(UUID().uuidString).\(ext)",
                    pickerItemID: nil
                )
            )
        }
        attachments.append(contentsOf: loaded)
    }
}

/// System sticker pack picker for the take comment composer.
struct CommentStickerPickerSheet: View {
    let stickersUseCase: StickersUseCase
    let onSelect: (Sticker) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StickerPackGridView(stickersUseCase: stickersUseCase) { sticker in
                onSelect(sticker)
                dismiss()
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PendingStickerChip: View {
    let sticker: Sticker
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LazyImage(url: sticker.thumbURL) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.secondary.opacity(0.08)
                }
            }
            .frame(width: 56, height: 56)

            Text(sticker.emojiHint ?? "Sticker")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove sticker")
        }
    }
}

struct PendingGIFChip: View {
    let gif: KlipyGIF
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AnimatedRemoteImage(
                url: gif.previewURL,
                contentMode: .scaleAspectFit,
                maxPixelSize: 160
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(gif.title.isEmpty ? "GIF" : gif.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove GIF")
        }
    }
}

/// Fixed-size sticker bubble for comment threads (Telegram-like).
struct CommentStickerImageView: View {
    let sticker: CommentSticker
    var maxSide: CGFloat = 160
    var accessibilityText: String = "Sticker"

    var body: some View {
        LazyImage(url: sticker.url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFit()
            } else if let thumb = sticker.thumbURL {
                LazyImage(url: thumb) { thumbState in
                    if let image = thumbState.image {
                        image.resizable().scaledToFit()
                    } else {
                        Color.secondary.opacity(0.08)
                    }
                }
            } else {
                Color.secondary.opacity(0.08)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .accessibilityLabel(accessibilityText)
    }

    private var displaySize: CGSize {
        let w = CGFloat(sticker.width ?? Int(maxSide))
        let h = CGFloat(sticker.height ?? Int(maxSide))
        guard w > 0, h > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }
        let scale = min(maxSide / w, maxSide / h, 1)
        return CGSize(width: w * scale, height: h * scale)
    }
}

struct CommentGifImageView: View {
    let gif: CommentGif
    var maxSide: CGFloat = 220

    var body: some View {
        AnimatedRemoteImage(
            url: gif.url,
            contentMode: .scaleAspectFit,
            maxPixelSize: max(maxSide * 2, 440)
        )
        .frame(width: displaySize.width, height: displaySize.height)
        .background(Color.secondary.opacity(0.08))
        .accessibilityLabel("GIF")
    }

    private var displaySize: CGSize {
        let w = CGFloat(gif.width ?? Int(maxSide))
        let h = CGFloat(gif.height ?? Int(maxSide))
        guard w > 0, h > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }
        let scale = min(maxSide / w, maxSide / h, 1)
        return CGSize(width: w * scale, height: h * scale)
    }
}

/// Klipy GIF browser for the take comment composer.
struct CommentGIFPickerSheet: View {
    let onPicked: (KlipyGIF) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            KlipyGIFGridView { gif in
                onPicked(gif)
                dismiss()
            }
            .navigationTitle("GIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
@Observable
final class KlipyGIFCatalog {
    static let shared = KlipyGIFCatalog()

    private(set) var trending: [KlipyGIF] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?

    /// Starts trending outside the view task, so a detent change cannot cancel it
    /// and leave the grid on "No GIFs".
    func ensureTrending() {
        guard trending.isEmpty, task == nil else { return }
        isLoading = true
        errorMessage = nil
        task = Task {
            defer {
                isLoading = false
                task = nil
            }
            do {
                trending = try await KlipyClient.shared.trending()
            } catch is CancellationError {
                return
            } catch {
                if trending.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct KlipyGIFGridView: View {
    let onPicked: (KlipyGIF) -> Void

    @State private var catalog = KlipyGIFCatalog.shared
    @State private var query = ""
    @State private var searchResults: [KlipyGIF]?
    @State private var searchLoading = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @State private var dismissController = KeyboardDismissController()

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        Group {
            if KlipyConfig.apiKey == nil {
                missingKeyView
            } else {
                content
            }
        }
        .liquidGlassKeyboardDismiss(controller: dismissController)
        .onAppear {
            catalog.ensureTrending()
            Task { await GIFAnimateSlots.shared.noteMounted() }
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
    }

    private var missingKeyView: some View {
        ContentUnavailableView(
            "Klipy API key needed",
            systemImage: "key",
            description: Text("Add your key to Info.plist as KlipyAPIKey (partner.klipy.com).")
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search GIFs", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if let errorMessage = activeError, shownGIFs.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            ScrollView {
                if isActiveLoading && shownGIFs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if shownGIFs.isEmpty {
                    ContentUnavailableView(
                        "No GIFs",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Try another search.")
                    )
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(shownGIFs) { gif in
                            Button {
                                select(gif)
                            } label: {
                                KlipyGIFGridCell(gif: gif)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(gif.title.isEmpty ? "GIF" : gif.title)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }

            Text("Powered by KLIPY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shownGIFs: [KlipyGIF] {
        isSearching ? (searchResults ?? []) : catalog.trending
    }

    private var isActiveLoading: Bool {
        isSearching ? searchLoading : catalog.isLoading
    }

    private var activeError: String? {
        isSearching ? searchError : catalog.errorMessage
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = nil
            searchLoading = false
            searchError = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searchLoading = true
            searchError = nil
            do {
                let results = try await KlipyClient.shared.search(query: trimmed)
                guard !Task.isCancelled else { return }
                searchResults = results
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    searchError = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                searchLoading = false
            }
        }
    }

    private func select(_ gif: KlipyGIF) {
        Task { await KlipyClient.shared.registerShare(slug: gif.slug) }
        onPicked(gif)
    }
}

/// When false, grid cells stop starting and decoding animations so a tab tap is not stuck in ImageIO.
enum GIFThumbGate {
    private static let lock = NSLock()
    private static var allowed = true

    static var allowsDecode: Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowed
    }

    static func setAllowed(_ value: Bool) {
        lock.lock()
        allowed = value
        lock.unlock()
    }
}

/// Caps how many grid cells hold an AVPlayer at once.
actor GIFAnimateSlots {
    static let shared = GIFAnimateSlots()

    private let limit = 4
    private let rampLimit = 2
    private var rampUntil: Date?
    private var inUse = 0
    private var nextTicket = 0
    private var held: Set<Int> = []
    private var cancelledIDs: Set<UUID> = []
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Int?, Never>)] = []

    /// First 600ms after the grid appears, only two players start.
    func noteMounted() {
        rampUntil = Date().addingTimeInterval(0.6)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await self.openRamp()
        }
    }

    func acquire() async -> Int? {
        let id = UUID()
        return await withTaskCancellationHandler {
            await beginWait(id)
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func release(_ ticket: Int) {
        guard held.remove(ticket) != nil else { return }
        if inUse > 0 { inUse -= 1 }
        resumeNext()
    }

    /// Drops cells still waiting for a player slot.
    func stop() {
        rampUntil = nil
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.continuation.resume(returning: nil) }
    }

    private var effectiveLimit: Int {
        if let rampUntil, Date() < rampUntil {
            return rampLimit
        }
        return limit
    }

    private func openRamp() {
        guard GIFThumbGate.allowsDecode else { return }
        rampUntil = nil
        while inUse < limit, !waiters.isEmpty {
            resumeNext()
        }
    }

    private func beginWait(_ id: UUID) async -> Int? {
        if cancelledIDs.remove(id) != nil || Task.isCancelled || !GIFThumbGate.allowsDecode {
            return nil
        }
        if inUse < effectiveLimit {
            return makeTicket()
        }
        return await withCheckedContinuation { continuation in
            if cancelledIDs.remove(id) != nil || !GIFThumbGate.allowsDecode {
                continuation.resume(returning: nil)
                return
            }
            waiters.append((id, continuation))
        }
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).continuation.resume(returning: nil)
        } else {
            cancelledIDs.insert(id)
        }
    }

    private func resumeNext() {
        guard GIFThumbGate.allowsDecode, inUse < effectiveLimit, !waiters.isEmpty else { return }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume(returning: makeTicket())
    }

    private func makeTicket() -> Int {
        inUse += 1
        nextTicket += 1
        held.insert(nextTicket)
        return nextTicket
    }
}

private struct KlipyGIFGridCell: View {
    let gif: KlipyGIF

    @State private var blur: UIImage?
    @State private var play = false
    @State private var ticket: Int?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let blur {
                Image(uiImage: blur)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let stillURL = gif.stillURL {
                LazyImage(url: stillURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            if play, let videoURL = gif.gridVideoURL {
                GIFLoopVideoView(url: videoURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: gif.id) {
            await decodeBlurIfNeeded()
            // Let stills paint and the tab stay interactive before AVPlayers start.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard gif.gridVideoURL != nil else { return }
            guard GIFThumbGate.allowsDecode else { return }
            guard let ticket = await GIFAnimateSlots.shared.acquire() else { return }
            guard !Task.isCancelled, GIFThumbGate.allowsDecode else {
                await GIFAnimateSlots.shared.release(ticket)
                return
            }
            self.ticket = ticket
            play = true
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func decodeBlurIfNeeded() async {
        guard blur == nil, let data = gif.blurPreview else { return }
        let image = await Task.detached(priority: .utility) {
            UIImage(data: data)
        }.value
        guard !Task.isCancelled else { return }
        blur = image
    }

    private func stopPlayback() {
        play = false
        guard let ticket else { return }
        self.ticket = nil
        Task { await GIFAnimateSlots.shared.release(ticket) }
    }
}
