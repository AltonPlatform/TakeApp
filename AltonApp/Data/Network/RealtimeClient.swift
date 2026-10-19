import Foundation

/// Lets a synchronous account switch block new inbox subscriptions until `disconnect` finishes.
final class RealtimeSwitchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never> = Task {}

    func arm(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func wait() async {
        let current: Task<Void, Never>
        lock.lock()
        current = task
        lock.unlock()
        await current.value
    }
}

enum RealtimeEvent: Sendable {
    case connected
    case disconnected
    case ack(requestID: String, messageID: String, seq: Int64, conversationID: String, createdAt: String)
    case messageNew(DMMessage)
    case messageUpdated(DMMessage)
    case messageReaction(conversationID: String, messageID: String, reactions: [DMMessageReaction])
    case messageChecklist(conversationID: String, messageID: String, marks: [DMChecklistMark])
    case messagePoll(
        conversationID: String,
        messageID: String,
        tallies: [DMPollTally],
        totalVoters: Int,
        voters: [DMPollVote],
        closed: Bool,
        myOptionIDs: [Int]?
    )
    case inboxUpdate(
        conversationID: String,
        lastSeq: Int64,
        previewText: String,
        previewKind: String,
        previewSeq: Int64?,
        senderID: String?
    )
    case conversationUpdated(DMGroupUpdate)
    case read(conversationID: String, userID: String, seq: Int64)
    case typing(conversationID: String, userID: String)
    case error(code: String, message: String?)
}

actor RealtimeClient {
    nonisolated let switchGate = RealtimeSwitchGate()
    private let wsURL: URL
    private let tokenStore: TokenStoreProtocol
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var shouldRun = false
    private var isConnecting = false
    private var isAuthed = false
    /// Access token the live socket authenticated with. A different token must open a new socket.
    private var authedAccessToken: String?
    private var connectingAccessToken: String?
    /// Bumped on disconnect so a socket opened for the previous account cannot finish auth.
    private var socketGeneration: UInt = 0
    /// Bumped when an account switch drops the socket. Listeners from the previous epoch must stop.
    private var streamEpoch: UInt = 0
    private var pending: [(id: String, payload: [String: Any])] = []
    private var continuations: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]

    init(
        wsURL: URL = AppEnvironment.current.realtimeWebSocketURL,
        tokenStore: TokenStoreProtocol
    ) {
        self.wsURL = wsURL
        self.tokenStore = tokenStore
    }

    func events() -> AsyncStream<RealtimeEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.addContinuation(id: id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    private func addContinuation(id: UUID, _ continuation: AsyncStream<RealtimeEvent>.Continuation) {
        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }

    private func emit(_ event: RealtimeEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Idempotent when already connected with a live task. After `disconnect()`, opens a new socket
    /// so a subsequent login cannot reuse the previous account's WebSocket.
    func connect() async {
        shouldRun = true
        let token = (try? tokenStore.load())?.accessToken
        if task != nil, isAuthed, token != nil, token == authedAccessToken {
            return
        }
        if isConnecting, token != nil, token == connectingAccessToken {
            return
        }
        if task != nil || isAuthed || isConnecting {
            let switchingAccount = authedAccessToken != nil && token != authedAccessToken
            disconnect(discardPending: switchingAccount)
            shouldRun = true
        }
        await openSocket()
    }

    /// - Parameter discardPending: When `true` (logout / session end), drop unsent envelopes so
    ///   the next account cannot flush them after `auth.ok`. Keep `false` for background
    ///   disconnect so offline sends still flush on the next connect of the same user.
    func disconnect(discardPending: Bool = false) {
        socketGeneration &+= 1
        shouldRun = false
        isConnecting = false
        isAuthed = false
        authedAccessToken = nil
        connectingAccessToken = nil
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        task?.cancel()
        task = nil
        session = nil
        if discardPending {
            pending.removeAll()
            streamEpoch &+= 1
            let stale = continuations
            continuations.removeAll()
            for continuation in stale.values {
                continuation.finish()
            }
        }
        emit(.disconnected)
    }

    func currentStreamEpoch() -> UInt {
        streamEpoch
    }

    func sendMessage(
        conversationID: String? = nil,
        recipientID: String? = nil,
        clientMsgID: String,
        kind: String,
        body: String? = nil,
        postID: String? = nil,
        replyToSeq: Int64? = nil,
        payload: [String: Any]? = nil
    ) async -> String {
        var d: [String: Any] = [
            "client_msg_id": clientMsgID,
            "kind": kind,
        ]
        if let conversationID { d["conversation_id"] = conversationID }
        if let recipientID { d["recipient_id"] = recipientID }
        if let body { d["body"] = body }
        if let postID { d["post_id"] = postID }
        if let replyToSeq { d["reply_to_seq"] = replyToSeq }
        if let payload { d["payload"] = payload }
        let requestID = UUID().uuidString
        let envelope: [String: Any] = ["t": "msg.send", "id": requestID, "d": d]
        pending.append((requestID, envelope))
        if isAuthed {
            await sendJSON(envelope)
        }
        return requestID
    }

    func markRead(conversationID: String, seq: Int64) async {
        let envelope: [String: Any] = [
            "t": "msg.read",
            "id": UUID().uuidString,
            "d": ["conversation_id": conversationID, "seq": seq],
        ]
        await sendJSON(envelope)
    }

    func typing(conversationID: String) async {
        let envelope: [String: Any] = [
            "t": "typing",
            "id": UUID().uuidString,
            "d": ["conversation_id": conversationID],
        ]
        await sendJSON(envelope)
    }

    private func openSocket() async {
        let generation = socketGeneration
        guard shouldRun, generation == socketGeneration else { return }
        guard !isConnecting else { return }
        isConnecting = true
        isAuthed = false
        defer { isConnecting = false }

        guard let tokens = try? tokenStore.load() else {
            emit(.error(code: "no_token", message: nil))
            return
        }
        connectingAccessToken = tokens.accessToken
        guard generation == socketGeneration, shouldRun else { return }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.session = session
        let task = session.webSocketTask(with: wsURL)
        self.task = task
        task.resume()

        guard generation == socketGeneration, shouldRun else {
            retire(task)
            return
        }

        let auth: [String: Any] = [
            "t": "auth",
            "d": ["token": tokens.accessToken],
        ]
        await sendJSON(auth)
        guard generation == socketGeneration, shouldRun else {
            retire(task)
            return
        }

        receiveTask?.cancel()
        receiveTask = Task { await self.receiveLoop() }
        heartbeatTask?.cancel()
        heartbeatTask = Task { await self.heartbeatLoop() }
    }

    /// Cancel only the socket this attempt opened. A newer connect may already own `self.task`.
    private func retire(_ task: URLSessionWebSocketTask) {
        guard self.task === task else { return }
        task.cancel()
        self.task = nil
        session = nil
    }

    private func flushPending() async {
        let items = pending
        for item in items {
            await sendJSON(item.payload)
        }
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled && shouldRun {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            await sendJSON(["t": "ping", "id": UUID().uuidString])
        }
    }

    private func receiveLoop() async {
        let generation = socketGeneration
        guard let socket = task else { return }
        while !Task.isCancelled, generation == socketGeneration {
            do {
                let message = try await socket.receive()
                guard generation == socketGeneration else { return }
                switch message {
                case .string(let text):
                    await handleFrame(text, generation: generation)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleFrame(text, generation: generation)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard generation == socketGeneration else { return }
                isAuthed = false
                if self.task === socket {
                    self.task = nil
                }
                emit(.disconnected)
                await scheduleReconnect()
                return
            }
        }
    }

    private func scheduleReconnect() async {
        guard shouldRun else { return }
        reconnectAttempt += 1
        let base = min(30.0, pow(2.0, Double(min(reconnectAttempt, 5))))
        let jitter = Double.random(in: 0...0.5)
        try? await Task.sleep(nanoseconds: UInt64((base + jitter) * 1_000_000_000))
        await openSocket()
    }

    private func handleFrame(_ text: String, generation: UInt) async {
        guard generation == socketGeneration else { return }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["t"] as? String else { return }

        switch type {
        case "auth.ok":
            reconnectAttempt = 0
            isAuthed = true
            authedAccessToken = connectingAccessToken
            emit(.connected)
            await flushPending()
        case "pong":
            break
        case "ack":
            let id = obj["id"] as? String ?? ""
            let d = obj["d"] as? [String: Any] ?? [:]
            pending.removeAll { $0.id == id }
            emit(.ack(
                requestID: id,
                messageID: d["message_id"] as? String ?? "",
                seq: (d["seq"] as? NSNumber)?.int64Value ?? 0,
                conversationID: d["conversation_id"] as? String ?? "",
                createdAt: d["created_at"] as? String ?? ""
            ))
        case "msg.new":
            if let d = obj["d"] as? [String: Any],
               let msgObj = d["message"] as? [String: Any],
               let msg = parseMessage(msgObj) {
                emit(.messageNew(msg))
            }
        case "msg.updated":
            if let d = obj["d"] as? [String: Any],
               let msgObj = d["message"] as? [String: Any],
               let msg = parseMessage(msgObj) {
                emit(.messageUpdated(msg))
            }
        case "msg.reaction":
            let d = obj["d"] as? [String: Any] ?? [:]
            let reactions = Self.parseReactions(d["reactions"])
            emit(.messageReaction(
                conversationID: d["conversation_id"] as? String ?? "",
                messageID: d["message_id"] as? String ?? "",
                reactions: reactions
            ))
        case "msg.poll":
            let d = obj["d"] as? [String: Any] ?? [:]
            let myOptionIDs = (d["my_option_ids"] as? [Any])?.compactMap { item -> Int? in
                if let value = item as? Int { return value }
                if let value = item as? NSNumber { return value.intValue }
                return nil
            }
            emit(.messagePoll(
                conversationID: d["conversation_id"] as? String ?? "",
                messageID: d["message_id"] as? String ?? "",
                tallies: DMPayloadCodec.pollTallies(from: d["tallies"]),
                totalVoters: (d["total_voters"] as? NSNumber)?.intValue ?? 0,
                voters: DMPayloadCodec.pollVotes(from: d["voters"]),
                closed: d["closed"] as? Bool ?? false,
                myOptionIDs: d["my_option_ids"] == nil ? nil : myOptionIDs
            ))
        case "msg.checklist":
            let d = obj["d"] as? [String: Any] ?? [:]
            emit(.messageChecklist(
                conversationID: d["conversation_id"] as? String ?? "",
                messageID: d["message_id"] as? String ?? "",
                marks: DMPayloadCodec.marks(from: d["marks"])
            ))
        case "inbox.update":
            let d = obj["d"] as? [String: Any] ?? [:]
            emit(.inboxUpdate(
                conversationID: d["conversation_id"] as? String ?? "",
                lastSeq: (d["last_seq"] as? NSNumber)?.int64Value ?? 0,
                previewText: d["preview_text"] as? String ?? "",
                previewKind: d["preview_kind"] as? String ?? "text",
                previewSeq: (d["preview_seq"] as? NSNumber)?.int64Value,
                senderID: d["sender_id"] as? String
            ))
        case "conversation.updated":
            let d = obj["d"] as? [String: Any] ?? [:]
            emit(.conversationUpdated(Self.groupUpdate(from: d)))
        case "read":
            let d = obj["d"] as? [String: Any] ?? [:]
            emit(.read(
                conversationID: d["conversation_id"] as? String ?? "",
                userID: d["user_id"] as? String ?? "",
                seq: (d["seq"] as? NSNumber)?.int64Value ?? 0
            ))
        case "typing":
            let d = obj["d"] as? [String: Any] ?? [:]
            emit(.typing(
                conversationID: d["conversation_id"] as? String ?? "",
                userID: d["user_id"] as? String ?? ""
            ))
        case "error":
            let d = obj["d"] as? [String: Any] ?? [:]
            emit(.error(code: d["code"] as? String ?? "error", message: d["message"] as? String))
        default:
            break
        }
    }

    static func groupUpdate(from d: [String: Any]) -> DMGroupUpdate {
        let members = (d["members"] as? [[String: Any]] ?? []).compactMap { row -> DMConversationMember? in
            guard let userID = row["user_id"] as? String, !userID.isEmpty else { return nil }
            return DMConversationMember(
                userID: userID,
                username: row["username"] as? String ?? "",
                displayName: row["display_name"] as? String ?? "",
                avatarURL: (row["avatar_url"] as? String).flatMap(URL.init(string:)),
                role: row["role"] as? String ?? "member",
                rights: Set(row["rights"] as? [String] ?? [])
            )
        }
        let count = (d["member_count"] as? NSNumber)?.intValue ?? members.count
        return DMGroupUpdate(
            conversationID: d["conversation_id"] as? String ?? "",
            title: d["title"] as? String ?? "",
            groupAvatarURL: (d["group_avatar_url"] as? String).flatMap(URL.init(string:)),
            visibility: d["visibility"] as? String ?? "private",
            memberCount: count,
            members: members
        )
    }

    private func parseMessage(_ d: [String: Any]) -> DMMessage? {
        guard let id = d["id"] as? String,
              let conversationID = d["conversation_id"] as? String,
              let senderID = d["sender_id"] as? String else { return nil }
        let seq = (d["seq"] as? NSNumber)?.int64Value ?? 0
        let kind = DMMessageKind(rawValue: d["kind"] as? String ?? "text") ?? .text
        let parsed = DMPayloadCodec.applyPayload(kind: kind, object: d["payload"] as? [String: Any])
        return DMMessage(
            id: id,
            conversationID: conversationID,
            seq: seq,
            senderID: senderID,
            kind: kind,
            body: d["body"] as? String ?? "",
            postID: d["post_id"] as? String,
            postType: d["post_type"] as? String,
            replyToSeq: (d["reply_to_seq"] as? NSNumber)?.int64Value,
            clientMsgID: d["client_msg_id"] as? String ?? id,
            createdAt: d["created_at"] as? String ?? "",
            editedAt: d["edited_at"] as? String,
            deletedAt: d["deleted_at"] as? String,
            mediaURL: (d["media_url"] as? String).flatMap(URL.init(string:)),
            mediaThumbURL: (d["media_thumb_url"] as? String).flatMap(URL.init(string:))
                ?? (d["media_url"] as? String).flatMap(URL.init(string:)),
            mediaWidth: (d["media_width"] as? NSNumber)?.intValue,
            mediaHeight: (d["media_height"] as? NSNumber)?.intValue,
            mediaStatus: d["media_status"] as? String,
            forwardedFromUserID: d["forwarded_from_user_id"] as? String,
            forwardedFromUsername: d["forwarded_from_username"] as? String,
            reactions: Self.parseReactions(d["reactions"]),
            localImageData: nil,
            isPending: false,
            isFailed: false,
            location: parsed.0,
            checklist: parsed.1,
            checklistMarks: DMPayloadCodec.marks(from: d["checklist_marks"]),
            poll: parsed.2,
            pollVotes: DMPayloadCodec.pollVotes(from: d["poll_votes"]),
            pollTallies: DMPayloadCodec.pollTallies(from: d["poll_tallies"]),
            pollTotalVoters: (d["poll_total_voters"] as? NSNumber)?.intValue ?? 0,
            stickerID: kind == .sticker ? (d["payload"] as? [String: Any])?["sticker_id"] as? String : nil
        )
    }

    private static func parseReactions(_ raw: Any?) -> [DMMessageReaction] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let userID = item["user_id"] as? String,
                  let emoji = item["emoji"] as? String else { return nil }
            return DMMessageReaction(userID: userID, emoji: emoji)
        }
    }

    func setChecklistItem(messageID: String, itemID: Int, done: Bool) async {
        let requestID = UUID().uuidString
        let envelope: [String: Any] = [
            "t": "msg.checklist",
            "id": requestID,
            "d": [
                "message_id": messageID,
                "item_id": itemID,
                "done": done,
            ],
        ]
        if isAuthed {
            await sendJSON(envelope)
        } else {
            pending.append((id: requestID, payload: envelope))
        }
    }

    func setReaction(messageID: String, emoji: String) async {
        let requestID = UUID().uuidString
        let envelope: [String: Any] = [
            "t": "msg.reaction",
            "id": requestID,
            "d": [
                "message_id": messageID,
                "emoji": emoji,
            ],
        ]
        if isAuthed {
            await sendJSON(envelope)
        } else {
            pending.append((id: requestID, payload: envelope))
        }
    }

    private func sendJSON(_ object: [String: Any]) async {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await task.send(.string(text))
    }
}
