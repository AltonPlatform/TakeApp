import SwiftUI

/// Simple @mention autocomplete list backed by user search.
struct MentionAutocompleteView: View {
    let users: [FollowUser]
    var onSelect: (FollowUser) -> Void

    var body: some View {
        MentionOverlayView(candidates: users, query: "", onSelect: onSelect)
    }
}

struct ComposerTextReplacement: Equatable {
    var location: Int
    var length: Int
    var text: String
}

struct PendingComposerEdit: Equatable {
    var id: Int
    var insert: String?
    var replacement: ComposerTextReplacement?
}

struct ActiveMention: Equatable {
    var query: String
    var range: NSRange
}

enum MentionTyping {
    /// Mention token that contains the caret. Text after the caret does not end the token.
    static func activeMention(in text: String, utf16Caret: Int) -> ActiveMention? {
        let ns = text as NSString
        guard utf16Caret >= 0, utf16Caret <= ns.length, ns.length > 0 else { return nil }

        var index = utf16Caret
        while index > 0 {
            let character = ns.substring(with: NSRange(location: index - 1, length: 1))
            if character == "@" {
                if index > 1 {
                    let before = ns.substring(with: NSRange(location: index - 2, length: 1))
                    let nameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
                    if before.rangeOfCharacter(from: nameCharacters) != nil {
                        return nil
                    }
                }
                let query = ns.substring(with: NSRange(location: index, length: utf16Caret - index))
                if query.contains(where: { $0.isWhitespace || $0.isNewline }) {
                    return nil
                }
                return ActiveMention(
                    query: query,
                    range: NSRange(location: index - 1, length: utf16Caret - index + 1)
                )
            }
            if character.contains(where: { $0.isWhitespace || $0.isNewline }) {
                return nil
            }
            let nameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
            if character.rangeOfCharacter(from: nameCharacters) == nil {
                return nil
            }
            index -= 1
        }
        return nil
    }

    /// Query after the active trailing `@` (nil when not composing a mention).
    static func activeQuery(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        if atIndex > text.startIndex {
            let before = text[text.index(before: atIndex)]
            if before.isLetter || before.isNumber || before == "_" {
                return nil
            }
        }

        let after = text[text.index(after: atIndex)...]
        if after.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return nil
        }
        return String(after)
    }

    static func inserting(username: String, into text: String) -> String {
        guard let atIndex = text.lastIndex(of: "@") else {
            let needsSpace = !text.isEmpty && !text.hasSuffix(" ")
            return text + (needsSpace ? " @" : "@") + username + " "
        }
        let prefix = text[..<atIndex]
        return "\(prefix)@\(username) "
    }

    static func appendMentionTrigger(to text: String) -> String {
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            return text + "@"
        }
        if text.hasSuffix("@") {
            return text
        }
        return text + " @"
    }
}

@MainActor
enum MentionNavigation {
    static func resolveUserID(username: String, searchUseCase: SearchUseCase) async -> String? {
        await searchUseCase.resolveUserID(username: username)
    }
}

@MainActor
@Observable
final class MentionPickerModel {
    var users: [FollowUser] = []
    var isVisible = false
    var activeRange: NSRange?

    private var searchTask: Task<Void, Never>?
    private let searchUseCase: SearchUseCase?

    init(searchUseCase: SearchUseCase?) {
        self.searchUseCase = searchUseCase
    }

    func update(from text: String) {
        guard let query = MentionTyping.activeQuery(in: text) else {
            hide()
            return
        }
        activeRange = nil
        isVisible = true
        search(query: query)
    }

    func update(plainText: String, utf16Caret: Int) {
        guard utf16Caret >= 0,
              let mention = MentionTyping.activeMention(in: plainText, utf16Caret: utf16Caret) else {
            hide()
            return
        }
        activeRange = mention.range
        isVisible = true
        search(query: mention.query)
    }

    func showAfterInsertingAt(into text: inout String) {
        text = MentionTyping.appendMentionTrigger(to: text)
        isVisible = true
        search(query: "")
    }

    func insert(_ user: FollowUser, into text: inout String) {
        text = MentionTyping.inserting(username: user.username, into: text)
        hide()
    }

    func hide() {
        searchTask?.cancel()
        searchTask = nil
        guard isVisible || activeRange != nil || !users.isEmpty else { return }
        isVisible = false
        users = []
        activeRange = nil
    }

    private func search(query: String) {
        guard let searchUseCase else {
            users = []
            return
        }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            // Empty query after bare `@` — keep list empty until the user types.
            guard !q.isEmpty else {
                users = []
                return
            }
            do {
                let page = try await searchUseCase.searchUsers(query: q, cursor: nil, limit: 8)
                guard !Task.isCancelled else { return }
                users = page.users
            } catch {
                guard !Task.isCancelled else { return }
                users = []
            }
        }
    }
}

private extension FollowUser {
    func asUser() -> User {
        User(
            id: id,
            username: username,
            displayName: displayName,
            bio: nil,
            avatarURL: avatarURL,
            suiWallet: nil,
            createdAt: nil
        )
    }
}
