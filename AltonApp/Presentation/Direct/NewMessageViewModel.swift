import Foundation
import Observation

@Observable
@MainActor
final class NewMessageViewModel {
    var query = ""
    var following: [FollowUser] = []
    var searchResults: [FollowUser] = []
    var followingCursor: String?
    var isLoading = false
    var isSearching = false
    var errorMessage: String?
    var openedConversation: DMConversation?

    private let currentUserID: String
    private let userUseCase: UserUseCase
    private let searchUseCase: SearchUseCase
    private let directUseCase: DirectUseCase
    private var searchTask: Task<Void, Never>?

    init(
        currentUserID: String,
        userUseCase: UserUseCase,
        searchUseCase: SearchUseCase,
        directUseCase: DirectUseCase
    ) {
        self.currentUserID = currentUserID
        self.userUseCase = userUseCase
        self.searchUseCase = searchUseCase
        self.directUseCase = directUseCase
    }

    var displayedUsers: [FollowUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? following : searchResults
    }

    var isSearchMode: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadFollowing() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await userUseCase.listFollowing(userID: currentUserID, cursor: nil, limit: 30)
            following = page.users
            followingCursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreFollowing() async {
        guard !isSearchMode, let cursor = followingCursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await userUseCase.listFollowing(userID: currentUserID, cursor: cursor, limit: 30)
            following.append(contentsOf: page.users)
            followingCursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func onQueryChanged() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    func openChat(with user: FollowUser) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            openedConversation = try await directUseCase.openDirect(with: user.id)
        } catch let error as APIError where error == .forbidden {
            errorMessage = "You can't message @\(user.username) — one of you has blocked the other."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func search(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await searchUseCase.searchUsers(query: q, cursor: nil, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = page.users.filter { $0.id != currentUserID }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
