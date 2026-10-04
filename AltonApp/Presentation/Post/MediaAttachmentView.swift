import SwiftUI
import NukeUI

/// Compact horizontal thumbnails for the take composer (not the feed-sized carousel).
struct ComposerAttachmentStrip: View {
    let attachments: [PostAttachment]
    var remainingSlots: Int = 0
    var onRemove: (PostAttachment) -> Void
    var onEdit: ((PostAttachment) -> Void)? = nil
    var onAddPhotos: (() -> Void)? = nil
    /// Drag-and-drop reorder (`from`, `to` indices). Nil disables dragging.
    /// The owner applies it with `AttachmentReorder.move` to its own attachments storage.
    var onMove: ((Int, Int) -> Void)? = nil
    /// `.legacy` keeps the original look for comment/reply composers; only the take composer opts into `.takeComposer`.
    var style: AttachmentStripStyle = .legacy

    private let thumbSize: CGFloat = 88

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    ComposerAttachmentThumb(
                        attachment: attachment,
                        size: thumbSize,
                        onRemove: { onRemove(attachment) },
                        onEdit: attachment.playsAsAnimation ? nil : { onEdit?(attachment) },
                        style: style
                    )
                    .reorderable(index: index, onMove: onMove)
                }

                if remainingSlots > 0, let onAddPhotos {
                    Button(action: onAddPhotos) {
                        addTile
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add photos")
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var addTile: some View {
        switch style {
        case .legacy:
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                Text("Add")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .frame(width: thumbSize, height: thumbSize)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .takeComposer:
            VStack(spacing: 6) {
                AttachmentStripGlyph(kind: .plus)
                    .stroke(AttachmentStripTokens.addForeground, style: AttachmentStripTokens.glyphStroke)
                    .frame(width: 22, height: 22)
                Text("Add")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AttachmentStripTokens.addForeground)
            }
            .frame(width: thumbSize, height: thumbSize)
            .background(
                AttachmentStripTokens.addBackground,
                in: RoundedRectangle(cornerRadius: AttachmentStripTokens.cornerRadius, style: .continuous)
            )
        }
    }
}

/// Visual treatment of `ComposerAttachmentStrip`.
enum AttachmentStripStyle: Equatable {
    /// Original thumbs (comment/reply composers).
    case legacy
    /// Take-composer redesign.
    case takeComposer
}

private struct ComposerAttachmentThumb: View {
    let attachment: PostAttachment
    let size: CGFloat
    let onRemove: () -> Void
    var onEdit: (() -> Void)? = nil
    var style: AttachmentStripStyle = .legacy

    @State private var decodedImage: UIImage?
    @State private var gifTempURL: URL?
    @State private var gifTooLarge = false

    private var cornerRadius: CGFloat {
        style == .legacy ? 12 : AttachmentStripTokens.cornerRadius
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if gifTooLarge {
                    Color(.tertiarySystemFill)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                } else if attachment.playsAsAnimation, let url = gifTempURL {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            ProgressView()
                        }
                    }
                } else if let uiImage = decodedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.tertiarySystemFill)
                        .overlay { ProgressView() }
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit?()
            }

            if attachment.playsAsAnimation {
                Text("GIF")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
                    .allowsHitTesting(false)
            }

            removeButton
        }
        .frame(width: size, height: size)
        .task(id: attachment.id) {
            await preparePreview()
        }
    }

    private var borderColor: Color {
        style == .legacy ? Color(.separator).opacity(0.45) : AttachmentStripTokens.border
    }

    @ViewBuilder
    private var removeButton: some View {
        switch style {
        case .legacy:
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove photo")
        case .takeComposer:
            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(AttachmentStripTokens.removeBackground)
                        .overlay(Circle().strokeBorder(AttachmentStripTokens.border, lineWidth: 0.5))
                    AttachmentStripGlyph(kind: .xmark)
                        .stroke(AttachmentStripTokens.removeForeground, style: AttachmentStripTokens.glyphStroke)
                        .padding(5)
                }
                .frame(width: 18, height: 18)
                // Keep a comfortable touch target around the small circle.
                .padding(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel("Remove photo")
        }
    }

    @MainActor
    private func preparePreview() async {
        cleanupTempGIF()
        gifTooLarge = false
        decodedImage = nil

        if attachment.playsAsAnimation {
            guard attachment.data.count <= CreatePostViewModel.maxGIFBytes else {
                gifTooLarge = true
                return
            }
            let ext = attachment.isGIF ? "gif" : "webp"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(attachment.id.uuidString)-thumb.\(ext)")
            do {
                try attachment.data.write(to: url, options: .atomic)
                gifTempURL = url
            } catch {
                gifTempURL = nil
            }
            return
        }

        decodedImage = await Task.detached(priority: .userInitiated) {
            DownsampledImage.make(data: attachment.data, maxPixelSize: 240)
        }.value
    }

    private func cleanupTempGIF() {
        guard let gifTempURL else { return }
        try? FileManager.default.removeItem(at: gifTempURL)
        self.gifTempURL = nil
    }
}

// MARK: - Reorder

/// Pure helpers for reordering/removing attachments (testable without UI).
enum AttachmentReorder {
    /// Removes the element at `from` and inserts it at `to`.
    /// Out-of-bounds indices return `items` unchanged.
    static func move<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return items }
        var result = items
        let element = result.remove(at: from)
        result.insert(element, at: to)
        return result
    }

    /// Removes the element at `index`. Out-of-bounds returns `items` unchanged.
    static func remove<T>(_ items: [T], at index: Int) -> [T] {
        guard items.indices.contains(index) else { return items }
        var result = items
        result.remove(at: index)
        return result
    }

    /// Drag payload for a thumb index. Prefixed so unrelated dropped text is never read as an index.
    private static let payloadPrefix = "alton.attachment-index:"

    static func payload(forIndex index: Int) -> String { payloadPrefix + String(index) }

    static func index(fromPayload payload: String) -> Int? {
        guard payload.hasPrefix(payloadPrefix) else { return nil }
        return Int(payload.dropFirst(payloadPrefix.count))
    }
}

private extension View {
    /// Adds `.draggable` + `.dropDestination` index-based reorder when `onMove` is set.
    @ViewBuilder
    func reorderable(index: Int, onMove: ((Int, Int) -> Void)?) -> some View {
        if let onMove {
            self
                .draggable(AttachmentReorder.payload(forIndex: index))
                .dropDestination(for: String.self) { payloads, _ in
                    guard let payload = payloads.first,
                          let from = AttachmentReorder.index(fromPayload: payload)
                    else { return false }
                    onMove(from, index)
                    return true
                }
        } else {
            self
        }
    }
}

// MARK: - Style

/// `.takeComposer` strip tokens — colors come from `ComposerPalette.monochrome`; `.legacy` keeps its own system colors.
private enum AttachmentStripTokens {
    static let cornerRadius: CGFloat = 8
    static let border = ComposerPalette.monochrome.divider
    static let addBackground = ComposerPalette.monochrome.activeFill
    static let addForeground = ComposerPalette.monochrome.muted
    static let removeForeground = ComposerPalette.monochrome.primary
    static let removeBackground = ComposerPalette.monochrome.onPrimary
    static let glyphStroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
}

/// Outline `xmark` / `plus` matching the `ComposerIcon` stroke style (no fill).
private struct AttachmentStripGlyph: Shape {
    enum Kind { case xmark, plus }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.2)
        switch kind {
        case .xmark:
            p.move(to: CGPoint(x: inset.minX, y: inset.minY))
            p.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            p.move(to: CGPoint(x: inset.maxX, y: inset.minY))
            p.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
        case .plus:
            p.move(to: CGPoint(x: inset.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: inset.maxX, y: rect.midY))
            p.move(to: CGPoint(x: rect.midX, y: inset.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: inset.maxY))
        }
        return p
    }
}

/// Composer preview of selected photos — Instagram-style carousel matching feed cards.
struct MediaAttachmentView: View {
    let attachments: [PostAttachment]
    let onRemove: (PostAttachment) -> Void

    @State private var pageIndex = 0
    @State private var currentPageID: PostAttachment.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PagingCarousel(items: attachments, pageIndex: $pageIndex) { attachment in
                ComposerAttachmentPage(
                    attachment: attachment,
                    onRemove: { onRemove(attachment) }
                )
            }
            .postMediaFrame()
            .clipShape(RoundedRectangle(cornerRadius: PostImageCarouselView.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PostImageCarouselView.cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.45), lineWidth: 0.5)
            }

            if attachments.count > 1 {
                Text("\(pageIndex + 1)/\(attachments.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            syncPageIdentity(preserving: currentPageID)
        }
        .onChange(of: pageIndex) { _, newIndex in
            if attachments.indices.contains(newIndex) {
                currentPageID = attachments[newIndex].id
            }
        }
        .onChange(of: attachments.map(\.id)) { _, ids in
            syncPageIdentity(preserving: currentPageID, ids: ids)
        }
    }

    private func syncPageIdentity(preserving previousID: PostAttachment.ID?, ids: [PostAttachment.ID]? = nil) {
        let idList = ids ?? attachments.map(\.id)
        guard !idList.isEmpty else {
            pageIndex = 0
            currentPageID = nil
            return
        }
        if let previousID, let index = idList.firstIndex(of: previousID) {
            pageIndex = index
            currentPageID = previousID
            return
        }
        let clamped = min(pageIndex, idList.count - 1)
        pageIndex = max(0, clamped)
        currentPageID = idList[pageIndex]
    }
}

private struct ComposerAttachmentPage: View {
    let attachment: PostAttachment
    let onRemove: () -> Void

    @State private var decodedImage: UIImage?
    @State private var gifTempURL: URL?
    @State private var gifTooLarge = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if gifTooLarge {
                    Color(.tertiarySystemFill)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                Text("GIF too large")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                        }
                } else if attachment.playsAsAnimation, let url = gifTempURL {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            ProgressView()
                        }
                    }
                } else if let uiImage = decodedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.tertiarySystemFill)
                        .overlay { ProgressView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            }
            .padding(12)
            .accessibilityLabel("Remove photo")
        }
        .task(id: attachment.id) {
            await preparePreview()
        }
        // Temp GIF cleanup happens in preparePreview on id change; skip onDisappear
        // to avoid LazyHStack recycle flicker.
    }

    @MainActor
    private func preparePreview() async {
        cleanupTempGIF()
        gifTooLarge = false
        decodedImage = nil

        if attachment.playsAsAnimation {
            guard attachment.data.count <= CreatePostViewModel.maxGIFBytes else {
                gifTooLarge = true
                return
            }
            let ext = attachment.isGIF ? "gif" : "webp"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(attachment.id.uuidString).\(ext)")
            do {
                try attachment.data.write(to: url, options: .atomic)
                gifTempURL = url
            } catch {
                gifTempURL = nil
            }
            return
        }

        decodedImage = await Task.detached(priority: .userInitiated) {
            DownsampledImage.make(data: attachment.data, maxPixelSize: 720)
        }.value
    }

    private func cleanupTempGIF() {
        guard let gifTempURL else { return }
        try? FileManager.default.removeItem(at: gifTempURL)
        self.gifTempURL = nil
    }
}

/// Instagram-style image carousel for take posts in feed / detail.
/// When engagement context is provided, tapping an image opens a video-like immersive viewer
/// with like / comment / share.
struct PostImageCarouselView: View {
    let urls: [URL]
    var post: Post?
    var currentUser: User?
    var engagementController: PostEngagementController?
    var commentsViewModelFactory: ((Post) -> CommentsViewModel)?
    var session: AuthSession?
    var container: DependencyContainer?
    var onPostChange: ((Post) -> Void)?

    static let aspectRatio: CGFloat = 4.0 / 5.0
    static let cornerRadius: CGFloat = 12

    @State private var pageIndex = 0
    @State private var lightboxItem: LightboxItem?

    private var identifiedURLs: [IdentifiedURL] {
        urls.enumerated().map { IdentifiedURL(id: "\($0.offset)-\($0.element.absoluteString)", url: $0.element, index: $0.offset) }
    }

    var body: some View {
        Group {
            if urls.isEmpty {
                EmptyView()
            } else if urls.count == 1, let url = urls.first {
                singleImage(url, index: 0)
            } else {
                multiImageCarousel
            }
        }
        .fullScreenCover(item: $lightboxItem) { item in
            if let post,
               let engagementController,
               let commentsViewModelFactory {
                ImageImmersiveViewer(
                    urls: urls,
                    initialIndex: item.index,
                    post: post,
                    currentUser: currentUser,
                    engagementController: engagementController,
                    commentsViewModelFactory: commentsViewModelFactory,
                    session: session,
                    container: container,
                    onPostChange: { onPostChange?($0) }
                )
            } else {
                ImageLightboxView(urls: urls, initialIndex: item.index)
            }
        }
    }

    private func singleImage(_ url: URL, index: Int) -> some View {
        Color(.tertiarySystemFill)
            .postMediaFrame()
            .overlay {
                carouselImage(url, resizeWidth: 1080)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .onTapGesture {
                lightboxItem = LightboxItem(id: url.absoluteString, index: index)
            }
    }

    private var multiImageCarousel: some View {
        ZStack(alignment: .topTrailing) {
            PagingCarousel(items: identifiedURLs, pageIndex: $pageIndex) { item in
                carouselImage(item.url, resizeWidth: 1080)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        lightboxItem = LightboxItem(id: item.id, index: item.index)
                    }
            }
            .postMediaFrame()
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            }

            Text("\(pageIndex + 1)/\(urls.count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(10)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func carouselImage(_ url: URL, resizeWidth: CGFloat) -> some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFill()
            } else if state.error != nil {
                mediaPlaceholder
            } else {
                Color(.tertiarySystemFill)
                    .overlay { ProgressView() }
            }
        }
        .processors([.resize(width: resizeWidth)])
        // Fill the fixed media frame — do not contribute intrinsic image size to layout.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
    }

    private var mediaPlaceholder: some View {
        Color(.tertiarySystemFill)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}

/// Fixed 4:5 media box that never expands past the post column width.
private extension View {
    func postMediaFrame() -> some View {
        self
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(PostImageCarouselView.aspectRatio, contentMode: .fit)
    }
}

/// Horizontal paging carousel keyed by stable item identity (avoids @State reuse bugs).
/// Page width comes from the laid-out bounds (parent must apply `.postMediaFrame()`).
private struct PagingCarousel<Item: Identifiable, Page: View>: View {
    let items: [Item]
    @Binding var pageIndex: Int
    @ViewBuilder let page: (Item) -> Page

    var body: some View {
        GeometryReader { geo in
            let pageWidth = max(geo.size.width, 1)
            let pageHeight = max(geo.size.height, 1)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                        page(item)
                            .frame(width: pageWidth, height: pageHeight)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: scrollPositionBinding)
        }
    }

    private var scrollPositionBinding: Binding<Item.ID?> {
        Binding(
            get: {
                guard items.indices.contains(pageIndex) else { return nil }
                return items[pageIndex].id
            },
            set: { newID in
                guard let newID,
                      let index = items.firstIndex(where: { $0.id == newID })
                else { return }
                pageIndex = index
            }
        )
    }
}

/// Backward-compatible alias used across feed / detail / reply.
typealias TakeMediaGridView = PostImageCarouselView

private struct IdentifiedURL: Identifiable, Hashable {
    let id: String
    let url: URL
    let index: Int
}

struct LightboxItem: Identifiable, Hashable {
    let id: String
    let index: Int
}

/// Plain media-only lightbox (composer / no engagement context).
struct ImageLightboxView: View {
    let urls: [URL]
    var thumbnailURLs: [URL] = []
    var blurFlags: [Bool]? = nil
    var unknownFlags: [Bool]? = nil
    let initialIndex: Int

    @State private var pageIndex: Int
    @State private var zoomedPageIndex: Int?
    @State private var dismissDrag = LightboxDismissDrag()
    @Environment(\.dismiss) private var dismiss

    init(
        urls: [URL],
        thumbnailURLs: [URL] = [],
        blurFlags: [Bool]? = nil,
        unknownFlags: [Bool]? = nil,
        initialIndex: Int
    ) {
        self.urls = urls
        self.thumbnailURLs = thumbnailURLs
        self.blurFlags = blurFlags
        self.unknownFlags = unknownFlags
        self.initialIndex = initialIndex
        _pageIndex = State(initialValue: initialIndex)
    }

    private var identifiedURLs: [IdentifiedURL] {
        urls.enumerated().map { IdentifiedURL(id: "\($0.offset)-\($0.element.absoluteString)", url: $0.element, index: $0.offset) }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .opacity(dismissDrag.backgroundOpacity)
                    .ignoresSafeArea()

                PagingCarousel(items: identifiedURLs, pageIndex: $pageIndex) { item in
                    SensitiveMediaOverlay(
                        isSensitive: (blurFlags?[item.index] ?? false)
                            || (unknownFlags?[item.index] ?? false),
                        allowsReveal: !(unknownFlags?[item.index] ?? false)
                    ) {
                        ZoomableRemoteImage(
                            url: item.url,
                            thumbnailURL: thumbnailURLs.indices.contains(item.index) ? thumbnailURLs[item.index] : nil,
                            isCurrentPage: pageIndex == item.index,
                            onZoomChange: { zoomed in
                                if zoomed {
                                    zoomedPageIndex = item.index
                                } else if zoomedPageIndex == item.index {
                                    zoomedPageIndex = nil
                                }
                            }
                        )
                        .id(item.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDisabled(zoomedPageIndex != nil || dismissDrag.isLocked || dismissDrag.isDismissing)
                .offset(y: dismissDrag.offset)
                .scaleEffect(dismissDrag.scale)
                .clipShape(RoundedRectangle(cornerRadius: dismissDrag.cornerRadius, style: .continuous))

                VStack {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    Spacer()
                    if urls.count > 1 {
                        pageCounter
                            .padding(.bottom, 28)
                    }
                }
                .opacity(dismissDrag.chromeOpacity)
                .allowsHitTesting(!dismissDrag.isDismissing && dismissDrag.progress < 0.2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .lightboxSwipeDismiss(
                drag: $dismissDrag,
                isEnabled: zoomedPageIndex == nil && !dismissDrag.isDismissing,
                screenHeight: geo.size.height,
                onDismiss: { LightboxDismissMotion.dismissCover(dismiss) }
            )
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .presentationBackground(.clear)
        .onChange(of: pageIndex) { _, _ in
            zoomedPageIndex = nil
        }
    }

    private var closeButton: some View {
        Button {
            closeAnimated()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .white.opacity(0.25))
        }
        .accessibilityLabel("Close")
        .padding()
    }

    private var pageCounter: some View {
        Text("\(pageIndex + 1) / \(urls.count)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
    }

    private func closeAnimated() {
        LightboxDismissMotion.animateAway(
            drag: $dismissDrag,
            direction: 1,
            screenHeight: UIScreen.main.bounds.height,
            onFinished: { LightboxDismissMotion.dismissCover(dismiss) }
        )
    }
}

/// Full-screen image viewer styled like the video feed (author + vertical action rail).
struct ImageImmersiveViewer: View {
    let urls: [URL]
    var thumbnailURLs: [URL] = []
    var blurFlags: [Bool]? = nil
    var unknownFlags: [Bool]? = nil
    let initialIndex: Int
    let currentUser: User?
    @Bindable var engagementController: PostEngagementController
    let commentsViewModelFactory: (Post) -> CommentsViewModel
    var session: AuthSession?
    var container: DependencyContainer?
    var onPostChange: (Post) -> Void

    @State private var post: Post
    @State private var pageIndex: Int
    @State private var zoomedPageIndex: Int?
    @State private var showShareSheet = false
    @State private var commentsPresentation: ShotCommentsPresentation?
    @State private var likeBurst = false
    @State private var dismissDrag = LightboxDismissDrag()
    @Environment(\.dismiss) private var dismiss

    init(
        urls: [URL],
        thumbnailURLs: [URL] = [],
        blurFlags: [Bool]? = nil,
        unknownFlags: [Bool]? = nil,
        initialIndex: Int,
        post: Post,
        currentUser: User?,
        engagementController: PostEngagementController,
        commentsViewModelFactory: @escaping (Post) -> CommentsViewModel,
        session: AuthSession?,
        container: DependencyContainer?,
        onPostChange: @escaping (Post) -> Void
    ) {
        self.urls = urls
        self.thumbnailURLs = thumbnailURLs
        self.blurFlags = blurFlags
        self.unknownFlags = unknownFlags
        self.initialIndex = initialIndex
        self.currentUser = currentUser
        self.engagementController = engagementController
        self.commentsViewModelFactory = commentsViewModelFactory
        self.session = session
        self.container = container
        self.onPostChange = onPostChange
        _post = State(initialValue: post)
        _pageIndex = State(initialValue: initialIndex)
    }

    private var identifiedURLs: [IdentifiedURL] {
        urls.enumerated().map { IdentifiedURL(id: "\($0.offset)-\($0.element.absoluteString)", url: $0.element, index: $0.offset) }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .opacity(dismissDrag.backgroundOpacity)
                    .ignoresSafeArea()

                ZStack {
                    PagingCarousel(items: identifiedURLs, pageIndex: $pageIndex) { item in
                        SensitiveMediaOverlay(
                            isSensitive: (blurFlags?[item.index] ?? false)
                                || (unknownFlags?[item.index] ?? false),
                            allowsReveal: !(unknownFlags?[item.index] ?? false)
                        ) {
                            ZoomableRemoteImage(
                                url: item.url,
                                thumbnailURL: thumbnailURLs.indices.contains(item.index) ? thumbnailURLs[item.index] : nil,
                                isCurrentPage: pageIndex == item.index,
                                doubleTapZooms: false,
                                onZoomChange: { zoomed in
                                    if zoomed {
                                        zoomedPageIndex = item.index
                                    } else if zoomedPageIndex == item.index {
                                        zoomedPageIndex = nil
                                    }
                                },
                                onDoubleTap: {
                                    Task { await toggleLike(burst: true) }
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollDisabled(
                        zoomedPageIndex != nil
                            || commentsPresentation != nil
                            || dismissDrag.isLocked
                            || dismissDrag.isDismissing
                    )

                    if likeBurst {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 88, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                            .transition(.scale.combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
                .offset(y: dismissDrag.offset)
                .scaleEffect(dismissDrag.scale)
                .clipShape(RoundedRectangle(cornerRadius: dismissDrag.cornerRadius, style: .continuous))

                immersiveChrome
                    .opacity(commentsPresentation == nil ? dismissDrag.chromeOpacity : 0)
                    .allowsHitTesting(
                        commentsPresentation == nil
                            && !dismissDrag.isDismissing
                            && dismissDrag.progress < 0.2
                    )

                if let commentsPresentation {
                    ShotCommentsSheet(
                        viewModel: commentsPresentation.viewModel,
                        commentCount: commentsPresentation.commentCount,
                        currentUser: currentUser,
                        searchUseCase: container?.searchUseCase,
                        session: session,
                        container: container,
                        onDismiss: { self.commentsPresentation = nil },
                        onCommentAdded: { _ in
                            self.commentsPresentation?.commentCount += 1
                            post.commentCount += 1
                            onPostChange(post)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .lightboxSwipeDismiss(
                drag: $dismissDrag,
                isEnabled: zoomedPageIndex == nil
                    && commentsPresentation == nil
                    && !dismissDrag.isDismissing,
                screenHeight: geo.size.height,
                onDismiss: { LightboxDismissMotion.dismissCover(dismiss) }
            )
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .presentationBackground(.clear)
        .onChange(of: pageIndex) { _, _ in
            zoomedPageIndex = nil
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = engagementController.shareURL {
                ActivityShareSheet(items: [url]) { completed in
                    showShareSheet = false
                    if completed {
                        Task {
                            post = await engagementController.completeShare(post: post)
                            onPostChange(post)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var immersiveChrome: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Button {
                closeAnimated()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.25))
            }
            .accessibilityLabel("Close")
            .padding()

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            UserAvatarView(
                                user: User(
                                    id: post.creatorID,
                                    username: post.creatorUsername ?? "",
                                    displayName: post.resolvedCreatorDisplayName(currentUser: currentUser),
                                    bio: nil,
                                    avatarURL: post.resolvedCreatorAvatarURL(currentUser: currentUser),
                                    suiWallet: nil,
                                    createdAt: nil
                                ),
                                size: 40
                            )
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))

                            UserHandleLabel(
                                displayName: post.resolvedCreatorDisplayName(currentUser: currentUser),
                                atUsername: post.resolvedAtUsername(currentUser: currentUser),
                                font: .headline
                            )
                            .foregroundStyle(.white)
                        }

                        if let content = post.content, !content.isEmpty {
                            Text(content)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(3)
                        }

                        if urls.count > 1 {
                            Text("\(pageIndex + 1) / \(urls.count)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 28)

                    Spacer(minLength: 0)

                    VStack(spacing: 20) {
                        PostContextMenuButton(
                            post: post,
                            iconColor: .white,
                            shotFeedStyle: true,
                            onBookmark: {
                                Task {
                                    post = await engagementController.toggleBookmark(for: post)
                                    onPostChange(post)
                                }
                            },
                            onRepost: {
                                Task {
                                    post = await engagementController.toggleRepost(for: post)
                                    onPostChange(post)
                                }
                            },
                            onCopy: {}
                        )

                        PostActionBar(
                            post: post,
                            layout: .vertical,
                            shotFeedStyle: true,
                            onLike: { Task { await toggleLike(burst: false) } },
                            onComment: { openComments() },
                            onShare: {
                                Task {
                                    if await engagementController.prepareShare(postID: post.id) {
                                        showShareSheet = true
                                    }
                                }
                            }
                        )
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 36)
                }
            }
        }
    }

    private func closeAnimated() {
        LightboxDismissMotion.animateAway(
            drag: $dismissDrag,
            direction: 1,
            screenHeight: UIScreen.main.bounds.height,
            onFinished: { LightboxDismissMotion.dismissCover(dismiss) }
        )
    }

    private func openComments() {
        guard commentsPresentation == nil else { return }
        commentsPresentation = ShotCommentsPresentation(
            postID: post.id,
            commentCount: post.commentCount,
            viewModel: commentsViewModelFactory(post)
        )
    }

    private func toggleLike(burst: Bool) async {
        let wasLiked = post.isLiked
        post = await engagementController.toggleLike(for: post)
        onPostChange(post)
        if burst, !wasLiked, post.isLiked {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                likeBurst = true
            }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.2)) {
                likeBurst = false
            }
        }
    }
}

private struct ZoomableRemoteImage: View {
    let url: URL
    var thumbnailURL: URL? = nil
    let isCurrentPage: Bool
    var doubleTapZooms: Bool = true
    var onZoomChange: (Bool) -> Void
    var onDoubleTap: (() -> Void)?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var hasFullImage = false
    @State private var imageAspect: CGFloat?

    private var placeholderURL: URL? {
        guard let thumbnailURL, thumbnailURL != url else { return nil }
        return thumbnailURL
    }

    private var isAnimated: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "gif" || ext == "webp"
    }

    var body: some View {
        fitted
            .onChange(of: isCurrentPage) { _, current in
            guard !current else { return }
            scale = 1
            lastScale = 1
            onZoomChange(false)
        }
        .onChange(of: url) { _, _ in
            hasFullImage = false
            imageAspect = nil
        }
    }

    private var imageStack: some View {
        ZStack {
            if let placeholderURL, !isAnimated {
                LazyImage(url: placeholderURL) { state in
                    if let image = state.image, !hasFullImage {
                        zoomable(image, pixelSize: state.imageContainer?.image.size)
                    }
                }
                .processors([.resize(width: 512)])
            }

            LazyImage(url: url) { state in
                if let image = state.image {
                    zoomable(image, pixelSize: state.imageContainer?.image.size)
                        .onAppear { hasFullImage = true }
                } else if placeholderURL == nil || isAnimated {
                    ProgressView()
                        .tint(.white)
                }
            }
            .processors(isAnimated ? [] : [.resize(width: 1600)])
        }
    }

    @ViewBuilder
    private var fitted: some View {
        if let imageAspect, imageAspect > 0 {
            imageStack.aspectRatio(imageAspect, contentMode: .fit)
        } else {
            imageStack
        }
    }

    private func rememberAspect(_ pixelSize: CGSize?) {
        guard let pixelSize, pixelSize.width > 0, pixelSize.height > 0 else { return }
        let next = pixelSize.width / pixelSize.height
        if imageAspect != next {
            imageAspect = next
        }
    }

    private func zoomable(_ image: Image, pixelSize: CGSize?) -> some View {
        image
            .resizable()
            .scaledToFit()
            .onAppear { rememberAspect(pixelSize) }
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        guard isCurrentPage else { return }
                        scale = max(1, min(lastScale * value.magnification, 4))
                        onZoomChange(scale > 1.05)
                    }
                    .onEnded { _ in
                        guard isCurrentPage else { return }
                        lastScale = scale
                        if scale < 1.05 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scale = 1
                                lastScale = 1
                            }
                            onZoomChange(false)
                        } else {
                            onZoomChange(true)
                        }
                    }
            )
            .onTapGesture(count: 2) {
                guard isCurrentPage else { return }
                if doubleTapZooms {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if scale > 1.05 {
                            scale = 1
                            lastScale = 1
                            onZoomChange(false)
                        } else {
                            scale = 2.2
                            lastScale = 2.2
                            onZoomChange(true)
                        }
                    }
                } else {
                    onDoubleTap?()
                }
            }
    }
}

private struct LightboxDismissDrag: Equatable {
    var offset: CGFloat = 0
    var isLocked = false
    var isDismissing = false

    private static let fadeDistance: CGFloat = 280

    var progress: CGFloat {
        min(abs(offset) / Self.fadeDistance, 1)
    }

    var backgroundOpacity: Double {
        max(0, 1 - Double(progress) * 0.88)
    }

    var chromeOpacity: Double {
        max(0, 1 - Double(progress) * 1.45)
    }

    var scale: CGFloat {
        max(0.84, 1 - progress * 0.16)
    }

    var cornerRadius: CGFloat {
        22 * progress
    }
}

private enum LightboxDismissMotion {
    static let distanceThreshold: CGFloat = 120
    static let predictedThreshold: CGFloat = 220
    static let velocityThreshold: CGFloat = 900

    static func shouldDismiss(translation: CGFloat, predicted: CGFloat, velocity: CGFloat) -> Bool {
        abs(translation) > distanceThreshold
            || abs(predicted) > predictedThreshold
            || abs(velocity) > velocityThreshold
    }

    static func dismissCover(_ dismiss: DismissAction) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dismiss()
        }
    }

    @MainActor
    static func animateAway(
        drag: Binding<LightboxDismissDrag>,
        direction: CGFloat,
        screenHeight: CGFloat,
        onFinished: @escaping () -> Void
    ) {
        guard !drag.wrappedValue.isDismissing else { return }
        drag.wrappedValue.isDismissing = true
        drag.wrappedValue.isLocked = true
        let travel = max(screenHeight, 1) * 1.08
        withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
            drag.wrappedValue.offset = direction * travel
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            onFinished()
        }
    }

    @MainActor
    static func snapBack(drag: Binding<LightboxDismissDrag>) {
        withAnimation(.interactiveSpring(response: 0.36, dampingFraction: 0.86)) {
            drag.wrappedValue.offset = 0
        }
        drag.wrappedValue.isLocked = false
    }
}

/// Blurs media only. Text outside this view stays sharp.
/// A center button explains the blur and asks the viewer to accept responsibility before revealing.
struct SensitiveMediaOverlay<Content: View>: View {
    let isSensitive: Bool
    /// Age lock owned by the parent (shots). Feed posts use `mediaAgeLocked` from `AgeRestrictedMediaGate`.
    var isAgeRestricted: Bool = false
    var allowsReveal: Bool = true
    var loadContentWhenBlurred: Bool = true
    /// Grid thumbnails blur without a button so the parent link stays tappable.
    var showsRevealButton: Bool = true
    /// When false, blur follows `isSensitive` only (parent owns reveal).
    var managesRevealInternally: Bool = true
    var moderationReason: String? = nil
    var cornerRadius: CGFloat = 0
    var title: String = "Sensitive content"
    var subtitle: String = "Tap to view"
    var onReveal: (() -> Void)? = nil
    var onTapWhenVisible: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.mediaAgeLocked) private var mediaAgeLocked
    @Environment(\.confirmMediaAge) private var confirmMediaAge
    @State private var revealed = false
    @State private var showNotice = false

    var body: some View {
        blurredMedia
            .accessibilityHidden(shouldBlur && SensitiveMediaOverlayPolicy.hidesContentFromAccessibility(isGated: true))
        .onTapIf(!shouldBlur && onTapWhenVisible != nil) {
            onTapWhenVisible?()
        }
        .sheet(isPresented: $showNotice) {
            SensitiveMediaNoticeSheet(notice: notice) { choice in
                if choice == .session {
                    SensitiveRevealSessionStore.shared.allowForSession()
                }
                acceptNotice()
            }
        }
        .onChange(of: isSensitive) { _, newValue in
            if !newValue { revealed = false }
        }
    }

    private var mediaShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Blur, noise, and the button stay inside the image. They do not grow to the container.
    @ViewBuilder
    private var blurredMedia: some View {
        if shouldBlur && SensitiveMediaOverlayPolicy.shouldLoadContent(
            isBlurred: true,
            loadWhenBlurred: loadContentWhenBlurred
        ) {
            content()
                .clipShape(mediaShape)
                .blur(radius: 28)
                .clipShape(mediaShape)
                .overlay {
                    ZStack {
                        Color.black.opacity(0.22)
                        SensitiveMediaNoise()
                    }
                    .clipShape(mediaShape)
                    .allowsHitTesting(false)
                }
                .overlay {
                    if showsRevealButton {
                        ZStack {
                            Color.clear
                                .contentShape(mediaShape)
                                .onTapGesture { }
                            revealButton
                        }
                    }
                }
        } else if shouldBlur {
            mediaShape
                .fill(Color.black.opacity(0.18))
                .overlay {
                    if showsRevealButton {
                        revealButton
                    }
                }
        } else {
            content()
        }
    }

    private var notice: SensitiveMediaNotice {
        SensitiveMediaNotice.make(
            ageLocked: mediaAgeLocked || isAgeRestricted,
            isSensitive: isSensitive,
            allowsReveal: allowsReveal,
            reason: moderationReason
        )
    }

    private var revealButton: some View {
        Button {
            if SensitiveMediaOverlayPolicy.skipsNotice(
                canContinue: notice.canContinue,
                sessionAllowed: SensitiveRevealSessionStore.shared.allowsImmediateReveal
            ) {
                acceptNotice()
            } else {
                showNotice = true
            }
        } label: {
            Image(systemName: notice.canContinue ? "eye.slash" : "clock")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notice.title)
        .accessibilityHint(
            notice.canContinue
                ? (SensitiveRevealSessionStore.shared.allowsImmediateReveal
                    ? "Shows this media"
                    : "Shows why this media is blurred")
                : SensitiveMediaOverlayPolicy.subtitle(allowsReveal: false, subtitle: subtitle)
        )
    }

    private func acceptNotice() {
        let ageLocked = mediaAgeLocked || isAgeRestricted
        if mediaAgeLocked {
            confirmMediaAge()
        }
        let canRevealSensitive = SensitiveMediaOverlayPolicy.revealsOnTap(
            isSensitive: isSensitive,
            allowsReveal: allowsReveal
        )
        if canRevealSensitive && managesRevealInternally {
            withAnimation(.easeOut(duration: 0.2)) {
                revealed = true
            }
        }
        if canRevealSensitive || ageLocked {
            onReveal?()
        }
    }

    private var shouldBlur: Bool {
        SensitiveMediaOverlayPolicy.shouldBlur(
            isSensitive: isSensitive,
            revealed: revealed,
            managesRevealInternally: managesRevealInternally
        ) || mediaAgeLocked || isAgeRestricted
    }
}

/// Dense twinkling specks over the blur, matching Telegram's 18+ media mask.
private struct SensitiveMediaNoise: View {
    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                guard size.width > 1, size.height > 1 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = min(720, max(90, Int(size.width * size.height / 150)))
                for index in 0..<count {
                    let seed = Double(index)
                    let phase = seed * 0.37
                    let baseX = Self.fract(sin(seed * 12.9898) * 43758.5453)
                    let baseY = Self.fract(sin(seed * 78.233) * 43758.5453)
                    let driftX = sin(time * 0.7 + phase) * 0.015
                    let driftY = cos(time * 0.45 + phase * 1.4) * 0.015
                    let x = Self.fract(baseX + driftX) * size.width
                    let y = Self.fract(baseY + driftY) * size.height
                    let speed = 1.6 + Self.fract(phase) * 2.4
                    let twinkle = max(0, sin(time * speed + phase))
                    let alpha = twinkle * twinkle * 0.92
                    if alpha < 0.08 { continue }
                    let radius = 0.55 + Self.fract(sin(seed * 4.1) * 999) * 1.15
                    let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}

enum SensitiveMediaNotice: Equatable {
    case ageRestricted
    case sensitive(reason: String?)
    case ageAndSensitive(reason: String?)
    case unavailable

    static let responsibility = "If you continue, you choose to view this material and release Alton from responsibility for displaying it."

    var title: String {
        switch self {
        case .ageRestricted:
            return "18+ content"
        case .sensitive, .ageAndSensitive:
            return "Sensitive content"
        case .unavailable:
            return "Content unavailable"
        }
    }

    var explanation: String {
        switch self {
        case .ageRestricted:
            return "This media is blurred because it is marked 18+ and may not be suitable for anyone under 18."
        case .sensitive(let reason):
            return Self.sensitiveExplanation(reason: reason)
        case .ageAndSensitive(let reason):
            return "This media is blurred because it is marked 18+. \(Self.sensitiveExplanation(reason: reason))"
        case .unavailable:
            return "This image is still being checked."
        }
    }

    var canContinue: Bool {
        if case .unavailable = self { return false }
        return true
    }

    static func make(
        ageLocked: Bool,
        isSensitive: Bool,
        allowsReveal: Bool,
        reason: String?
    ) -> SensitiveMediaNotice {
        if isSensitive && !allowsReveal {
            return .unavailable
        }
        let label = ReportReason.displayTitle(for: reason)
        if ageLocked && isSensitive {
            return .ageAndSensitive(reason: label)
        }
        if ageLocked {
            return .ageRestricted
        }
        return .sensitive(reason: label)
    }

    private static func sensitiveExplanation(reason: String?) -> String {
        if let reason, !reason.isEmpty {
            return "This media is blurred because it may contain sensitive material (\(reason))."
        }
        return "This media is blurred because it may contain sensitive material."
    }
}

enum SensitiveMediaRevealChoice: Equatable {
    case session
    case once
}

private struct SensitiveMediaNoticeSheet: View {
    let notice: SensitiveMediaNotice
    let onChoose: (SensitiveMediaRevealChoice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: notice.canContinue ? "eye.slash" : "clock")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(Color(.secondarySystemBackground), in: Circle())

                Text(notice.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(notice.explanation)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if notice.canContinue {
                    Text(SensitiveMediaNotice.responsibility)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                if notice.canContinue {
                    Button {
                        onChoose(.session)
                        dismiss()
                    } label: {
                        Text("Allow for this session")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onChoose(.once)
                        dismiss()
                    } label: {
                        Text("Allow once")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }

                Button(notice.canContinue ? "Not now" : "OK") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

enum SensitiveMediaOverlayPolicy {
    static func revealsOnTap(isSensitive: Bool, allowsReveal: Bool) -> Bool {
        isSensitive && allowsReveal
    }

    /// Session consent skips the sheet. Media that cannot be revealed still explains why.
    static func skipsNotice(canContinue: Bool, sessionAllowed: Bool) -> Bool {
        canContinue && sessionAllowed
    }

    static func title(allowsReveal: Bool, title: String = "Sensitive content") -> String {
        allowsReveal ? title : "Content unavailable"
    }

    static func subtitle(allowsReveal: Bool, subtitle: String = "Tap to view") -> String {
        allowsReveal ? subtitle : "This image is still being checked"
    }

    static func hidesContentFromAccessibility(isGated: Bool) -> Bool {
        AgeRestrictedContentPolicy.hidesContentFromAccessibility(isGated: isGated)
    }

    static func shouldLoadContent(isBlurred: Bool, loadWhenBlurred: Bool) -> Bool {
        !isBlurred || loadWhenBlurred
    }

    static func shouldBlur(isSensitive: Bool, revealed: Bool, managesRevealInternally: Bool) -> Bool {
        if managesRevealInternally {
            return isSensitive && !revealed
        }
        return isSensitive
    }
}

/// Marks 18+ posts so only media inside blurs. Caption text stays sharp.
struct AgeRestrictedMediaGate<Content: View>: View {
    let isAgeGated: Bool
    var contentID: String = ""
    @ViewBuilder var content: () -> Content

    @State private var confirmed = false
    @State private var confirmedForID = ""

    var body: some View {
        let store = AgeGateConfirmationStore.shared
        let storeConfirmed = store.confirmedIDs.contains(contentID)
        let isConfirmed = confirmed || storeConfirmed
        let gated = AgeRestrictedMediaGatePolicy.shouldGate(
            isAgeGated: isAgeGated,
            confirmed: isConfirmed,
            contentID: contentID,
            confirmedForID: isConfirmed ? contentID : confirmedForID
        )
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.mediaAgeLocked, gated)
            .environment(\.confirmMediaAge, {
                confirmed = true
                confirmedForID = contentID
                AgeGateConfirmationStore.shared.confirm(contentID)
            })
            .onChange(of: contentID) { _, newID in
                if AgeRestrictedMediaGatePolicy.shouldReset(confirmedForID: confirmedForID, newID: newID) {
                    confirmed = false
                }
            }
            .onChange(of: isAgeGated) { _, isGated in
                if !isGated {
                    confirmed = false
                    confirmedForID = ""
                }
            }
    }
}

private struct MediaAgeLockedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ConfirmMediaAgeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private extension EnvironmentValues {
    var mediaAgeLocked: Bool {
        get { self[MediaAgeLockedKey.self] }
        set { self[MediaAgeLockedKey.self] = newValue }
    }

    var confirmMediaAge: () -> Void {
        get { self[ConfirmMediaAgeKey.self] }
        set { self[ConfirmMediaAgeKey.self] = newValue }
    }
}

private extension View {
    @ViewBuilder
    func onTapIf(_ enabled: Bool, perform action: @escaping () -> Void) -> some View {
        if enabled {
            self.onTapGesture(perform: action)
        } else {
            self
        }
    }
}

enum AgeRestrictedMediaGatePolicy {
    static func shouldGate(
        isAgeGated: Bool,
        confirmed: Bool,
        contentID: String,
        confirmedForID: String,
        viewerIsAdult: Bool = AgeGateConfirmationStore.shared.viewerIsAdult
    ) -> Bool {
        guard isAgeGated else { return false }
        // Verified adults never see the age gate.
        if viewerIsAdult { return false }
        // Under-18 / unknown DOB: permanently gated (session confirm ignored).
        return true
    }

    static func shouldReset(confirmedForID: String, newID: String) -> Bool {
        confirmedForID != newID
    }
}

private extension View {
    func lightboxSwipeDismiss(
        drag: Binding<LightboxDismissDrag>,
        isEnabled: Bool,
        screenHeight: CGFloat,
        onDismiss: @escaping () -> Void
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .local)
                .onChanged { value in
                    guard isEnabled, !drag.wrappedValue.isDismissing else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if !drag.wrappedValue.isLocked {
                        guard abs(dy) > abs(dx) * 1.2 else { return }
                        drag.wrappedValue.isLocked = true
                    }
                    drag.wrappedValue.offset = dy
                }
                .onEnded { value in
                    guard isEnabled, !drag.wrappedValue.isDismissing else { return }
                    guard drag.wrappedValue.isLocked else { return }
                    let dy = value.translation.height
                    if LightboxDismissMotion.shouldDismiss(
                        translation: dy,
                        predicted: value.predictedEndTranslation.height,
                        velocity: value.velocity.height
                    ) {
                        LightboxDismissMotion.animateAway(
                            drag: drag,
                            direction: dy >= 0 ? 1 : -1,
                            screenHeight: screenHeight,
                            onFinished: onDismiss
                        )
                    } else {
                        LightboxDismissMotion.snapBack(drag: drag)
                    }
                }
        )
    }
}
