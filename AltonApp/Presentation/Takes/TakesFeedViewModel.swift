import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class TakesFeedViewModel {
    var items: [FeedTimelineItem] = []
    var adSlots: [FeedAdSlot] = []
    var feedMode: FeedMode = .forYou
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    /// True when the server returned no next_cursor — catalog walk finished.
    var isExhausted = false
    /// Client-side fallback when server filter is off / lagging.
    var showSensitiveContent = false
    /// Client-side age gate: hide age-gated posts when viewer is not 18+.
    var viewerIsAdult = false
    private var nextCursor: String?
    private var hasLoaded = false
    private var window = WindowedFeed<FeedTimelineItem>(windowSize: 100)
    private let maxEmptyPageContinues = 3
    // Read from `deinit`; stored `nonisolated` is illegal on @Observable properties.
    @ObservationIgnored private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?

    /// Default native-ad cadence when the feed response has no `ad_slots`.
    private let defaultFrequencyCap = 5
    private let defaultMinPosition = 3
    private let thumbPrefetchAhead = 8
    private let fullPrefetchWindow = 2

    private let feedUseCase: FeedUseCase
    private let commentsUseCase: CommentsUseCase
    private let activityUseCase: PostActivityUseCase
    let userUseCase: UserUseCase
    let engagementController: PostEngagementController

    /// Flattened feed rows with native ads inserted at `adSlots` (or default cadence).
    var displayRows: [FeedDisplayRow] {
        Self.buildDisplayRows(items: visibleItems, adSlots: resolvedAdSlots)
    }

    private var visibleItems: [FeedTimelineItem] {
        items.filter {
            ViewerContentFilterPolicy.allowsTimelineItem(
                $0,
                viewerIsAdult: viewerIsAdult,
                showSensitiveContent: showSensitiveContent
            )
        }
    }

    private var resolvedAdSlots: [FeedAdSlot] {
        if !adSlots.isEmpty { return adSlots }
        let postCount = visibleItems.reduce(0) { partial, item in
            if case .post = item { return partial + 1 }
            return partial
        }
        guard defaultFrequencyCap > 0, postCount >= defaultMinPosition else { return [] }
        var slots: [FeedAdSlot] = []
        var pos = defaultMinPosition
        while pos <= postCount {
            slots.append(FeedAdSlot(placementID: "feed_native", position: pos))
            pos += defaultFrequencyCap
        }
        return slots
    }

    init(
        feedUseCase: FeedUseCase,
        engagementUseCase: EngagementUseCase,
        commentsUseCase: CommentsUseCase,
        activityUseCase: PostActivityUseCase,
        userUseCase: UserUseCase
    ) {
        self.feedUseCase = feedUseCase
        self.commentsUseCase = commentsUseCase
        self.activityUseCase = activityUseCase
        self.userUseCase = userUseCase
        self.engagementController = PostEngagementController(
            engagementUseCase: engagementUseCase,
            commentsUseCase: commentsUseCase
        )
        self.engagementController.bind { [weak self] post in
            self?.updatePost(post)
        }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func updatePost(_ post: Post) {
        guard let index = items.firstIndex(where: {
            if case .post(let item) = $0 { return item.id == post.id }
            return false
        }) else { return }
        if case .post(let item) = items[index] {
            items[index] = .post(item.updatingPost(post))
            window.items = items
        }
    }

    func makeCommentsViewModel(for post: Post, userID: String) -> CommentsViewModel {
        CommentsViewModel(
            postID: post.id,
            currentUserID: userID,
            commentsUseCase: commentsUseCase,
            activityUseCase: activityUseCase,
            onCommentAdded: { [weak self] in
                guard let self else { return }
                let updated = post.updatingEngagement(commentCount: post.commentCount + 1)
                self.updatePost(updated)
            }
        )
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let page = try await fetchTakesPage(cursor: nil)
            window.replaceAll(page.items)
            items = window.items
            adSlots = page.adSlots
            nextCursor = page.nextCursor
            isExhausted = page.nextCursor == nil || page.nextCursor?.isEmpty == true
            // Drop prior feed's thumb/full work before warming the new page.
            FeedImagePrefetcher.shared.stopAll()
            prefetchThumbs(for: page.items)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func switchFeedMode(_ mode: FeedMode) async {
        guard feedMode != mode else { return }
        feedMode = mode
        window.replaceAll([])
        items = []
        adSlots = []
        nextCursor = nil
        isExhausted = false
        hasLoaded = false
        FeedImagePrefetcher.shared.stopAll()
        await loadInitial()
    }

    func refresh() async {
        nextCursor = nil
        isExhausted = false
        await loadInitial()
    }

    func loadMoreIfNeeded(currentItem: FeedTimelineItem) async {
        guard let nextCursor, !nextCursor.isEmpty, !isLoadingMore, !isExhausted else { return }
        // Compare against the last *visible* row — filtered sensitive items sit in `items`
        // but never appear in the UI, so anchoring on `items.last` would stall pagination.
        guard visibleItems.last?.id == currentItem.id else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let postCountBefore = visibleItems.reduce(0) { partial, item in
                if case .post = item { return partial + 1 }
                return partial
            }
            let page = try await fetchTakesPage(cursor: nextCursor)
            let existingIDs = Set(items.map(\.id))
            let unique = page.items.filter { !existingIDs.contains($0.id) }
            // Focus near the end — user is loading more while scrolled down.
            _ = window.append(unique, around: max(0, window.items.count - 1))
            items = window.items
            let offsetSlots = page.adSlots.map {
                FeedAdSlot(placementID: $0.placementID, position: $0.position + postCountBefore)
            }
            adSlots.append(contentsOf: offsetSlots)
            self.nextCursor = page.nextCursor
            isExhausted = page.nextCursor == nil || page.nextCursor?.isEmpty == true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fetch a page; if the server returns an empty/short page with a cursor, continue
    /// up to `maxEmptyPageContinues` times so filtered batches do not stall the UI.
    private func fetchTakesPage(cursor: String?) async throws -> FeedPage {
        var cursor = cursor
        var mergedItems: [FeedTimelineItem] = []
        var mergedAds: [FeedAdSlot] = []
        var lastCursor: String? = cursor
        var continues = 0

        repeat {
            let page = try await feedUseCase.fetchTakes(cursor: cursor, mode: feedMode)
            mergedItems.append(contentsOf: page.items)
            mergedAds.append(contentsOf: page.adSlots)
            lastCursor = page.nextCursor
            let hasMore = page.nextCursor.map { !$0.isEmpty } ?? false
            if !page.items.isEmpty || !hasMore {
                break
            }
            continues += 1
            cursor = page.nextCursor
        } while continues < maxEmptyPageContinues

        return FeedPage(items: mergedItems, nextCursor: lastCursor, adSlots: mergedAds)
    }

    func removePost(id: String) {
        items.removeAll {
            if case .post(let item) = $0 { return item.id == id }
            return false
        }
        window.items = items
    }

    func prefetchAhead(currentItem: FeedTimelineItem) {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItem.id }) else { return }

        let thumbStart = currentIndex
        let thumbEnd = min(items.count, currentIndex + thumbPrefetchAhead + 1)
        let aheadSlice = items[thumbStart..<thumbEnd]
        let thumbURLs = Self.thumbnailURLs(in: aheadSlice)
        if !thumbURLs.isEmpty {
            // Union-start near window without cancelling page warmup further ahead.
            FeedImagePrefetcher.shared.prefetchThumbs(thumbURLs)
        }
        // Drop only scrolled-past thumbs; keep in-flight warmup still ahead of viewport.
        let retainThumbs = Self.thumbnailURLs(in: items[currentIndex..<items.count])
        if !retainThumbs.isEmpty {
            FeedImagePrefetcher.shared.retainThumbs(retainThumbs)
        }

        let fullStart = max(0, currentIndex - fullPrefetchWindow)
        let fullEnd = min(items.count, currentIndex + fullPrefetchWindow + 1)
        var fullURLs = Self.fullImageURLs(in: items[fullStart..<fullEnd])
        // Reply cards in the ahead window only have plain URLs (no resized thumbs).
        fullURLs.append(contentsOf: Self.replyImageURLs(in: aheadSlice))
        if !fullURLs.isEmpty {
            FeedImagePrefetcher.shared.prefetchFull(fullURLs)
        }
    }

    func handleMemoryWarning() {
        window.trimToNewest()
        items = window.items
        FeedImagePrefetcher.shared.stopAll()
        ImagePipelineConfig.clearMemoryCache()
        RichTextMarkdownConverter.clearCache()
        URLCache.shared.removeAllCachedResponses()
    }

    private func prefetchThumbs(for timelineItems: [FeedTimelineItem]) {
        FeedImagePrefetcher.shared.prefetchThumbs(Self.thumbnailURLs(in: timelineItems))
    }

    private static func thumbnailURLs(in timelineItems: some Collection<FeedTimelineItem>) -> [URL] {
        timelineItems.flatMap { item -> [URL] in
            switch item {
            case .post(let feedItem):
                return feedItem.post.feedThumbnailURLs
            case .reply:
                // Comment strip uses PostMediaStripView without a Post (thumbURL == fullURL,
                // no resize processor) — covered by fullImageURLs.
                return []
            }
        }
    }

    private static func fullImageURLs(in timelineItems: some Collection<FeedTimelineItem>) -> [URL] {
        timelineItems.flatMap { item -> [URL] in
            switch item {
            case .post(let feedItem):
                return feedItem.post.imageURLs
            case .reply(let replyItem):
                return replyItem.comment.imageURLs
            }
        }
    }

    private static func replyImageURLs(in timelineItems: some Collection<FeedTimelineItem>) -> [URL] {
        timelineItems.flatMap { item -> [URL] in
            guard case .reply(let replyItem) = item else { return [] }
            return replyItem.comment.imageURLs
        }
    }

    static func buildDisplayRows(items: [FeedTimelineItem], adSlots: [FeedAdSlot]) -> [FeedDisplayRow] {
        let slotPositions = Set(adSlots.map(\.position))
        var rows: [FeedDisplayRow] = []
        var postIndex = 0

        for item in items {
            rows.append(.timeline(item))
            if case .post = item {
                postIndex += 1
                if slotPositions.contains(postIndex) {
                    let placement = adSlots.first(where: { $0.position == postIndex })?.placementID ?? "feed_native"
                    rows.append(.nativeAd(placementID: placement, position: postIndex))
                }
            }
        }
        return rows
    }
}

enum FeedDisplayRow: Identifiable, Equatable {
    case timeline(FeedTimelineItem)
    case nativeAd(placementID: String, position: Int)

    var id: String {
        switch self {
        case .timeline(let item):
            return item.id
        case .nativeAd(let placementID, let position):
            return "ad-\(placementID)-\(position)"
        }
    }
}
