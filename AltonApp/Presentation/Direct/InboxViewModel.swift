import Foundation
import Observation

@Observable
@MainActor
final class InboxViewModel {
    private let useCase: DirectUseCase
    private let realtime: RealtimeClient
    private let repository: DirectRepository

    var conversations: [DMConversation] = []
    var nextCursor: String?
    var isLoading = false
    var errorMessage: String?
    var folder: String = "primary"
    var ownerUserID: String?

    private var eventsTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt = 0

    init(useCase: DirectUseCase, realtime: RealtimeClient, repository: DirectRepository) {
        self.useCase = useCase
        self.realtime = realtime
        self.repository = repository
    }

    func start() {
        eventsTask?.cancel()
        refreshTask?.cancel()
        eventsTask = Task { [weak self] in
            guard let self else { return }
            await realtime.switchGate.wait()
            await realtime.connect()
            let epoch = await realtime.currentStreamEpoch()
            for await event in await realtime.events() {
                guard await realtime.currentStreamEpoch() == epoch else { return }
                guard !Task.isCancelled else { return }
                await self.handle(event)
            }
        }
        refreshTask = Task { await refresh() }
    }

    func stop() {
        refreshGeneration &+= 1
        isLoading = false
        eventsTask?.cancel()
        eventsTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Drops the previous account's list before the next inbox frame.
    func adopt(userID: String) {
        guard ownerUserID != userID else { return }
        stop()
        ownerUserID = userID
        conversations = []
        nextCursor = nil
    }

    func refresh() async {
        // Invalidate any in-flight loadMore so it cannot append onto a replaced list.
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let owner = ownerUserID
        isLoading = true
        errorMessage = nil
        defer {
            guard generation == refreshGeneration else { return }
            isLoading = false
        }
        do {
            let page = try await useCase.inbox(folder: folder, cursor: nil)
            guard generation == refreshGeneration, owner == ownerUserID, !Task.isCancelled else { return }
            if conversations.map(\.id) != page.conversations.map(\.id)
                || conversations != page.conversations
            {
                conversations = page.conversations
            }
            nextCursor = page.nextCursor
            warmCache(for: page.conversations)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        let generation = refreshGeneration
        let owner = ownerUserID
        isLoading = true
        defer {
            guard generation == refreshGeneration else { return }
            isLoading = false
        }
        do {
            let page = try await useCase.inbox(folder: folder, cursor: cursor)
            guard generation == refreshGeneration, owner == ownerUserID else { return }
            conversations.append(contentsOf: page.conversations)
            nextCursor = page.nextCursor
            warmCache(for: page.conversations)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ event: RealtimeEvent) async {
        switch event {
        case .inboxUpdate(let conversationID, let lastSeq, let previewText, let previewKind, let previewSeq, let senderID):
            guard let ownerUserID else { return }
            if let idx = conversations.firstIndex(where: { $0.id == conversationID }) {
                if let previewSeq, conversations[idx].lastReadSeq >= previewSeq {
                    conversations[idx].lastReadSeq = max(conversations[idx].lastReadSeq, lastSeq)
                }
                if previewSeq == nil, senderID == ownerUserID {
                    conversations[idx].lastReadSeq = max(conversations[idx].lastReadSeq, lastSeq)
                }
                conversations[idx].lastSeq = max(conversations[idx].lastSeq, lastSeq)
                conversations[idx].previewText = previewText
                conversations[idx].previewKind = previewKind
                conversations[idx].unreadCount = max(0, conversations[idx].lastSeq - conversations[idx].lastReadSeq)
                let item = conversations.remove(at: idx)
                conversations.insert(item, at: 0)
                warmCache(for: [item])
            } else {
                await refresh()
            }
        case .conversationUpdated(let update):
            guard ownerUserID != nil else { return }
            if let idx = conversations.firstIndex(where: { $0.id == update.conversationID }) {
                conversations[idx] = conversations[idx].applying(update)
            } else {
                await refresh()
            }
        case .connected:
            guard ownerUserID != nil else { return }
            await refresh()
        default:
            break
        }
    }

    /// Pulls the latest page into the message cache before the chat is opened.
    private func warmCache(for conversations: [DMConversation]) {
        let targets = conversations
        Task { [repository] in
            await repository.prefetchHistories(targets)
        }
    }
}
