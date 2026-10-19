import SwiftUI

struct DirectShareDependencies {
    let directUseCase: DirectUseCase
    let userUseCase: UserUseCase
    let searchUseCase: SearchUseCase
    let currentUserID: String
}

/// Pick up to 10 recipients (recent chats, following, or search) and share a Take/Shot.
struct DirectSharePickerView: View {
    let postID: String
    let deps: DirectShareDependencies
    let onFinish: (_ sent: Bool) -> Void

    @State private var recent: [DMConversation] = []
    @State private var following: [FollowUser] = []
    @State private var followingCursor: String?
    @State private var searchResults: [FollowUser] = []
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var isSending = false
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && recent.isEmpty && following.isEmpty && !isSearchMode {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rowsEmpty {
                    ContentUnavailableView(
                        isSearchMode ? "No people found" : "No one to share with yet",
                        systemImage: "person.2",
                        description: Text(
                            isSearchMode
                                ? "Try a different name or username."
                                : "Follow people or start a chat, then share here."
                        )
                    )
                } else {
                    List {
                        if isSearchMode {
                            Section {
                                ForEach(searchResults) { user in
                                    personRow(
                                        id: user.id,
                                        title: user.displayName.isEmpty ? user.username : user.displayName,
                                        subtitle: "@\(user.username)",
                                        avatarURL: user.avatarURL
                                    )
                                }
                            }
                        } else {
                            if !recent.isEmpty {
                                Section("Recent") {
                                    // SharePost uses recipient user ids (1:1). Skip groups —
                                    // posting into a group chat is not supported by this picker.
                                    ForEach(recent.filter { !$0.isGroup && !$0.peerUserID.isEmpty }) { conversation in
                                        personRow(
                                            id: conversation.peerUserID,
                                            title: conversation.peerDisplayName.isEmpty
                                                ? conversation.peerUsername
                                                : conversation.peerDisplayName,
                                            subtitle: "@\(conversation.peerUsername)",
                                            avatarURL: conversation.peerAvatarURL
                                        )
                                    }
                                }
                            }
                            if !following.isEmpty {
                                Section("Following") {
                                    ForEach(followingFiltered) { user in
                                        personRow(
                                            id: user.id,
                                            title: user.displayName.isEmpty ? user.username : user.displayName,
                                            subtitle: "@\(user.username)",
                                            avatarURL: user.avatarURL
                                        )
                                    }
                                    if followingCursor != nil {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .task { await loadMoreFollowing() }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search people")
            .onChange(of: query) { _ in
                onQueryChanged()
            }
            .navigationTitle("Send in Direct")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onFinish(false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(selected.isEmpty || isSending)
                }
            }
            .overlay {
                if isSending { ProgressView() }
            }
            .alert("Couldn’t send", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await loadInitial() }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private var isSearchMode: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rowsEmpty: Bool {
        if isSearchMode {
            return searchResults.isEmpty && !isSearching
        }
        return recent.isEmpty && followingFiltered.isEmpty
    }

    /// Following minus people already shown under Recent.
    private var followingFiltered: [FollowUser] {
        let recentIDs = Set(recent.map(\.peerUserID))
        return following.filter { !recentIDs.contains($0.id) && $0.id != deps.currentUserID }
    }

    @ViewBuilder
    private func personRow(
        id: String,
        title: String,
        subtitle: String,
        avatarURL: URL?
    ) -> some View {
        Button {
            toggle(id)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(id) ? Color.accentColor : .secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ userID: String) {
        if selected.contains(userID) {
            selected.remove(userID)
        } else if selected.count < 10 {
            selected.insert(userID)
        }
    }

    private func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        async let inboxPage = loadRecent()
        async let followingPage = loadFollowingFirstPage()
        _ = await (inboxPage, followingPage)
    }

    private func loadRecent() async {
        do {
            let page = try await deps.directUseCase.inbox(folder: "primary", cursor: nil)
            recent = page.conversations
        } catch {
            // Keep following usable even if inbox fails.
            if following.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadFollowingFirstPage() async {
        do {
            let page = try await deps.userUseCase.listFollowing(
                userID: deps.currentUserID,
                cursor: nil,
                limit: 30
            )
            following = page.users
            followingCursor = page.nextCursor
        } catch {
            if recent.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreFollowing() async {
        guard let cursor = followingCursor, !isLoading else { return }
        do {
            let page = try await deps.userUseCase.listFollowing(
                userID: deps.currentUserID,
                cursor: cursor,
                limit: 30
            )
            following.append(contentsOf: page.users)
            followingCursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func onQueryChanged() {
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

    private func search(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await deps.searchUseCase.searchUsers(query: q, cursor: nil, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = page.users.filter { $0.id != deps.currentUserID }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await deps.directUseCase.sharePost(
                postID: postID,
                recipientIDs: Array(selected),
                text: nil
            )
            onFinish(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// People row inside the share sheet: pick recipients and an optional note without a second screen.
struct DirectShareInlineSection: View {
    let postID: String
    let deps: DirectShareDependencies
    let onSent: () -> Void

    @State private var recent: [DMConversation] = []
    @State private var following: [FollowUser] = []
    @State private var searchResults: [FollowUser] = []
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var note = ""
    @State private var isSending = false
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search people", text: $query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query) { _ in
                    onQueryChanged()
                }

            if isLoading && recent.isEmpty && following.isEmpty && !isSearchMode {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
            } else if isSearchMode {
                searchList
            } else if candidates.isEmpty {
                Text("Follow people or start a chat to send this here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(candidates) { person in
                            personCell(person)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !selected.isEmpty {
                HStack(spacing: 8) {
                    TextField("Add a message", text: $note)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") {
                        Task { await send() }
                    }
                    .directGlassButton(prominent: true)
                    .disabled(isSending)
                }
            }
        }
        .overlay {
            if isSending { ProgressView() }
        }
        .alert("Couldn’t send", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await loadInitial() }
        .onDisappear { searchTask?.cancel() }
    }

    private var isSearchMode: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var candidates: [SharePerson] {
        var seen = Set<String>()
        var people: [SharePerson] = []
        for conversation in recent where seen.insert(conversation.peerUserID).inserted {
            let name = conversation.peerDisplayName.isEmpty
                ? conversation.peerUsername
                : conversation.peerDisplayName
            people.append(SharePerson(
                id: conversation.peerUserID,
                name: name,
                username: conversation.peerUsername,
                avatarURL: conversation.peerAvatarURL
            ))
        }
        for user in following where user.id != deps.currentUserID && seen.insert(user.id).inserted {
            people.append(SharePerson(
                id: user.id,
                name: user.displayName.isEmpty ? user.username : user.displayName,
                username: user.username,
                avatarURL: user.avatarURL
            ))
        }
        return people
    }

    private var searchList: some View {
        Group {
            if isSearching && searchResults.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            } else if searchResults.isEmpty {
                Text("No people found")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(searchResults.prefix(8)) { user in
                        Button {
                            toggle(user.id)
                        } label: {
                            HStack(spacing: 10) {
                                avatar(url: user.avatarURL, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.displayName.isEmpty ? user.username : user.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("@\(user.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(user.id) ? Color.accentColor : .secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func personCell(_ person: SharePerson) -> some View {
        Button {
            toggle(person.id)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    avatar(url: person.avatarURL, size: 56)
                    if selected.contains(person.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(Color.white).padding(2))
                    }
                }
                Text(person.name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 68)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityAddTraits(selected.contains(person.id) ? .isSelected : [])
    }

    private func avatar(url: URL?, size: CGFloat) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(Color.gray.opacity(0.2))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func toggle(_ userID: String) {
        if selected.contains(userID) {
            selected.remove(userID)
        } else if selected.count < 10 {
            selected.insert(userID)
        }
    }

    private func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        async let inboxPage = loadRecent()
        async let followingPage = loadFollowing()
        _ = await (inboxPage, followingPage)
    }

    private func loadRecent() async {
        do {
            let page = try await deps.directUseCase.inbox(folder: "primary", cursor: nil)
            recent = page.conversations
        } catch {
            if following.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadFollowing() async {
        do {
            let page = try await deps.userUseCase.listFollowing(
                userID: deps.currentUserID,
                cursor: nil,
                limit: 30
            )
            following = page.users
        } catch {
            if recent.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func onQueryChanged() {
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

    private func search(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await deps.searchUseCase.searchUsers(query: q, cursor: nil, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = page.users.filter { $0.id != deps.currentUserID }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        defer { isSending = false }
        do {
            try await deps.directUseCase.sharePost(
                postID: postID,
                recipientIDs: Array(selected),
                text: text.isEmpty ? nil : text
            )
            onSent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SharePerson: Identifiable {
    let id: String
    let name: String
    let username: String
    let avatarURL: URL?
}
