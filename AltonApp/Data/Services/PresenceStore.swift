import Foundation
import Observation

/// Batches visible avatar user ids and refreshes online status via `GET /presence`.
@Observable
@MainActor
final class PresenceStore {
    private let apiClient: APIClient
    private var onlineIDs: Set<String> = []
    @ObservationIgnored private var trackedIDs: Set<String> = []
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIDs: Set<String> = []

    private let cacheTTL: TimeInterval = 30

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func isOnline(_ userID: String) -> Bool {
        guard !userID.isEmpty else { return false }
        return onlineIDs.contains(userID)
    }

    /// Register a visible avatar; schedules a batched refresh.
    func track(_ userID: String) {
        guard !userID.isEmpty else { return }
        trackedIDs.insert(userID)
        if let at = fetchedAt[userID], Date().timeIntervalSince(at) < cacheTTL {
            return
        }
        pendingIDs.insert(userID)
        scheduleFlush()
    }

    func refreshIfNeeded(_ userIDs: [String]) {
        for id in userIDs {
            track(id)
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self?.flush()
        }
    }

    private func flush() async {
        flushTask = nil
        let batch = Array(pendingIDs.prefix(100))
        pendingIDs.subtract(batch)
        guard !batch.isEmpty else { return }

        struct PresenceResponse: Decodable {
            let onlineUserIDs: [String]?
            enum CodingKeys: String, CodingKey {
                case onlineUserIDs = "online_user_ids"
            }
        }

        do {
            let response: PresenceResponse = try await apiClient.request(
                .presence(userIDs: batch)
            )
            let online = Set(response.onlineUserIDs ?? [])
            let now = Date()
            for id in batch {
                fetchedAt[id] = now
                if online.contains(id) {
                    onlineIDs.insert(id)
                } else {
                    onlineIDs.remove(id)
                }
            }
        } catch {
            // Soft-fail: leave previous cache; retry later when tracked again.
            for id in batch {
                fetchedAt.removeValue(forKey: id)
            }
        }

        if !pendingIDs.isEmpty {
            scheduleFlush()
        }
    }
}
