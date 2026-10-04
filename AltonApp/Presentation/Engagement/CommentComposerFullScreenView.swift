import SwiftUI
import PhotosUI
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
                        style: .composer
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
            .liquidGlassKeyboardDismiss(controller: dismissController)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isPreviewMode ? "Edit" : "Preview") {
                        isPreviewMode.toggle()
                    }
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

    @State private var packs: [StickerPackSummary] = []
    @State private var selectedPackID: String?
    @State private var detail: StickerPackDetail?
    @State private var isLoadingPacks = false
    @State private var isLoadingDetail = false
    @State private var errorMessage: String?
    @State private var packLoadTask: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingPacks && packs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, packs.isEmpty {
                    ContentUnavailableView(
                        "Stickers unavailable",
                        systemImage: "face.smiling",
                        description: Text(errorMessage)
                    )
                } else if packs.isEmpty {
                    ContentUnavailableView(
                        "No stickers yet",
                        systemImage: "face.smiling",
                        description: Text("Published packs will show up here.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadPacks() }
            .onChange(of: selectedPackID) { _, newID in
                guard let newID else { return }
                packLoadTask?.cancel()
                packLoadTask = Task { await loadPack(id: newID) }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { packLoadTask?.cancel() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(packs) { pack in
                        Button {
                            selectedPackID = pack.id
                        } label: {
                            Text(pack.title)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedPackID == pack.id
                                        ? Color.primary.opacity(0.12)
                                        : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()

            if isLoadingDetail && detail == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(detail.stickers) { sticker in
                            Button {
                                onSelect(sticker)
                                dismiss()
                            } label: {
                                LazyImage(url: sticker.thumbURL) { state in
                                    if let image = state.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        Color.secondary.opacity(0.08)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .padding(6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sticker.emojiHint ?? "Sticker")
                        }
                    }
                    .padding(16)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadPacks() async {
        guard !isLoadingPacks else { return }
        isLoadingPacks = true
        errorMessage = nil
        defer { isLoadingPacks = false }
        do {
            let loaded = try await stickersUseCase.fetchPacks()
            packs = loaded
            if selectedPackID == nil {
                selectedPackID = loaded.first?.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadPack(id: String) async {
        isLoadingDetail = true
        errorMessage = nil
        defer { isLoadingDetail = false }
        do {
            let loaded = try await stickersUseCase.fetchPack(id: id)
            if Task.isCancelled { return }
            detail = loaded
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            detail = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
            LazyImage(url: gif.previewURL) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.secondary.opacity(0.08)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        LazyImage(url: gif.url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.08)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
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

    @State private var query = ""
    @State private var gifs: [KlipyGIF] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @State private var dismissController = KeyboardDismissController()

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if KlipyConfig.apiKey == nil {
                    missingKeyView
                } else {
                    content
                }
            }
            .navigationTitle("GIF")
            .navigationBarTitleDisplayMode(.inline)
            .liquidGlassKeyboardDismiss(controller: dismissController)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadTrending()
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(newValue)
            }
        }
        .presentationDetents([.medium, .large])
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            ScrollView {
                if isLoading && gifs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if gifs.isEmpty {
                    ContentUnavailableView(
                        "No GIFs",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Try another search.")
                    )
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(gifs) { gif in
                            Button {
                                select(gif)
                            } label: {
                                LazyImage(url: gif.previewURL) { state in
                                    ZStack {
                                        Color(.tertiarySystemFill)
                                        if let image = state.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } else if state.isLoading {
                                            ProgressView()
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load(query: text)
        }
    }

    private func loadTrending() async {
        await load(query: "")
    }

    private func load(query: String) async {
        guard KlipyConfig.apiKey != nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let results = try await KlipyClient.shared.search(query: query)
            guard !Task.isCancelled else { return }
            gifs = results
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ gif: KlipyGIF) {
        Task { await KlipyClient.shared.registerShare(slug: gif.slug) }
        onPicked(gif)
        dismiss()
    }
}
