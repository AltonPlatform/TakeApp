import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ShotFeedViewModel {
    var items: [FeedItem] = []
    var adSlots: [FeedAdSlot] = []
    var currentIndex = 0
    var isLoading = false
    var isRefreshing = false
    var isLoadingMore = false
    var errorMessage: String?
    /// True when the server returned no next_cursor — catalog walk finished.
    var isExhausted = false
    /// Client-side fallback when server filter is off / lagging.
    var showSensitiveContent = false
    /// Client-side age gate: hide age-gated shots when viewer is not 18+.
    var viewerIsAdult = false
    private var nextCursor: String?
    private var window = WindowedFeed<FeedItem>(windowSize: 60)
    private let maxEmptyPageContinues = 3
    // Read from `deinit`; stored `nonisolated` is illegal on @Observable properties.
    @ObservationIgnored private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?

    /// Default native-ad cadence when the feed response has no shot-feed `ad_slots`.
    private let defaultFrequencyCap = 5
    private let defaultMinPosition = 3

    private let feedUseCase: FeedUseCase
    private let commentsUseCase: CommentsUseCase
    private let activityUseCase: PostActivityUseCase
    let userUseCase: UserUseCase
    let engagementController: PostEngagementController

    /// Flattened pager pages with native ads inserted at `adSlots` (or default cadence).
    var displayRows: [ShotFeedDisplayRow] {
        Self.buildDisplayRows(items: visibleItems, adSlots: resolvedAdSlots)
    }

    private var visibleItems: [FeedItem] {
        items.filter {
            ViewerContentFilterPolicy.allowsPost(
                $0.post,
                viewerIsAdult: viewerIsAdult,
                showSensitiveContent: showSensitiveContent
            )
        }
    }

    private var resolvedAdSlots: [FeedAdSlot] {
        let usable = adSlots.filter { $0.placementID == NativeAdPool.shotFeedPlacementID }
        if !usable.isEmpty { return usable }
        return Self.defaultAdSlots(
            shotCount: visibleItems.count,
            frequencyCap: defaultFrequencyCap,
            minPosition: defaultMinPosition
        )
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
        guard let index = items.firstIndex(where: { $0.id == post.id }) else { return }
        items[index] = items[index].updatingPost(post)
        window.items = items
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
        defer { isLoading = false }

        do {
            let page = try await fetchShotsPage(cursor: nil)
            window.replaceAll(page.items)
            items = window.items
            adSlots = Self.shotFeedSlots(from: page.adSlots)
            nextCursor = page.nextCursor
            isExhausted = page.nextCursor == nil || page.nextCursor?.isEmpty == true
            currentIndex = 0
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        isExhausted = false
        defer { isRefreshing = false }

        do {
            let page = try await fetchShotsPage(cursor: nil)
            window.replaceAll(page.items)
            items = window.items
            adSlots = Self.shotFeedSlots(from: page.adSlots)
            nextCursor = page.nextCursor
            isExhausted = page.nextCursor == nil || page.nextCursor?.isEmpty == true
            currentIndex = 0
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(for index: Int) async {
        guard index >= max(displayRows.count - 3, 0) else { return }
        guard let nextCursor, !nextCursor.isEmpty, !isExhausted else { return }
        guard !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let focusedID = focusedShotID(at: currentIndex)
            let firstID = items.first?.id
            let shotCountBefore = items.count
            let page = try await fetchShotsPage(cursor: nextCursor)
            let existingIDs = Set(items.map(\.id))
            let unique = page.items.filter { !existingIDs.contains($0.id) }
            let remapped = window.append(unique, around: itemFocusIndex(forDisplayIndex: currentIndex))
            items = window.items
            let offsetSlots = Self.shotFeedSlots(from: page.adSlots).map {
                FeedAdSlot(placementID: $0.placementID, position: $0.position + shotCountBefore)
            }
            adSlots.append(contentsOf: offsetSlots)
            self.nextCursor = page.nextCursor
            isExhausted = page.nextCursor == nil || page.nextCursor?.isEmpty == true
            if items.first?.id != firstID {
                restoreCurrentIndex(shotID: focusedID, fallbackItemIndex: remapped)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// At the end of the catalog: try one more page if a cursor remains; do not auto-refresh.
    func handleOverscrollPastEnd() async {
        guard !isExhausted else { return }
        if let nextCursor, !nextCursor.isEmpty {
            await loadMoreIfNeeded(for: displayRows.count - 1)
        }
    }

    /// Fetch a page; continue through empty filtered pages while a cursor remains.
    private func fetchShotsPage(cursor: String?) async throws -> ShotFeedPage {
        var cursor = cursor
        var mergedItems: [FeedItem] = []
        var mergedAds: [FeedAdSlot] = []
        var lastCursor: String? = cursor
        var continues = 0

        repeat {
            let page = try await feedUseCase.fetchShots(cursor: cursor)
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

        return ShotFeedPage(items: mergedItems, nextCursor: lastCursor, adSlots: mergedAds)
    }

    func setCurrentIndex(_ index: Int) {
        currentIndex = index
        Task { await loadMoreIfNeeded(for: index) }
    }

    /// Call after mutating `showSensitiveContent` / `viewerIsAdult` so the pager
    /// stays on the same shot (or clamps) when `displayRows` shrinks.
    func applyContentPreferences(showSensitive: Bool, viewerIsAdult: Bool) {
        let focusedID = focusedShotID(at: currentIndex)
        showSensitiveContent = showSensitive
        self.viewerIsAdult = viewerIsAdult
        restoreCurrentIndex(shotID: focusedID, fallbackItemIndex: 0)
    }

    func handleMemoryWarning() {
        let focusedID = focusedShotID(at: currentIndex)
        window.trimToNewest()
        items = window.items
        restoreCurrentIndex(shotID: focusedID, fallbackItemIndex: min(currentIndex, max(0, items.count - 1)))
        ShotFeedPlaybackCache.shared.clearAll()
        NativeAdSlotCache.shared.releaseAll()
        ImagePipelineConfig.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()
    }

    func adjacentShotID(beforePosition: Int) -> String? {
        let shotIndex = beforePosition - 1
        guard items.indices.contains(shotIndex) else { return nil }
        return items[shotIndex].id
    }

    private func focusedShotID(at displayIndex: Int) -> String? {
        guard displayRows.indices.contains(displayIndex) else { return nil }
        switch displayRows[displayIndex] {
        case .shot(let item):
            return item.id
        case .nativeAd(_, let position):
            return adjacentShotID(beforePosition: position)
        }
    }

    private func displayIndex(forShotID id: String) -> Int? {
        displayRows.firstIndex { row in
            if case .shot(let item) = row { return item.id == id }
            return false
        }
    }

    private func itemFocusIndex(forDisplayIndex displayIndex: Int) -> Int {
        guard displayRows.indices.contains(displayIndex) else {
            return max(0, items.count - 1)
        }
        switch displayRows[displayIndex] {
        case .shot(let item):
            return items.firstIndex(where: { $0.id == item.id }) ?? max(0, items.count - 1)
        case .nativeAd(_, let position):
            return max(0, min(position - 1, items.count - 1))
        }
    }

    private func restoreCurrentIndex(shotID: String?, fallbackItemIndex: Int) {
        if let shotID, let idx = displayIndex(forShotID: shotID) {
            currentIndex = idx
            return
        }
        if items.indices.contains(fallbackItemIndex) {
            currentIndex = displayIndex(forShotID: items[fallbackItemIndex].id) ?? 0
            return
        }
        currentIndex = min(currentIndex, max(0, displayRows.count - 1))
    }

    static func shotFeedSlots(from slots: [FeedAdSlot]) -> [FeedAdSlot] {
        slots.filter { $0.placementID == NativeAdPool.shotFeedPlacementID }
    }

    static func defaultAdSlots(
        shotCount: Int,
        frequencyCap: Int = 5,
        minPosition: Int = 3,
        placementID: String = NativeAdPool.shotFeedPlacementID
    ) -> [FeedAdSlot] {
        guard frequencyCap > 0, shotCount >= minPosition else { return [] }
        var slots: [FeedAdSlot] = []
        var pos = minPosition
        while pos <= shotCount {
            slots.append(FeedAdSlot(placementID: placementID, position: pos))
            pos += frequencyCap
        }
        return slots
    }

    static func buildDisplayRows(items: [FeedItem], adSlots: [FeedAdSlot]) -> [ShotFeedDisplayRow] {
        let slotPositions = Set(adSlots.map(\.position))
        var rows: [ShotFeedDisplayRow] = []
        var shotIndex = 0

        for item in items {
            rows.append(.shot(item))
            shotIndex += 1
            if slotPositions.contains(shotIndex) {
                let placement = adSlots.first(where: { $0.position == shotIndex })?.placementID
                    ?? NativeAdPool.shotFeedPlacementID
                rows.append(.nativeAd(placementID: placement, position: shotIndex))
            }
        }
        return rows
    }
}

enum ShotFeedDisplayRow: Identifiable, Equatable {
    case shot(FeedItem)
    case nativeAd(placementID: String, position: Int)

    var id: String {
        switch self {
        case .shot(let item):
            return item.id
        case .nativeAd(let placementID, let position):
            return "ad-\(placementID)-\(position)"
        }
    }
}
