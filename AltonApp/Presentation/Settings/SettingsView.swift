import SwiftUI

/// Native Apple-style Settings for the signed-in user.
struct SettingsView: View {
    let session: AuthSession
    let container: DependencyContainer
    let onLogout: () -> Void
    var onOpenDraft: ((UUID) -> Void)?
    var onOpenShotDraft: ((UUID) -> Void)?
    var initialProfile: UserProfile?
    var onProfileUpdated: ((UserProfile) -> Void)?

    @State private var profile: UserProfile?
    @State private var showEditProfile = false
    @State private var showSignOutConfirm = false
    @State private var isLoadingProfile = false
    @State private var showSensitive = false
    @State private var isUpdatingSensitive = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    BookmarksView(container: container, session: session)
                } label: {
                    Label("Saved", systemImage: "bookmark")
                }

                NavigationLink {
                    DraftsView(
                        postUseCase: container.postUseCase,
                        draftStore: container.draftStore,
                        onOpenDraft: onOpenDraft,
                        onOpenShotDraft: onOpenShotDraft
                    )
                } label: {
                    Label("Drafts", systemImage: "doc.text")
                }

                NavigationLink {
                    ScheduledPostsView(postUseCase: container.postUseCase)
                } label: {
                    Label("Scheduled", systemImage: "calendar")
                }
            } header: {
                Text("Library")
            }

            Section {
                Toggle(isOn: $showSensitive) {
                    Label("Show Sensitive Content", systemImage: "eye")
                }
                .disabled(isUpdatingSensitive || profile == nil || profile?.isAdult != true)
                .onChange(of: showSensitive) { _, newValue in
                    Task { await updateSensitive(newValue) }
                }

                NavigationLink {
                    InterestsView(userUseCase: container.userUseCase) { interests in
                        if var updated = profile {
                            updated.interests = interests
                            profile = updated
                            container.sessionStore.updateCurrentUser(from: updated)
                            onProfileUpdated?(updated)
                        }
                    }
                } label: {
                    Label("Interests", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("Content Preferences")
            } footer: {
                if profile?.isAdult != true {
                    Text("Available for adults 18+ only. Set your date of birth in Edit Profile.")
                } else {
                    Text("When off, posts marked sensitive are hidden from your feed. Blur and tap-to-view still apply when on.")
                }
            }

            Section {
                NavigationLink {
                    AnalyticsDashboardView(
                        viewModel: AnalyticsDashboardViewModel(
                            postID: nil,
                            analyticsUseCase: container.analyticsUseCase
                        )
                    )
                } label: {
                    Label("Analytics", systemImage: "chart.bar")
                }
            } header: {
                Text("Insights")
            }

            Section {
                Button {
                    showEditProfile = true
                } label: {
                    Label("Edit Profile", systemImage: "person.crop.circle")
                }
                .disabled(profile == nil)

                NavigationLink {
                    BlockedUsersView(userUseCase: container.userUseCase)
                } label: {
                    Label("Blocked Users", systemImage: "hand.raised")
                }
            } header: {
                Text("Account")
            }

            Section {
                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let initialProfile {
                profile = initialProfile
                showSensitive = initialProfile.isAdult ? initialProfile.showSensitiveContent : false
                await reconcileSensitivePrefIfNeeded(initialProfile)
            } else {
                await loadProfile()
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let profile {
                EditProfileView(
                    profile: profile,
                    userUseCase: container.userUseCase
                ) { updated in
                    self.profile = updated
                    showSensitive = updated.isAdult ? updated.showSensitiveContent : false
                    container.sessionStore.updateCurrentUser(from: updated)
                    onProfileUpdated?(updated)
                    Task { await reconcileSensitivePrefIfNeeded(updated) }
                }
            }
        }
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive, action: onLogout)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private func loadProfile() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            let loaded = try await container.userUseCase.loadCurrentProfile()
            profile = loaded
            showSensitive = loaded.isAdult ? loaded.showSensitiveContent : false
            await reconcileSensitivePrefIfNeeded(loaded)
        } catch {
            // Edit Profile stays disabled if load fails.
        }
    }

    /// Persist force-off when the server still has sensitive enabled for a non-adult.
    private func reconcileSensitivePrefIfNeeded(_ loaded: UserProfile) async {
        guard !loaded.isAdult, loaded.showSensitiveContent else { return }
        guard !isUpdatingSensitive else { return }
        isUpdatingSensitive = true
        defer { isUpdatingSensitive = false }
        do {
            let updated = try await container.userUseCase.updateProfile(showSensitiveContent: false)
            profile = updated
            showSensitive = false
            container.sessionStore.updateCurrentUser(from: updated)
            onProfileUpdated?(updated)
        } catch {
            // UI already shows off; server may reject if race — leave local false.
            showSensitive = false
        }
    }

    private func updateSensitive(_ value: Bool) async {
        guard let profile, profile.isAdult, profile.showSensitiveContent != value else {
            if profile?.isAdult != true {
                showSensitive = false
            }
            return
        }
        isUpdatingSensitive = true
        defer { isUpdatingSensitive = false }
        do {
            let updated = try await container.userUseCase.updateProfile(showSensitiveContent: value)
            self.profile = updated
            container.sessionStore.updateCurrentUser(from: updated)
            onProfileUpdated?(updated)
        } catch {
            showSensitive = profile.showSensitiveContent
        }
    }
}
