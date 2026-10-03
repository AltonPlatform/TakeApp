import SwiftUI
import UIKit

struct ShotFeedVerticalPager: UIViewControllerRepresentable {
    let rows: [ShotFeedDisplayRow]
    @Binding var currentIndex: Int
    let currentUser: User
    let session: AuthSession
    let container: DependencyContainer
    @Bindable var engagementController: PostEngagementController
    let commentsViewModelFactory: (Post) -> CommentsViewModel
    let viewSource: ViewSource
    var edgeToEdge: Bool = false
    var isFeedVisible: Bool = true
    var commentsOpenPostID: String?
    var onOpenComments: (Post) -> Void = { _ in }
    var onIndexChanged: (Int) -> Void
    var onPullToRefresh: () async -> Void
    var onOverscrollPastEnd: () async -> Void
    var onOpenProfile: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ShotFeedPagingViewController {
        let controller = ShotFeedPagingViewController()
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: ShotFeedPagingViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let itemCountChanged = coordinator.syncItemCount(forceReload: false)
        if coordinator.lastCommentsOpenPostID != commentsOpenPostID {
            coordinator.lastCommentsOpenPostID = commentsOpenPostID
            controller.updateActiveStates()
        }
        if coordinator.lastIsFeedVisible != isFeedVisible {
            coordinator.lastIsFeedVisible = isFeedVisible
            if !isFeedVisible {
                // Leaving the Video tab — release all players immediately so
                // audio/video does not keep playing in the background.
                ShotFeedPlaybackCache.shared.clearAll()
            }
            controller.updateActiveStates()
        }
        if coordinator.lastBoundIndex != currentIndex {
            coordinator.lastBoundIndex = currentIndex
            controller.scrollToPage(currentIndex, animated: false)
        } else if itemCountChanged {
            controller.updateActiveStates()
        }
    }

    @MainActor
    final class Coordinator {
        var parent: ShotFeedVerticalPager
        weak var controller: ShotFeedPagingViewController?
        private(set) var trackedItemCount = 0
        var lastBoundIndex = 0
        var lastCommentsOpenPostID: String?
        var lastIsFeedVisible: Bool = true
        private var overscrollTask: Task<Void, Never>?
        private var didTriggerOverscroll = false

        init(parent: ShotFeedVerticalPager) {
            self.parent = parent
            self.trackedItemCount = parent.rows.count
            self.lastBoundIndex = parent.currentIndex
            self.lastCommentsOpenPostID = parent.commentsOpenPostID
            self.lastIsFeedVisible = parent.isFeedVisible
        }

        @discardableResult
        func syncItemCount(forceReload: Bool) -> Bool {
            let newCount = parent.rows.count
            guard let controller else {
                trackedItemCount = newCount
                return false
            }

            if forceReload || newCount < trackedItemCount {
                trackedItemCount = newCount
                controller.reloadAllItems()
                return true
            }

            if newCount > trackedItemCount {
                let inserted = Array(trackedItemCount..<newCount)
                trackedItemCount = newCount
                if controller.isViewLoaded {
                    controller.insertItems(at: inserted)
                } else {
                    controller.enqueueInsertItems(at: inserted)
                }
                return true
            }

            trackedItemCount = newCount
            return false
        }

        func pageContent(for index: Int, visibleIndex: Int) -> AnyView {
            guard parent.rows.indices.contains(index) else {
                return AnyView(Color.black)
            }
            // When the feed is not visible (user switched to another tab), force every
            // cell inactive so AVPlayer instances are torn down and audio stops.
            let feedVisible = parent.isFeedVisible
            let isActive = feedVisible && index == visibleIndex
            // visibleIndex < 0 is used by didEndDisplaying to force teardown — do not
            // treat abs(index - (-1)) as a preload window.
            let isPreloading = feedVisible
                && visibleIndex >= 0
                && abs(index - visibleIndex) > 0
                && abs(index - visibleIndex) <= 3

            let page: AnyView
            switch parent.rows[index] {
            case .shot(let item):
                let shotPage = ShotFeedPageView(
                    item: item,
                    currentUser: parent.currentUser,
                    session: parent.session,
                    container: parent.container,
                    isActive: isActive,
                    isPreloading: isPreloading,
                    engagementController: parent.engagementController,
                    commentsViewModelFactory: parent.commentsViewModelFactory,
                    viewSource: parent.viewSource,
                    isCommentsOpen: parent.commentsOpenPostID == item.post.id,
                    onOpenComments: parent.onOpenComments,
                    onOpenProfile: parent.onOpenProfile
                )
                page = AnyView(shotPage)
            case .nativeAd(let placementID, let position):
                page = AnyView(
                    NativeAdShotView(
                        placementID: placementID,
                        position: position,
                        adRepository: parent.container.adRepository,
                        adjacentPostID: adjacentShotID(beforePosition: position),
                        feedSessionID: AppSessionTracker.shared.sessionID,
                        isActive: isActive,
                        isPreloading: isPreloading
                    )
                )
            }

            if parent.edgeToEdge {
                return AnyView(page.ignoresSafeArea())
            }
            return AnyView(page.ignoresSafeArea(edges: .top))
        }

        func onVisibleVideoIndexChanged(_ index: Int) {
            guard parent.rows.indices.contains(index) else { return }
            lastBoundIndex = index
            didTriggerOverscroll = false
            parent.onIndexChanged(index)
            warmPlayback(at: index)
        }

        func onPullToRefresh() async {
            await parent.onPullToRefresh()
        }

        func onOverscrollPastEnd() {
            guard !didTriggerOverscroll else { return }
            didTriggerOverscroll = true
            overscrollTask?.cancel()
            overscrollTask = Task { @MainActor in
                await parent.onOverscrollPastEnd()
            }
        }

        private func warmPlayback(at index: Int) {
            let lower = max(0, index - 3)
            let upper = min(parent.rows.count - 1, index + 3)
            guard lower <= upper else { return }

            var urls: [URL?] = []
            var currentInSlice = 0
            for i in lower...upper {
                if case .shot(let item) = parent.rows[i] {
                    if i == index {
                        currentInSlice = urls.count
                    }
                    urls.append(item.post.playbackURL)
                }
            }
            guard !urls.isEmpty else { return }
            ShotFeedPlaybackCache.shared.warmAdjacent(currentIndex: currentInSlice, urls: urls)
        }

        private func adjacentShotID(beforePosition: Int) -> String? {
            var shotIndex = 0
            for row in parent.rows {
                guard case .shot(let item) = row else { continue }
                shotIndex += 1
                if shotIndex == beforePosition {
                    return item.id
                }
            }
            return nil
        }
    }
}

final class ShotFeedPagingViewController: UIViewController {
    static weak var activeInstance: ShotFeedPagingViewController?

    weak var delegate: ShotFeedVerticalPager.Coordinator?

    private var collectionView: UICollectionView!
    private var refreshControl: UIRefreshControl!
    private var visibleIndex = 0
    private var pendingScrollIndex: Int?
    private var pageHeight: CGFloat = 0
    private var needsInitialReload = true
    private var pendingInsertIndexes: [Int] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            let height = max(environment.container.contentSize.height, 1)
            self?.pageHeight = height
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(height)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(height)
                ),
                subitems: [item]
            )
            return NSCollectionLayoutSection(group: group)
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.decelerationRate = .fast
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: ShotFeedPagingCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        applyPendingContentUpdates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Self.activeInstance = self
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if Self.activeInstance === self {
            Self.activeInstance = nil
        }
        ShotFeedPlaybackCache.shared.clearAll()
    }

    func setFeedScrollingEnabled(_ enabled: Bool) {
        collectionView.isScrollEnabled = enabled
    }

    var feedScrollView: UIScrollView {
        collectionView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let newHeight = collectionView.bounds.height
        if abs(newHeight - pageHeight) > 0.5 {
            (collectionView.collectionViewLayout as? UICollectionViewCompositionalLayout)?.invalidateLayout()
        }
        if let pendingScrollIndex {
            self.pendingScrollIndex = nil
            scrollToPage(pendingScrollIndex, animated: false)
        }
    }

    @objc private func handlePullToRefresh() {
        Task { @MainActor in
            await delegate?.onPullToRefresh()
            refreshControl?.endRefreshing()
        }
    }

    func enqueueInsertItems(at indexes: [Int]) {
        pendingInsertIndexes.append(contentsOf: indexes)
    }

    private func applyPendingContentUpdates() {
        if !pendingInsertIndexes.isEmpty {
            let inserts = pendingInsertIndexes
            pendingInsertIndexes = []
            insertItems(at: inserts)
            needsInitialReload = false
            return
        }

        if needsInitialReload {
            needsInitialReload = false
            collectionView.reloadData()
            updateActiveStates()
            let startIndex = delegate?.lastBoundIndex ?? 0
            scrollToPage(startIndex, animated: false)
        }
    }

    func reloadAllItems() {
        guard isViewLoaded else {
            needsInitialReload = true
            pendingInsertIndexes = []
            return
        }
        needsInitialReload = false
        pendingInsertIndexes = []
        collectionView.reloadData()
        updateActiveStates()
    }

    func insertItems(at indexes: [Int]) {
        guard isViewLoaded else {
            enqueueInsertItems(at: indexes)
            return
        }
        guard !indexes.isEmpty else { return }
        let indexPaths = indexes.map { IndexPath(item: $0, section: 0) }
        collectionView.performBatchUpdates {
            collectionView.insertItems(at: indexPaths)
        } completion: { [weak self] _ in
            self?.updateActiveStates()
        }
    }

    func scrollToPage(_ index: Int, animated: Bool) {
        let count = delegate?.trackedItemCount ?? 0
        guard count > 0 else { return }
        let clamped = max(0, min(index, count - 1))
        guard collectionView.bounds.height > 0 else {
            pendingScrollIndex = clamped
            visibleIndex = clamped
            return
        }
        let offsetY = CGFloat(clamped) * collectionView.bounds.height
        collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: animated)
        if visibleIndex != clamped {
            visibleIndex = clamped
            updateActiveStates()
            delegate?.onVisibleVideoIndexChanged(clamped)
        }
    }

    func updateActiveStates() {
        guard isViewLoaded else { return }
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { continue }
            configure(cell: cell, at: indexPath.item)
        }
    }

    private func configure(cell: UICollectionViewCell, at index: Int) {
        guard let delegate else { return }
        cell.contentConfiguration = UIHostingConfiguration {
            delegate.pageContent(for: index, visibleIndex: visibleIndex)
        }
        .margins(.all, 0)
    }

    private func pageIndex(from scrollView: UIScrollView) -> Int {
        guard scrollView.bounds.height > 0 else { return 0 }
        let count = delegate?.trackedItemCount ?? 0
        guard count > 0 else { return 0 }
        let raw = Int(round(scrollView.contentOffset.y / scrollView.bounds.height))
        return max(0, min(raw, count - 1))
    }

    private func settleVisiblePage(from scrollView: UIScrollView) {
        let index = pageIndex(from: scrollView)
        guard index != visibleIndex else { return }
        visibleIndex = index
        updateActiveStates()
        delegate?.onVisibleVideoIndexChanged(index)
    }

    private func checkOverscrollPastEnd(_ scrollView: UIScrollView) {
        let count = delegate?.trackedItemCount ?? 0
        guard count > 0, visibleIndex >= count - 1 else { return }
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
        guard scrollView.contentOffset.y > maxOffset + 48 else { return }
        delegate?.onOverscrollPastEnd()
    }
}

extension ShotFeedPagingViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        delegate?.trackedItemCount ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ShotFeedPagingCell.reuseID, for: indexPath)
        configure(cell: cell, at: indexPath.item)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        configure(cell: cell, at: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // Keep the same hosting type as `configure` so UIKit does not tear down
        // UIHostingConfiguration and replace it with Color.
        // visibleIndex: -1 forces isActive/isPreloading false and releases the player.
        guard let delegate else { return }
        cell.contentConfiguration = UIHostingConfiguration {
            delegate.pageContent(for: indexPath.item, visibleIndex: -1)
        }
        .margins(.all, 0)
    }
}

extension ShotFeedPagingViewController: UICollectionViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settleVisiblePage(from: scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            settleVisiblePage(from: scrollView)
        }
        checkOverscrollPastEnd(scrollView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking || scrollView.isDecelerating else { return }
        let index = pageIndex(from: scrollView)
        if index != visibleIndex {
            visibleIndex = index
            updateActiveStates()
        }
        checkOverscrollPastEnd(scrollView)
    }
}

private enum ShotFeedPagingCell {
    static let reuseID = "ShotFeedPagingCell"
}
