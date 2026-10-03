import Foundation
import Observation
import UIKit

struct CommentTakeItem: Identifiable, Equatable, Sendable {
    var id: String { comment.id }
    let comment: Comment
    /// 0 = top-level comment, 1+ = reply nested in that comment's branch.
    let depth: Int
}

@MainActor
@Observable
final class CommentsViewModel {
    var comments: [Comment] = []
    var draft = ""
    var attachments: [PostAttachment] = []
    var pendingSticker: Sticker?
    var pendingGIF: KlipyGIF?
    var replyParentCommentID: String?
    /// Username for the active reply target — kept even if the comment leaves the windowed list.
    private var replyTargetUsername: String?
    var isLoading = false
    var isSubmitting = false
    var errorMessage: String?

    var canSubmitDraft: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachments.isEmpty || pendingSticker != nil || pendingGIF != nil) && !isSubmitting
    }
    private var nextCursor: String?
    private var window = WindowedFeed<Comment>(windowSize: 100)
    // Read from `deinit` — keep out of Observation tracking.
    @ObservationIgnored private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?

    let postID: String
    let currentUserID: String
    var currentUserAvatarURL: URL?
    let commentsUseCase: CommentsUseCase
    let activityUseCase: PostActivityUseCase
    private let onCommentAdded: (() -> Void)?

    init(
        postID: String,
        currentUserID: String,
        commentsUseCase: CommentsUseCase,
        activityUseCase: PostActivityUseCase,
        onCommentAdded: (() -> Void)? = nil
    ) {
        self.postID = postID
        self.currentUserID = currentUserID
        self.commentsUseCase = commentsUseCase
        self.activityUseCase = activityUseCase
        self.onCommentAdded = onCommentAdded
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

    /// Flat API order → threaded display: each top-level comment followed by its reply branch.
    var takeComments: [CommentTakeItem] {
        CommentTakeTree.build(from: comments)
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await commentsUseCase.fetchComments(postID: postID)
            window.replaceAll(page.comments)
            comments = window.items
            nextCursor = page.nextCursor
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current: Comment) async {
        guard let nextCursor, !nextCursor.isEmpty else { return }
        guard takeComments.last?.comment.id == current.id else { return }

        do {
            let page = try await commentsUseCase.fetchComments(postID: postID, cursor: nextCursor)
            _ = window.append(page.comments, around: max(0, window.items.count - 1))
            comments = window.items
            self.nextCursor = page.nextCursor
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func beginReply(to comment: Comment) {
        // Switching reply targets: drop the previous @mention prefix first.
        stripReplyMentionPrefix()

        // Keep immediate parent so the author of that comment gets the reply notification.
        replyParentCommentID = comment.id
        replyTargetUsername = comment.authorUsername

        guard let username = comment.authorUsername, !username.isEmpty else { return }
        let mention = "@\(username) "
        if draft.hasPrefix(mention) { return }
        let rest = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = rest.isEmpty ? mention : mention + rest
    }

    func clearReplyTarget() {
        stripReplyMentionPrefix()
        replyParentCommentID = nil
        replyTargetUsername = nil
    }

    private func stripReplyMentionPrefix() {
        guard let username = replyTargetUsername, !username.isEmpty else { return }
        let mention = "@\(username) "
        if draft.hasPrefix(mention) {
            draft = String(draft.dropFirst(mention.count))
        }
    }

    func submit(parentCommentID: String? = nil) async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!content.isEmpty || !attachments.isEmpty || pendingSticker != nil || pendingGIF != nil), !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let parentID = parentCommentID ?? replyParentCommentID
        let pendingAttachments = attachments
        let stickerID = pendingSticker?.id
        let pendingGif = pendingGIF.map {
            PendingCommentGif(
                klipyGifID: $0.id,
                sourceURL: $0.downloadURL,
                contentType: $0.contentType,
                width: $0.width,
                height: $0.height
            )
        }

        do {
            let comment = try await commentsUseCase.addComment(
                postID: postID,
                content: content,
                showInFeed: true,
                parentCommentID: parentID,
                attachments: pendingAttachments,
                stickerID: stickerID,
                pendingGif: pendingGif
            )
            insertLocally(commentWithResolvedAvatar(comment))
            draft = ""
            attachments = []
            pendingSticker = nil
            pendingGIF = nil
            replyParentCommentID = nil
            replyTargetUsername = nil
            onCommentAdded?()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removeAttachment(_ attachment: PostAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func appendAttachments(_ items: [PostAttachment]) {
        let remaining = CommentsUseCase.maxAttachments - attachments.count
        guard remaining > 0 else { return }
        attachments.append(contentsOf: items.prefix(remaining))
    }

    /// Attaches a Klipy GIF to the draft. Does not send until the user submits.
    func enqueuePickedGIF(_ gif: KlipyGIF) {
        pendingSticker = nil
        pendingGIF = gif
    }

    func setPendingSticker(_ sticker: Sticker) {
        pendingGIF = nil
        pendingSticker = sticker
    }

    func clearPendingSticker() {
        pendingSticker = nil
    }

    func clearPendingGIF() {
        pendingGIF = nil
    }

    private func commentWithResolvedAvatar(_ comment: Comment) -> Comment {
        if comment.authorAvatarURL != nil { return comment }
        if comment.authorID == currentUserID {
            return comment.fillingAuthorAvatar(currentUserAvatarURL)
        }
        let siblingAvatar = comments.first(where: {
            $0.authorID == comment.authorID && $0.authorAvatarURL != nil
        })?.authorAvatarURL
        return comment.fillingAuthorAvatar(siblingAvatar)
    }

    /// Inserts into storage so `takeComments` places the reply under its branch.
    private func insertLocally(_ comment: Comment) {
        if comment.parentCommentID == nil {
            comments.insert(comment, at: 0)
        } else {
            comments.append(comment)
        }
        window.items = comments
        _ = window.trimIfNeeded(around: max(0, comments.count - 1))
        comments = window.items
    }

    func toggleCommentLike(comment: Comment) async {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }

        let previousLiked = comments[index].isLiked
        let previousCount = comments[index].likeCount
        comments[index].isLiked.toggle()
        comments[index].likeCount = max(0, previousCount + (comments[index].isLiked ? 1 : -1))

        do {
            let result = try await commentsUseCase.toggleCommentLike(commentID: comment.id)
            if let updatedIndex = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[updatedIndex].isLiked = result.active
                comments[updatedIndex].likeCount = result.count
            }
        } catch {
            if let rollbackIndex = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[rollbackIndex].isLiked = previousLiked
                comments[rollbackIndex].likeCount = previousCount
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(comment: Comment) async {
        guard comment.authorID == currentUserID else { return }
        do {
            try await commentsUseCase.deleteComment(commentID: comment.id)
            let removedIDs = CommentTakeTree.descendantIDs(of: comment.id, in: comments).union([comment.id])
            comments.removeAll { removedIDs.contains($0.id) }
            window.items = comments
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func handleMemoryWarning() {
        window.trimToNewest()
        comments = window.items
    }
}

enum CommentTakeTree {
    /// Groups replies under their top-level root so each conversation is one branch.
    static func build(from comments: [Comment]) -> [CommentTakeItem] {
        guard !comments.isEmpty else { return [] }

        let byID = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })
        let roots = comments.filter { $0.parentCommentID == nil }

        var repliesByRoot: [String: [Comment]] = [:]
        for comment in comments where comment.parentCommentID != nil {
            let rootKey = rootID(for: comment, byID: byID)
            repliesByRoot[rootKey, default: []].append(comment)
        }

        for key in repliesByRoot.keys {
            repliesByRoot[key]?.sort { lhs, rhs in
                let l = lhs.createdAt ?? .distantPast
                let r = rhs.createdAt ?? .distantPast
                if l != r { return l < r }
                return lhs.id < rhs.id
            }
        }

        var result: [CommentTakeItem] = []
        var consumedRoots = Set<String>()

        for root in roots {
            consumedRoots.insert(root.id)
            result.append(CommentTakeItem(comment: root, depth: 0))
            for reply in repliesByRoot[root.id] ?? [] {
                result.append(CommentTakeItem(comment: reply, depth: 1))
            }
        }

        // Orphan replies whose root isn't on this page — still show as an indented branch.
        for (rootKey, replies) in repliesByRoot where !consumedRoots.contains(rootKey) {
            for reply in replies {
                result.append(CommentTakeItem(comment: reply, depth: 1))
            }
        }

        return result
    }

    static func rootID(for comment: Comment, byID: [String: Comment]) -> String {
        var current = comment
        var seen = Set<String>([comment.id])
        while let parentID = current.parentCommentID {
            if seen.contains(parentID) { break }
            seen.insert(parentID)
            guard let parent = byID[parentID] else {
                return parentID
            }
            current = parent
        }
        return current.id
    }

    static func descendantIDs(of rootID: String, in comments: [Comment]) -> Set<String> {
        let byParent = Dictionary(grouping: comments.compactMap { c -> (String, Comment)? in
            guard let parent = c.parentCommentID else { return nil }
            return (parent, c)
        }, by: \.0).mapValues { $0.map(\.1) }

        var result = Set<String>()
        var stack = byParent[rootID]?.map(\.id) ?? []
        while let id = stack.popLast() {
            guard result.insert(id).inserted else { continue }
            stack.append(contentsOf: byParent[id]?.map(\.id) ?? [])
        }
        return result
    }
}
