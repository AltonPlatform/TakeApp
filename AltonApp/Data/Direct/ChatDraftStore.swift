import Foundation

/// Persists per-conversation DM composer drafts in UserDefaults.
/// Keyed by account (`dm.drafts.<userID>`), capped at 100 entries with a 30-day TTL.
struct ChatDraftStore: Sendable {
    static let maxDraftCount = 100
    static let maxAgeDays = 30

    private let defaults: UserDefaults
    private let userID: String

    init(userID: String, defaults: UserDefaults = .standard) {
        self.userID = userID
        self.defaults = defaults
    }

    private var storageKey: String { "dm.drafts.\(userID)" }

    func load(conversationID: String) -> String? {
        var map = loadMap()
        pruneExpired(&map)
        guard let entry = map[conversationID] else {
            saveMap(map)
            return nil
        }
        saveMap(map)
        let text = entry.text
        return ChatComposerLimits.hasNonWhitespaceContent(text) ? text : nil
    }

    func save(conversationID: String, text: String, updatedAt: Date = Date()) {
        var map = loadMap()
        pruneExpired(&map)
        let trimmedEmpty = !ChatComposerLimits.hasNonWhitespaceContent(text)
        if trimmedEmpty {
            map.removeValue(forKey: conversationID)
        } else {
            map[conversationID] = Entry(text: text, updatedAt: updatedAt)
            enforceLimit(&map)
        }
        saveMap(map)
    }

    func clear(conversationID: String) {
        var map = loadMap()
        map.removeValue(forKey: conversationID)
        saveMap(map)
    }

    /// Removes every draft for this account (logout / account switch).
    func clearAll() {
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: - Private

    private struct Entry: Codable, Equatable {
        var text: String
        var updatedAt: Date
    }

    private func loadMap() -> [String: Entry] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func saveMap(_ map: [String: Entry]) {
        if map.isEmpty {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func pruneExpired(_ map: inout [String: Entry]) {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -Self.maxAgeDays,
            to: Date()
        ) ?? Date.distantPast
        map = map.filter { $0.value.updatedAt >= cutoff }
    }

    private func enforceLimit(_ map: inout [String: Entry]) {
        guard map.count > Self.maxDraftCount else { return }
        let sorted = map.sorted { $0.value.updatedAt < $1.value.updatedAt }
        let overflow = map.count - Self.maxDraftCount
        for i in 0..<overflow {
            map.removeValue(forKey: sorted[i].key)
        }
    }
}
