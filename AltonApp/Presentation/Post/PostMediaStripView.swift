import SwiftUI
import Nuke
import NukeUI
import ImageIO

/// Figma photo axis (h1/h2/h3+, v1/v2/v3+, mixed).
/// Sliders bleed to the app screen edges. Tiles keep the photo aspect — no crop.
/// Feed tiles load 512px thumbs only. Full playback URLs open in the lightbox.
struct PostMediaStripView: View {
    let urls: [URL]
    var post: Post?
    var currentUser: User?
    var engagementController: PostEngagementController?
    var commentsViewModelFactory: ((Post) -> CommentsViewModel)?
    var session: AuthSession?
    var container: DependencyContainer?
    var onPostChange: ((Post) -> Void)?

    @State private var layout: PostMediaDesign.Layout = .h1
    @State private var aspects: [CGFloat] = []
    @State private var columnMetrics = MediaColumnMetrics()
    @State private var lightboxItem: LightboxItem?
    @State private var revealedIndices: Set<Int> = []

    private struct LightboxItem: Identifiable {
        let id: String
        let index: Int
    }

    private var items: [(thumb: URL, full: URL)] {
        if urls.isEmpty { return [] }
        if post == nil {
            // Comments: keep the original file so GIF/WebP animation isn't replaced by a still thumb.
            return urls.map { ($0, $0) }
        }
        let thumbs: [URL]
        if let post, !post.feedThumbnailURLs.isEmpty, post.feedThumbnailURLs.count == urls.count {
            thumbs = post.feedThumbnailURLs
        } else {
            thumbs = MediaThumbnailURL.thumbnails(
                imageURLs: urls,
                thumbnailURL: post?.thumbnailURL,
                thumbnailKey: post?.thumbnailKey
            )
        }
        return zip(thumbs, urls).map { ($0, $1) }
    }

    private var fullURLs: [URL] { items.map(\.full) }
    private var thumbURLs: [URL] { items.map(\.thumb) }
    private var column: CGFloat {
        columnMetrics.width > 1 ? columnMetrics.width : PostMediaDesign.figmaColumn
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 0)
                        .background {
                            GeometryReader { geo in
                                let frame = geo.frame(in: .global)
                                Color.clear.preference(
                                    key: MediaColumnMetricsKey.self,
                                    value: MediaColumnMetrics(
                                        width: geo.size.width,
                                        minX: frame.minX,
                                        maxX: frame.maxX
                                    )
                                )
                            }
                        }
                        .onPreferenceChange(MediaColumnMetricsKey.self) { columnMetrics = $0 }

                    layoutBody
                }
                .task(id: thumbURLs.map(\.absoluteString).joined(separator: "|")) {
                    revealedIndices = []
                    await resolveLayout()
                }
            }
        }
        .fullScreenCover(item: $lightboxItem) { item in
            if let post,
               let engagementController,
               let commentsViewModelFactory {
                ImageImmersiveViewer(
                    urls: fullURLs,
                    thumbnailURLs: thumbURLs,
                    blurFlags: perImageBlurFlags(for: post),
                    unknownFlags: perImageUnknownFlags(for: post),
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
                ImageLightboxView(
                    urls: fullURLs,
                    thumbnailURLs: thumbURLs,
                    blurFlags: post.map { perImageBlurFlags(for: $0) },
                    unknownFlags: post.map { perImageUnknownFlags(for: $0) },
                    initialIndex: item.index
                )
            }
        }
    }

    @ViewBuilder
    private var layoutBody: some View {
        switch layout {
        case .h1, .v1:
            tile(index: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .h2, .h3Plus, .v2, .v3Plus, .mixed:
            slider
        }
    }

    private var slider: some View {
        let leadingBleed = max(0, columnMetrics.minX)
        let trailingBleed = max(0, Self.screenWidth - columnMetrics.maxX)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PostMediaDesign.spacing(for: layout)) {
                ForEach(items.indices, id: \.self) { index in
                    tile(index: index)
                }
            }
        }
        // First and last tiles rest on the post column; the track still reaches the screen edges.
        .contentMargins(.leading, leadingBleed, for: .scrollContent)
        .contentMargins(.trailing, trailingBleed, for: .scrollContent)
        .padding(.leading, -leadingBleed)
        .padding(.trailing, -trailingBleed)
    }

    private func tile(index: Int) -> some View {
        let size = PostMediaDesign.displaySize(
            layout: layout,
            rawAspect: aspect(at: index),
            firstRawAspect: aspect(at: 0),
            column: column
        )
        return SensitiveMediaOverlay(
            isSensitive: post?.isSensitiveImage(at: index) == true,
            allowsReveal: post?.allowsRevealImage(at: index) ?? true,
            loadContentWhenBlurred: post?.allowsRevealImage(at: index) ?? true,
            moderationReason: post?.moderationReason,
            cornerRadius: PostMediaDesign.cornerRadius,
            onReveal: {
                revealedIndices.insert(index)
                Task { await resolveLayout() }
            },
            onTapWhenVisible: { openLightbox(index: index) }
        ) {
            HugPhoto(
                thumbURL: items[index].thumb,
                fullURL: items[index].full,
                cornerRadius: PostMediaDesign.cornerRadius
            )
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .frame(width: size.width, height: size.height)
    }

    private func aspect(at index: Int) -> CGFloat {
        if aspects.indices.contains(index), aspects[index] > 0 {
            return aspects[index]
        }
        return layout == .v1 || layout == .v2 || layout == .v3Plus ? 9.0 / 16.0 : 4.0 / 3.0
    }

    private func perImageBlurFlags(for post: Post) -> [Bool] {
        fullURLs.indices.map { post.blursImage(at: $0) }
    }

    private func perImageUnknownFlags(for post: Post) -> [Bool] {
        fullURLs.indices.map { post.isUnknownImage(at: $0) }
    }

    private func openLightbox(index: Int) {
        guard items.indices.contains(index) else { return }
        lightboxItem = LightboxItem(id: items[index].full.absoluteString, index: index)
    }

    private func resolveLayout() async {
        var portraits: [Bool] = []
        var resolved: [CGFloat] = []
        portraits.reserveCapacity(items.count)
        resolved.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            let sensitive = post?.isSensitiveImage(at: index) == true
            let unknown = post?.isUnknownImage(at: index) == true
            let revealed = revealedIndices.contains(index)
            if !PostMediaLayoutProbe.shouldProbeRemoteSize(
                isSensitive: sensitive,
                isUnknown: unknown,
                isRevealed: revealed
            ) {
                portraits.append(false)
                resolved.append(4.0 / 3.0)
                continue
            }
            if let size = await Self.probeSize(item.thumb), size.width > 0, size.height > 0 {
                portraits.append(size.height > size.width)
                resolved.append(size.width / size.height)
            } else {
                portraits.append(false)
                resolved.append(4.0 / 3.0)
            }
        }
        aspects = resolved
        layout = PostMediaDesign.layout(portraits: portraits)
    }

    private static var screenWidth: CGFloat {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.screen.bounds.width
        }
        return UIScreen.main.bounds.width
    }

    private static let sizeCache = NSCache<NSURL, NSValue>()

    /// Header/size only from the **thumb**. Never downloads the full playback file.
    private static func probeSize(_ url: URL) async -> CGSize? {
        if let cached = sizeCache.object(forKey: url as NSURL)?.cgSizeValue,
           cached.width > 0, cached.height > 0 {
            return cached
        }

        let request = ImageRequest(url: url, priority: .low)
        if let cached = ImagePipeline.shared.cache[request] {
            let size = cached.image.size
            if size.width > 0, size.height > 0 {
                sizeCache.setObject(NSValue(cgSize: size), forKey: url as NSURL)
                return size
            }
        }

        if url.isFileURL, let data = try? Data(contentsOf: url), let size = MediaThumbnailURL.pixelSize(of: data) {
            sizeCache.setObject(NSValue(cgSize: size), forKey: url as NSURL)
            return size
        }

        do {
            let (data, _) = try await ImagePipeline.shared.data(for: request)
            guard let size = MediaThumbnailURL.pixelSize(of: data) else { return nil }
            sizeCache.setObject(NSValue(cgSize: size), forKey: url as NSURL)
            return size
        } catch {
            return nil
        }
    }
}

/// Fits the photo into a box that already matches its aspect — no fill-crop.
/// Still thumb first, then fade in the full image (including animated GIF).
private struct HugPhoto: View {
    let thumbURL: URL
    let fullURL: URL
    var cornerRadius: CGFloat = 8

    @State private var fullLoaded = false

    var body: some View {
        imageContent
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onChange(of: fullURL) { _, _ in
                fullLoaded = false
            }
    }

    @ViewBuilder
    private var imageContent: some View {
        if thumbURL == fullURL {
            // Comment thread or no separate thumb — single URL (GIF animates directly).
            LazyImage(url: thumbURL) { state in
                photo(state)
            }
            .priority(.normal)
        } else {
            ZStack {
                LazyImage(url: thumbURL) { state in
                    photo(state)
                }
                .processors([.resize(width: 512)])
                .priority(.normal)

                // Full image / GIF overlay — no processors so GIF animation is preserved.
                LazyImage(url: fullURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(fullLoaded ? 1 : 0)
                    }
                }
                .priority(.low)
                .onCompletion { result in
                    switch result {
                    case .success:
                        fullLoaded = true
                    case .failure:
                        fullLoaded = false
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: fullLoaded)
        }
    }

    @ViewBuilder
    private func photo(_ state: LazyImageState) -> some View {
        Color.clear
            .overlay {
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
    }
}

private struct MediaColumnMetrics: Equatable {
    var width: CGFloat = 0
    var minX: CGFloat = 0
    var maxX: CGFloat = 0
}

private struct MediaColumnMetricsKey: PreferenceKey {
    static var defaultValue = MediaColumnMetrics()
    static func reduce(value: inout MediaColumnMetrics, nextValue: () -> MediaColumnMetrics) {
        value = nextValue()
    }
}
