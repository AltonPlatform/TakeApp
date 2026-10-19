import Foundation
import UIKit

/// Shared date formatting for chat rows.
/// Avoids allocating ISO8601DateFormatter / DateFormatter on every body evaluation.
enum ChatDateCache {
    private static let lock = NSLock()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let mediumDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static var parsed: [String: Date] = [:]
    private static let maxEntries = 2000

    static func date(_ iso: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = parsed[iso] { return cached }
        let value = isoFractional.date(from: iso) ?? isoBasic.date(from: iso)
        guard let value else { return nil }
        if parsed.count >= maxEntries {
            parsed.removeAll(keepingCapacity: true)
        }
        parsed[iso] = value
        return value
    }

    static func time(_ iso: String) -> String {
        guard let d = date(iso) else { return "" }
        lock.lock()
        defer { lock.unlock() }
        return timeFormatter.string(from: d)
    }

    static func dayKey(_ iso: String) -> String {
        guard let d = date(iso) else { return iso }
        lock.lock()
        defer { lock.unlock() }
        return dayKeyFormatter.string(from: d)
    }

    static func stampNow() -> String {
        lock.lock()
        defer { lock.unlock() }
        return isoFractional.string(from: Date())
    }

    static func dayLabel(_ iso: String) -> String {
        guard let d = date(iso) else { return "" }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        lock.lock()
        defer { lock.unlock() }
        return mediumDayFormatter.string(from: d)
    }

    /// Clears the parse cache (tests).
    static func resetForTests() {
        lock.lock()
        parsed.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}

/// Decodes optimistic DM local JPEG previews once per clientMsgID.
enum ChatLocalImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 40
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    static func store(clientMsgID: String, image: UIImage, cost: Int) {
        cache.setObject(image, forKey: clientMsgID as NSString, cost: cost)
    }

    static func image(clientMsgID: String, data: Data) -> UIImage? {
        let key = clientMsgID as NSString
        if let hit = cache.object(forKey: key) { return hit }
        return nil
    }

    /// Decodes off the caller. Safe to call from a background queue; `NSCache` is thread-safe.
    static func storeDecoded(clientMsgID: String, data: Data) {
        guard let image = UIImage(data: data) else { return }
        store(clientMsgID: clientMsgID, image: image, cost: data.count)
    }

    static func remove(clientMsgID: String) {
        cache.removeObject(forKey: clientMsgID as NSString)
    }
}
