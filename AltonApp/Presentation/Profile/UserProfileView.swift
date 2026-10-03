import SwiftUI
import NukeUI
import UIKit

private struct ProfileDetailNavigation: Identifiable, Hashable {
    let item: FeedItem
    let focusComposer: Bool

    var id: String { focusComposer ? "\(item.id)-compose" : item.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProfileDetailNavigation, rhs: ProfileDetailNavigation) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ProfileShotsNavigation: Identifiable, Hashable {
    let postID: String
    let isOwnProfile: Bool

    var id: String { postID }
}

struct UserProfileView: View {
    @State private var viewModel: UserProfileViewModel
    let session: AuthSession
    let container: DependencyContainer
    var onOpenDraft: ((UUID) -> Void)?
    var onOpenShotDraft: ((UUID) -> Void)?
    var externalProfileUpdate: Binding<UserProfile?>? = nil
    @State private var showEditProfile = false
    @State private var isBlocking = false
    @State private var usernameCopied = false
    @State private var copyFeedbackTrigger = 0
    @State private var engagementController: PostEngagementController
    @State private var followListDestination: FollowListMode?
    @State private var detailItem: ProfileDetailNavigation?
    @State private var mentionProfileUserID: String?
    @State private var peekPost: Post?
    @State private var peekSuppress = ProfilePeekSuppressController()
    @State private var shotsNavigation: ProfileShotsNavigation?

    init(
        userID: String?,
        session: AuthSession,
        container: DependencyContainer,
        initialTab: ProfilePostTab = .takes,
        onOpenDraft: ((UUID) -> Void)? = nil,
        onOpenShotDraft: ((UUID) -> Void)? = nil,
        externalProfileUpdate: Binding<UserProfile?>? = nil
    ) {
        _viewModel = State(initialValue: UserProfileViewModel(
            userID: userID,
            currentUserID: session.user.id,
            userUseCase: container.userUseCase,
            initialTab: initialTab
        ))
        self.session = session
        self.container = container
        self.onOpenDraft = onOpenDraft
        self.onOpenShotDraft = onOpenShotDraft
        self.externalProfileUpdate = externalProfileUpdate
        _engagementController = State(initialValue: container.makeEngagementController())
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let profile = viewModel.profile {
                        profileHeader(profile)
                        profileTabBar(profile)
                        Divider()

                        switch viewModel.selectedTab {
                        case .takes:
                            takesContent
                        case .shots:
                            shotsContent
                        }
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
            .scrollDisabled(peekPost != nil)

            ProfilePeekOverlay(isPresented: peekPost != nil, onDismiss: dismissPeekOverlay) {
                if let peekPost {
                    ProfileShotPeekCard(post: peekPost)
                }
            }
        }
        .navigationTitle(viewModel.profile.map { "@\($0.username)" } ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showEditProfile) {
            if let profile = viewModel.profile {
                EditProfileView(
                    profile: profile,
                    userUseCase: container.userUseCase
                ) { updated in
                    viewModel.profile = updated
                    container.sessionStore.updateCurrentUser(from: updated)
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationDestination(item: $followListDestination) { mode in
            if let profile = viewModel.profile {
                FollowListView(
                    userID: profile.id,
                    mode: mode,
                    session: session,
                    container: container
                )
            }
        }
        .navigationDestination(item: $detailItem) { navigation in
            TakePostDetailView(
                item: navigation.item,
                currentUser: session.user,
                container: container,
                session: session,
                userUseCase: container.userUseCase,
                engagementController: engagementController,
                commentsViewModelFactory: { post in
                    container.makeCommentsViewModel(
                        postID: post.id,
                        currentUserID: session.user.id
                    )
                },
                analyticsUseCase: container.analyticsUseCase,
                postUseCase: container.postUseCase,
                onDeleted: { viewModel.removeTakePost(id: navigation.item.id) },
                focusComposerOnAppear: navigation.focusComposer
            )
        }
        .navigationDestination(item: $mentionProfileUserID) { userID in
            UserProfileView(userID: userID, session: session, container: container)
        }
        .navigationDestination(item: $shotsNavigation) { navigation in
            let posts = ViewerContentFilterPolicy.filterPosts(
                viewModel.shotPosts,
                viewerIsAdult: session.user.isAdult,
                showSensitiveContent: session.user.showSensitiveContent,
                isOwnProfile: navigation.isOwnProfile
            )
            let index = posts.firstIndex(where: { $0.id == navigation.postID }) ?? 0
            ProfileShotsFeedView(
                posts: posts,
                initialIndex: index,
                session: session,
                container: container,
                isOwnProfile: navigation.isOwnProfile
            )
        }
        .onChange(of: externalProfileUpdate?.wrappedValue) { _, updated in
            if let updated {
                viewModel.profile = updated
            }
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTrigger)
        .onDisappear {
            peekSuppress.clear()
            peekPost = nil
        }
    }

    private func peekGestureBinding(for post: Post) -> Binding<Bool> {
        Binding(
            get: { peekPost?.id == post.id },
            set: { peeking in
                if peeking {
                    peekPost = post
                } else if peekPost?.id == post.id {
                    peekPost = nil
                }
            }
        )
    }

    /// Overlay tap (and any non-gesture dismiss) must end suppress or the cell stays locked.
    private func dismissPeekOverlay() {
        peekPost = nil
        peekSuppress.end()
    }

    @ViewBuilder
    private func profileHeader(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            UserAvatarView(user: profile.asUser(), size: 88)

            VStack(spacing: 4) {
                Text(profile.displayName)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(usernameCopied ? "Copied" : "@\(profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(usernameCopied ? Color.primary : Color.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: usernameCopied)
                    .onTapGesture { copyUsername(profile.username) }
                    .onLongPressGesture { copyUsername(profile.username) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Copies username to clipboard")
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                Button {
                    followListDestination = .followers
                } label: {
                    statItem(value: profile.followerCount, label: "Followers")
                }
                .buttonStyle(.plain)

                Divider().frame(height: 28)

                Button {
                    followListDestination = .following
                } label: {
                    statItem(value: profile.followingCount, label: "Following")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            if viewModel.isOwnProfile {
                ownProfileActions
            } else {
                otherProfileActions(profile)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var ownProfileActions: some View {
        VStack(spacing: 10) {
            Button {
                showEditProfile = true
            } label: {
                Text("Edit Profile")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 12) {
                NavigationLink {
                    DraftsView(
                        postUseCase: container.postUseCase,
                        draftStore: container.draftStore,
                        onOpenDraft: onOpenDraft,
                        onOpenShotDraft: onOpenShotDraft
                    )
                } label: {
                    Label("Drafts", systemImage: "doc.text")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    ScheduledPostsView(postUseCase: container.postUseCase)
                } label: {
                    Label("Scheduled", systemImage: "calendar")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func otherProfileActions(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.toggleFollow() }
            } label: {
                Text(profile.isFollowing ? "Following" : "Follow")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .disabled(viewModel.isFollowLoading)

            Button(role: .destructive) {
                Task { await blockUser(profile.id) }
            } label: {
                Text(isBlocking ? "…" : "Block")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .disabled(isBlocking)
        }
    }

    private func copyUsername(_ username: String) {
        UIPasteboard.general.string = "@\(username)"
        copyFeedbackTrigger &+= 1
        let token = copyFeedbackTrigger
        container.appState.showToast("Copied", duration: 1.5)
        usernameCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copyFeedbackTrigger == token {
                usernameCopied = false
            }
        }
    }

    private func blockUser(_ userID: String) async {
        isBlocking = true
        defer { isBlocking = false }
        do {
            try await container.userUseCase.blockUser(userID: userID)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func profileTabBar(_ profile: UserProfile) -> some View {
        HStack(spacing: 0) {
            profileTabButton(.takes, title: "Takes", icon: "text.bubble", count: profile.takeCount)
            profileTabButton(.shots, title: "Shots", icon: "play.rectangle", count: profile.shotCount)
        }
    }

    private func profileTabButton(_ tab: ProfilePostTab, title: String, icon: String, count: Int?) -> some View {
        Button {
            viewModel.selectedTab = tab
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(title)
                    if let count {
                        Text("(\(count))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(viewModel.selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(viewModel.selectedTab == tab ? .primary : .secondary)

                Rectangle()
                    .fill(viewModel.selectedTab == tab ? Color.primary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .buttonStyle(.plain)
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(formattedCount(value))
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func formattedCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    @ViewBuilder
    private var takesContent: some View {
        let visibleTakes = ViewerContentFilterPolicy.filterPosts(
            viewModel.takePosts,
            viewerIsAdult: session.user.isAdult,
            showSensitiveContent: session.user.showSensitiveContent,
            isOwnProfile: viewModel.isOwnProfile
        )
        if visibleTakes.isEmpty, !viewModel.isLoading {
            ContentUnavailableView("No takes yet", systemImage: "text.bubble")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(visibleTakes, id: \.id) { post in
                    TakePostView(
                            item: FeedItem(
                                post: post,
                                finalScore: 0,
                                userScore: 0,
                                creatorScore: 0,
                                brandScore: 0
                            ),
                            currentUser: session.user,
                            container: container,
                            session: session,
                            engagementController: engagementController,
                            commentsViewModelFactory: { post in
                                container.makeCommentsViewModel(
                                    postID: post.id,
                                    currentUserID: session.user.id
                                )
                            },
                            onReply: { post in
                                detailItem = ProfileDetailNavigation(
                                    item: FeedItem(
                                        post: post,
                                        finalScore: 0,
                                        userScore: 0,
                                        creatorScore: 0,
                                        brandScore: 0
                                    ),
                                    focusComposer: true
                                )
                            },
                            onDeleted: { id in
                                viewModel.removeTakePost(id: id)
                            },
                            onOpenDetail: {
                                detailItem = ProfileDetailNavigation(
                                    item: FeedItem(
                                        post: post,
                                        finalScore: 0,
                                        userScore: 0,
                                        creatorScore: 0,
                                        brandScore: 0
                                    ),
                                    focusComposer: false
                                )
                            },
                            onOpenMentionProfile: { userID in
                                mentionProfileUserID = userID
                            }
                    )

                    Divider()
                        .overlay(PostColor.border)
                }
                if viewModel.hasMoreTakes {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task { await viewModel.loadTakes(reset: false) }
                }
            }
        }
    }

    @ViewBuilder
    private var shotsContent: some View {
        let visibleShots = ViewerContentFilterPolicy.filterPosts(
            viewModel.shotPosts,
            viewerIsAdult: session.user.isAdult,
            showSensitiveContent: session.user.showSensitiveContent,
            isOwnProfile: viewModel.isOwnProfile
        )
        if visibleShots.isEmpty, !viewModel.isLoading {
            ContentUnavailableView("No shots yet", systemImage: "play.rectangle")
                .padding(.vertical, 32)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
                spacing: 1
            ) {
                ForEach(visibleShots, id: \.id) { post in
                    profileShotThumbnail(post)
                        .contentShape(Rectangle())
                        .profilePeekGesture(
                            isPeeking: peekGestureBinding(for: post),
                            onPeekBegan: { peekSuppress.begin(lockID: post.id) },
                            onPeekEnded: { peekSuppress.end() }
                        )
                        .simultaneousGesture(TapGesture().onEnded {
                            guard peekSuppress.allowsActivation(for: post.id) else { return }
                            shotsNavigation = ProfileShotsNavigation(
                                postID: post.id,
                                isOwnProfile: viewModel.isOwnProfile
                            )
                        })
                }
            }
            if viewModel.hasMoreShots {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .task { await viewModel.loadShots(reset: false) }
            }
        }
    }

    private func profileShotThumbnail(_ post: Post) -> some View {
        ZStack(alignment: .bottomLeading) {
            SensitiveMediaOverlay(
                isSensitive: post.isSensitiveImage(at: 0),
                isAgeRestricted: post.ageGated && !AgeGateConfirmationStore.shared.isConfirmed(post.id),
                showsRevealButton: false,
                managesRevealInternally: false,
                moderationReason: post.moderationReason
            ) {
                Group {
                    if let url = post.thumbnailURL {
                        LazyImage(url: url) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.gray.opacity(0.25)
                            }
                        }
                        .processors([.resize(width: 256)])
                    } else {
                        Color.gray.opacity(0.25)
                    }
                }
                .aspectRatio(9 / 16, contentMode: .fill)
                .clipped()
            }

            if viewModel.isOwnProfile, post.status == .rejected {
                Color.black.opacity(0.55)
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("Removed for violation")
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    if let reason = ReportReason.displayTitle(for: post.moderationReason) {
                        Text(reason)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    Text(formattedCount(post.viewCount))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(6)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .contentShape(Rectangle())
    }
}

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EditProfileViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarCrop: PhotoCropDraft?
    let onSaved: (UserProfile) -> Void

    init(profile: UserProfile, userUseCase: UserUseCase, onSaved: @escaping (UserProfile) -> Void) {
        self.onSaved = onSaved
        _viewModel = State(initialValue: EditProfileViewModel(profile: profile, userUseCase: userUseCase))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        let avatarPreview = viewModel.avatarPreview
                        let avatarUser = viewModel.profile.asUser()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Group {
                                if let avatarPreview {
                                    Image(uiImage: avatarPreview)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 88, height: 88)
                                        .clipShape(Circle())
                                } else {
                                    UserAvatarView(user: avatarUser, size: 88)
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "camera.fill")
                                                .font(.caption)
                                                .padding(6)
                                                .background(.ultraThinMaterial, in: Circle())
                                        }
                                }
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        }
                        .disabled(viewModel.isUploadingAvatar)
                        .accessibilityLabel("Change profile photo")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Choose a photo, then adjust what appears in the circle.")
                }

                TextField("Display name", text: $viewModel.displayName)

                Section {
                    Toggle(
                        "Set date of birth",
                        isOn: Binding(
                            get: { viewModel.dateOfBirth != nil },
                            set: { viewModel.hasDateOfBirth = $0 }
                        )
                    )
                    if viewModel.dateOfBirth != nil {
                        DatePicker(
                            "Date of birth",
                            selection: Binding(
                                get: { viewModel.dateOfBirth ?? viewModel.defaultDateOfBirth },
                                set: { viewModel.dateOfBirth = $0 }
                            ),
                            in: viewModel.dateOfBirthRange,
                            displayedComponents: .date
                        )
                    }
                    Picker("Gender", selection: $viewModel.gender) {
                        Text("Not set").tag(Optional<Gender>.none)
                        ForEach(Gender.allCases) { option in
                            Text(option.displayName).tag(Optional(option))
                        }
                    }
                } header: {
                    Text("About you")
                }

                Section {
                    TextField("Username", text: Binding(
                        get: { viewModel.username },
                        set: { viewModel.usernameEdited($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)

                    if case .checking = viewModel.usernameAvailability {
                        Text("Checking availability…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if case .available = viewModel.usernameAvailability {
                        Text("Username is available")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if case .taken = viewModel.usernameAvailability {
                        Text("Username is taken")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if case .invalid(let message) = viewModel.usernameAvailability {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Username")
                } footer: {
                    Text("3–20 characters: lowercase letters, numbers, and underscores.")
                }
                TextField("Bio", text: $viewModel.bio, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Edit Profile")
            .keyboardDoneButton()
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    photoItem = nil
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                        avatarCrop = PhotoCropDraft(image: image)
                    }
                }
            }
            .fullScreenCover(item: $avatarCrop) { draft in
                PhotoCropEditorView(
                    image: draft.image,
                    mask: .circle
                ) {
                    avatarCrop = nil
                } onComplete: { cropped in
                    avatarCrop = nil
                    Task {
                        guard let data = cropped.jpegData(compressionQuality: 0.92) else { return }
                        await viewModel.uploadAvatar(data: data, contentType: "image/jpeg")
                        if let profile = viewModel.savedProfile {
                            onSaved(profile)
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.save()
                            // Always sync successful profile writes (including partial username failures).
                            if let profile = viewModel.savedProfile {
                                onSaved(profile)
                            }
                            if viewModel.errorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }
}

struct BookmarksView: View {
    @State private var viewModel: BookmarksViewModel
    @State private var feedViewModel: TakesFeedViewModel
    let session: AuthSession
    let container: DependencyContainer

    init(container: DependencyContainer, session: AuthSession) {
        self.container = container
        self.session = session
        _viewModel = State(initialValue: BookmarksViewModel(bookmarksUseCase: container.bookmarksUseCase))
        _feedViewModel = State(initialValue: container.makeTakesFeedViewModel())
    }

    var body: some View {
        let visiblePosts = ViewerContentFilterPolicy.filterPosts(
            viewModel.posts,
            viewerIsAdult: session.user.isAdult,
            showSensitiveContent: session.user.showSensitiveContent
        )
        List(visiblePosts, id: \.id) { post in
            if post.postType == .take {
                NavigationLink {
                    TakePostDetailView(
                        item: FeedItem(post: post, finalScore: 0, userScore: 0, creatorScore: 0, brandScore: 0),
                        currentUser: session.user,
                        container: container,
                        session: session,
                        userUseCase: container.userUseCase,
                        engagementController: feedViewModel.engagementController,
                        commentsViewModelFactory: { post in
                            feedViewModel.makeCommentsViewModel(for: post, userID: session.user.id)
                        },
                        analyticsUseCase: container.analyticsUseCase,
                        postUseCase: container.postUseCase,
                        onDeleted: {
                            viewModel.posts.removeAll { $0.id == post.id }
                        }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("@\(post.creatorUsername ?? "user")")
                            .font(.caption.weight(.semibold))
                        if let content = post.listSnippet {
                            Text(content).lineLimit(3)
                        }
                    }
                }
            } else {
                NavigationLink {
                    UserProfileView(
                        userID: post.creatorID,
                        session: session,
                        container: container,
                        initialTab: .shots
                    )
                } label: {
                    HStack {
                        if let thumbnailURL = post.thumbnailURL {
                            SensitiveMediaOverlay(
                                isSensitive: post.isSensitiveImage(at: 0),
                                isAgeRestricted: post.ageGated && !AgeGateConfirmationStore.shared.isConfirmed(post.id),
                                showsRevealButton: false,
                                managesRevealInternally: false,
                                moderationReason: post.moderationReason,
                                cornerRadius: 8
                            ) {
                                LazyImage(url: thumbnailURL) { state in
                                    if let image = state.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.2)
                                    }
                                }
                                .processors([.resize(width: 112)])
                                .frame(width: 56, height: 72)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("@\(post.creatorUsername ?? "user")")
                                .font(.caption.weight(.semibold))
                            if let content = post.listSnippet {
                                Text(content).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved")
        .task { await viewModel.load(reset: true) }
        .refreshable { await viewModel.load(reset: true) }
    }
}

struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @State private var engagementController: PostEngagementController
    let session: AuthSession
    let container: DependencyContainer

    init(container: DependencyContainer, session: AuthSession) {
        self.container = container
        self.session = session
        _viewModel = State(initialValue: SearchViewModel(searchUseCase: container.searchUseCase))
        _engagementController = State(initialValue: container.makeEngagementController())
    }

    private var trimmedQuery: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasEnoughQuery: Bool {
        trimmedQuery.count >= 2
    }

    private var visibleSearchPosts: [Post] {
        ViewerContentFilterPolicy.filterPosts(
            viewModel.posts,
            viewerIsAdult: session.user.isAdult,
            showSensitiveContent: session.user.showSensitiveContent
        )
    }

    private var isEmptyResults: Bool {
        switch viewModel.segment {
        case .users: return viewModel.users.isEmpty
        case .posts, .shots: return visibleSearchPosts.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Segment", selection: $viewModel.segment) {
                    Text("Users").tag(SearchViewModel.Segment.users)
                    Text("Posts").tag(SearchViewModel.Segment.posts)
                    Text("Shots").tag(SearchViewModel.Segment.shots)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Spacer()
                } else if hasEnoughQuery, isEmptyResults {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("Nothing matched “\(trimmedQuery)”.")
                    )
                } else {
                    List {
                        switch viewModel.segment {
                        case .users:
                            ForEach(viewModel.users) { user in
                                NavigationLink {
                                    UserProfileView(userID: user.id, session: session, container: container)
                                } label: {
                                    HStack {
                                        UserAvatarView(
                                            user: User(
                                                id: user.id,
                                                username: user.username,
                                                displayName: user.displayName,
                                                bio: nil,
                                                avatarURL: user.avatarURL,
                                                suiWallet: nil,
                                                createdAt: nil
                                            ),
                                            size: 40
                                        )
                                        VStack(alignment: .leading) {
                                            Text(user.displayName).fontWeight(.semibold)
                                            Text("@\(user.username)").foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        case .posts:
                            ForEach(visibleSearchPosts, id: \.id) { post in
                                NavigationLink {
                                    TakePostDetailView(
                                        item: FeedItem(
                                            post: post,
                                            finalScore: 0,
                                            userScore: 0,
                                            creatorScore: 0,
                                            brandScore: 0
                                        ),
                                        currentUser: session.user,
                                        container: container,
                                        session: session,
                                        userUseCase: container.userUseCase,
                                        engagementController: engagementController,
                                        commentsViewModelFactory: { post in
                                            container.makeCommentsViewModel(
                                                postID: post.id,
                                                currentUserID: session.user.id
                                            )
                                        },
                                        analyticsUseCase: container.analyticsUseCase,
                                        postUseCase: container.postUseCase
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("@\(post.creatorUsername ?? "")")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(post.listSnippet ?? "")
                                            .lineLimit(2)
                                    }
                                }
                            }
                        case .shots:
                            ForEach(visibleSearchPosts, id: \.id) { post in
                                NavigationLink {
                                    UserProfileView(
                                        userID: post.creatorID,
                                        session: session,
                                        container: container,
                                        initialTab: .shots
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        if let thumb = post.thumbnailURL {
                                            SensitiveMediaOverlay(
                                                isSensitive: post.isSensitiveImage(at: 0),
                                                isAgeRestricted: post.ageGated && !AgeGateConfirmationStore.shared.isConfirmed(post.id),
                                                showsRevealButton: false,
                                                managesRevealInternally: false,
                                                moderationReason: post.moderationReason,
                                                cornerRadius: 8
                                            ) {
                                                LazyImage(url: thumb) { state in
                                                    if let image = state.image {
                                                        image
                                                            .resizable()
                                                            .scaledToFill()
                                                    } else {
                                                        Color.secondary.opacity(0.15)
                                                    }
                                                }
                                                .frame(width: 56, height: 84)
                                                .clipped()
                                            }
                                        } else {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.secondary.opacity(0.15))
                                                .frame(width: 56, height: 84)
                                                .overlay {
                                                    Image(systemName: "play.rectangle.fill")
                                                        .foregroundStyle(.secondary)
                                                }
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("@\(post.creatorUsername ?? "")")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text(post.listSnippet ?? "Shot")
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Search...")
            .onChange(of: viewModel.query) { _, _ in
                viewModel.searchDebounced()
            }
            .onChange(of: viewModel.segment) { _, _ in
                viewModel.searchDebounced()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
