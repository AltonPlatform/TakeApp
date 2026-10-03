import Foundation

/// Bounded feed storage that trims old pages while keeping a sliding window around the focus index.
struct WindowedFeed<Item> {
    var items: [Item] = []
    /// Number of items removed from the front across the session (for diagnostics / index remapping).
    private(set) var trimmedPrefixCount = 0
    var windowSize: Int

    init(windowSize: Int = 100) {
        self.windowSize = windowSize
    }

    mutating func replaceAll(_ newItems: [Item]) {
        items = newItems
        trimmedPrefixCount = 0
    }

    /// Appends items and trims when over `windowSize * 1.5`, keeping a window around `focusIndex`.
    /// Returns the adjusted focus index after trimming (or nil if unchanged).
    @discardableResult
    mutating func append(_ newItems: [Item], around focusIndex: Int) -> Int {
        items.append(contentsOf: newItems)
        return trimIfNeeded(around: focusIndex)
    }

    /// Keeps at most `windowSize` items centered on `focusIndex`.
    /// Returns the remapped focus index after trim.
    @discardableResult
    mutating func trimIfNeeded(around focusIndex: Int) -> Int {
        let threshold = Int(Double(windowSize) * 1.5)
        guard items.count > threshold else { return focusIndex }

        let half = windowSize / 2
        let clampedFocus = max(0, min(focusIndex, items.count - 1))
        var start = max(0, clampedFocus - half)
        if start + windowSize > items.count {
            start = max(0, items.count - windowSize)
        }
        let end = min(items.count, start + windowSize)

        if start > 0 || end < items.count {
            trimmedPrefixCount += start
            items = Array(items[start..<end])
            return max(0, clampedFocus - start)
        }
        return focusIndex
    }

    /// Aggressive trim used on memory warnings — keep the newest `windowSize` items.
    mutating func trimToNewest() {
        guard items.count > windowSize else { return }
        let remove = items.count - windowSize
        items = Array(items.suffix(windowSize))
        trimmedPrefixCount += remove
    }
}
