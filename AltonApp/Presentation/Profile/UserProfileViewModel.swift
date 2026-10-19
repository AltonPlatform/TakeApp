import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class UserProfileViewModel {
    let userID: String?
    let initialTab: ProfilePostTab
    private let userUseCase: UserUseCase
    private let currentUserID: String

    var profile: UserProfile?
    var takePosts: [Post] = []
    var shotPosts: [Post] = []
    var selectedTab: ProfilePostTab
    var isLoading = false
    var isFollowLoading = false
    var errorMessage: String?
    var takeCursor: String?
    var shotCursor: String?
    var hasMoreTakes = true
    var hasMoreShots = true
    private var takeWindow = WindowedFeed<Post>(windowSize: 100)
    private var shotWindow = WindowedFeed<Post>(windowSize: 100)
    // Read from `deinit`; stored `nonisolated` is illegal on @Observable properties.
    @ObservationIgnored private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?

    var isOwnProfile: Bool {
        guard let profile else { return userID == nil }
        return profile.id == currentUserID
    }

    init(
        userID: String?,
        currentUserID: String,
        userUseCase: UserUseCase,
        initialTab: ProfilePostTab = .takes
    ) {
        self.userID = userID
        self.currentUserID = currentUserID
        self.userUseCase = userUseCase
        self.initialTab = initialTab
        self.selectedTab = initialTab
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

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let userID {
                profile = try await userUseCase.loadProfile(userID: userID)
                if userID != currentUserID {
                    try? await userUseCase.recordProfileView(userID: userID)
                }
            } else {
                profile = try await userUseCase.loadCurrentProfile()
            }
            await loadTakes(reset: true)
            await loadShots(reset: true)
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadTakes(reset: Bool) async {
        guard let profile else { return }
        if !reset {
            guard hasMoreTakes else { return }
        }
        let requestCursor = reset ? nil : takeCursor
        do {
            let page = try await userUseCase.loadTakePosts(
                userID: profile.id,
                cursor: requestCursor,
                limit: 20
            )
            if reset {
                takeWindow.replaceAll(page.posts)
                takeCursor = page.nextCursor
                hasMoreTakes = page.nextCursor != nil
            } else {
                _ = takeWindow.append(page.posts, around: max(0, takeWindow.items.count - 1))
                takeCursor = page.nextCursor
                hasMoreTakes = page.nextCursor != nil
            }
            takePosts = takeWindow.items
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadShots(reset: Bool) async {
        guard let profile else { return }
        if !reset {
            guard hasMoreShots else { return }
        }
        let requestCursor = reset ? nil : shotCursor
        do {
            let page = try await userUseCase.loadShotPosts(
                userID: profile.id,
                cursor: requestCursor,
                limit: 20
            )
            if reset {
                shotWindow.replaceAll(page.posts)
                shotCursor = page.nextCursor
                hasMoreShots = page.nextCursor != nil
            } else {
                _ = shotWindow.append(page.posts, around: max(0, shotWindow.items.count - 1))
                shotCursor = page.nextCursor
                hasMoreShots = page.nextCursor != nil
            }
            shotPosts = shotWindow.items
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func handleMemoryWarning() {
        takeWindow.trimToNewest()
        shotWindow.trimToNewest()
        takePosts = takeWindow.items
        shotPosts = shotWindow.items
        ImagePipelineConfig.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()
    }

    func removeTakePost(id: String) {
        takePosts.removeAll { $0.id == id }
        takeWindow.items = takePosts
    }

    func toggleFollow() async {
        guard var profile, !isOwnProfile else { return }
        isFollowLoading = true
        defer { isFollowLoading = false }
        do {
            if profile.isFollowing {
                _ = try await userUseCase.unfollow(userID: profile.id)
                profile.isFollowing = false
                profile.followerCount = max(0, profile.followerCount - 1)
            } else {
                _ = try await userUseCase.follow(userID: profile.id)
                profile.isFollowing = true
                profile.followerCount += 1
            }
            self.profile = profile
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class EditProfileViewModel {
    enum UsernameAvailability: Equatable {
        case idle
        case checking
        case available
        case taken
        case invalid(String)
    }

    private let userUseCase: UserUseCase
    private let mediaUploadClient = MediaUploadClient()
    let profile: UserProfile
    var displayName: String
    var bio: String
    var username: String
    var dateOfBirth: Date?
    var gender: Gender?
    var usernameAvailability: UsernameAvailability = .idle
    var isSaving = false
    var isUploadingAvatar = false
    var avatarPreview: UIImage?
    var errorMessage: String?
    var savedProfile: UserProfile?
    private var usernameCheckTask: Task<Void, Never>?

    private static let usernameAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")

    var dateOfBirthRange: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let min = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? today
        return min...today
    }

    /// When DOB is cleared or set below 18, turn sensitive preference off in the same save.
    static func shouldForceSensitiveOff(previous: UserProfile, nextDateOfBirth: Date?) -> Bool {
        let clearing = nextDateOfBirth == nil && previous.dateOfBirth != nil
        let becomingMinor = nextDateOfBirth.map { !User.computeIsAdult(from: $0) } ?? false
        return clearing || becomingMinor
    }

    /// Default DOB when the user opts in to setting a birthday (18 years ago).
    var defaultDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }

    var hasDateOfBirth: Bool {
        get { dateOfBirth != nil }
        set {
            if newValue {
                if dateOfBirth == nil {
                    // Prefer the original profile DOB if the user toggles back on.
                    dateOfBirth = profile.dateOfBirth ?? defaultDateOfBirth
                }
            } else {
                dateOfBirth = nil
            }
        }
    }

    var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var usernameChanged: Bool {
        normalizedUsername != profile.username.lowercased()
    }

    var canSave: Bool {
        guard !isSaving else { return false }
        if usernameChanged, case .checking = usernameAvailability {
            return false
        }
        return true
    }

    init(profile: UserProfile, userUseCase: UserUseCase) {
        self.profile = profile
        self.userUseCase = userUseCase
        self.displayName = profile.displayName
        self.bio = profile.bio ?? ""
        self.username = profile.username
        self.dateOfBirth = profile.dateOfBirth
        self.gender = profile.gender
    }

    func usernameEdited(_ raw: String) {
        let filtered = String(raw.lowercased().unicodeScalars.filter { Self.usernameAllowed.contains($0) })
        let clipped = String(filtered.prefix(20))
        username = clipped
        scheduleUsernameAvailabilityCheck()
    }

    func scheduleUsernameAvailabilityCheck() {
        usernameCheckTask?.cancel()
        let candidate = normalizedUsername
        guard usernameChanged else {
            usernameAvailability = .idle
            return
        }
        guard isUsernameFormatValid(candidate) else {
            usernameAvailability = .invalid(usernameFormatError(for: candidate))
            return
        }
        usernameAvailability = .checking
        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            guard normalizedUsername == candidate else { return }
            do {
                let available = try await userUseCase.checkUsernameAvailable(candidate)
                guard !Task.isCancelled, normalizedUsername == candidate else { return }
                usernameAvailability = available ? .available : .taken
            } catch {
                if NetworkErrorClassifier.isCancellation(error) { return }
                guard !Task.isCancelled else { return }
                usernameAvailability = .invalid(error.localizedDescription)
            }
        }
    }

    func isUsernameFormatValid(_ value: String) -> Bool {
        guard value.count >= 3, value.count <= 20 else { return false }
        return value.unicodeScalars.allSatisfy { Self.usernameAllowed.contains($0) }
    }

    private func usernameFormatError(for value: String) -> String {
        if value.isEmpty {
            return "Username is required."
        }
        if value.count < 3 {
            return "Username must be at least 3 characters."
        }
        if value.count > 20 {
            return "Username must be at most 20 characters."
        }
        return "Use lowercase letters, numbers, and underscores only."
    }

    func uploadAvatar(data: Data, contentType: String) async {
        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }

        do {
            if let image = UIImage(data: data) {
                avatarPreview = image
            }
            let upload = try await userUseCase.prepareAvatarUpload(contentType: contentType)
            try await mediaUploadClient.upload(data: data, to: upload.uploadURL, contentType: contentType)
            try await userUseCase.completeAvatarUpload(objectKey: upload.objectKey)
            // Processing is async; keep local preview and refresh profile shortly.
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let refreshed = try? await userUseCase.loadCurrentProfile() {
                    savedProfile = refreshed
                    if refreshed.avatarURL != nil { break }
                }
            }
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let candidate = normalizedUsername
        do {
            var updated = try await userUseCase.updateProfile(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarR2Key: nil,
                dateOfBirth: dateOfBirth,
                gender: gender,
                showSensitiveContent: Self.shouldForceSensitiveOff(
                    previous: profile,
                    nextDateOfBirth: dateOfBirth
                ) ? false : nil,
                clearDateOfBirth: dateOfBirth == nil && profile.dateOfBirth != nil,
                clearGender: gender == nil && profile.gender != nil
            )

            if usernameChanged {
                guard isUsernameFormatValid(candidate) else {
                    savedProfile = updated
                    errorMessage = "Profile saved. Username was not updated: \(usernameFormatError(for: candidate))"
                    usernameAvailability = .invalid(usernameFormatError(for: candidate))
                    return
                }

                // Always re-check — UI `.available` can go stale before save.
                let available = try await userUseCase.checkUsernameAvailable(candidate)
                usernameAvailability = available ? .available : .taken
                guard available else {
                    savedProfile = updated
                    errorMessage = "Profile saved, but that username is taken."
                    return
                }

                do {
                    updated = try await userUseCase.updateUsername(candidate)
                } catch {
                    savedProfile = updated
                    errorMessage = Self.usernameUpdateErrorMessage(from: error)
                    usernameAvailability = .taken
                    return
                }
            }

            savedProfile = updated
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func usernameUpdateErrorMessage(from error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .conflict:
                return "Profile saved, but that username is taken."
            case .validation(let message) where message.lowercased().contains("taken")
                || message.lowercased().contains("already"):
                return "Profile saved, but that username is taken."
            default:
                break
            }
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("taken") || text.contains("conflict") || text.contains("already") {
            return "Profile saved, but that username is taken."
        }
        return "Profile saved, but username could not be updated: \(error.localizedDescription)"
    }
}

@MainActor
@Observable
final class BookmarksViewModel {
    private let bookmarksUseCase: BookmarksUseCase
    var posts: [Post] = []
    var isLoading = false
    var errorMessage: String?
    private var cursor: String?
    private var hasMore = true
    private var window = WindowedFeed<Post>(windowSize: 100)

    init(bookmarksUseCase: BookmarksUseCase) {
        self.bookmarksUseCase = bookmarksUseCase
    }

    func load(reset: Bool = false) async {
        if reset {
            cursor = nil
            window.replaceAll([])
            posts = []
            hasMore = true
        }
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await bookmarksUseCase.loadBookmarks(cursor: cursor, limit: 20)
            _ = window.append(page.posts, around: max(0, window.items.count - 1))
            posts = window.items
            cursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class SearchViewModel {
    private let searchUseCase: SearchUseCase
    enum Segment: String, CaseIterable { case users, posts, shots }
    var segment: Segment = .users
    var query = ""
    var users: [FollowUser] = []
    var posts: [Post] = []
    var isLoading = false
    var errorMessage: String?
    private var searchTask: Task<Void, Never>?
    /// Bumped on every new search/cancel so stale responses don't clear loading or overwrite results.
    private var searchGeneration = 0

    init(searchUseCase: SearchUseCase) {
        self.searchUseCase = searchUseCase
    }

    func searchDebounced() {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            users = []
            posts = []
            isLoading = false
            errorMessage = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, generation == searchGeneration else { return }
            await search(generation: generation)
        }
    }

    func search(generation: Int? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        let requestGeneration: Int
        if let generation {
            requestGeneration = generation
        } else {
            searchGeneration += 1
            requestGeneration = searchGeneration
        }
        let requestQuery = trimmed
        let requestSegment = segment
        isLoading = true
        errorMessage = nil
        defer {
            if requestGeneration == searchGeneration {
                isLoading = false
            }
        }
        do {
            switch requestSegment {
            case .users:
                let page = try await searchUseCase.searchUsers(query: requestQuery, cursor: nil, limit: 20)
                guard requestGeneration == searchGeneration, !Task.isCancelled else { return }
                guard query.trimmingCharacters(in: .whitespacesAndNewlines) == requestQuery,
                      segment == requestSegment else { return }
                users = page.users
                posts = []
            case .posts:
                let page = try await searchUseCase.searchPosts(
                    query: requestQuery,
                    cursor: nil,
                    limit: 20,
                    postType: "take"
                )
                guard requestGeneration == searchGeneration, !Task.isCancelled else { return }
                guard query.trimmingCharacters(in: .whitespacesAndNewlines) == requestQuery,
                      segment == requestSegment else { return }
                posts = page.posts
                users = []
            case .shots:
                let page = try await searchUseCase.searchPosts(
                    query: requestQuery,
                    cursor: nil,
                    limit: 20,
                    postType: "shot"
                )
                guard requestGeneration == searchGeneration, !Task.isCancelled else { return }
                guard query.trimmingCharacters(in: .whitespacesAndNewlines) == requestQuery,
                      segment == requestSegment else { return }
                posts = page.posts
                users = []
            }
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { return }
            guard requestGeneration == searchGeneration, !Task.isCancelled else { return }
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == requestQuery,
                  segment == requestSegment else { return }
            errorMessage = error.localizedDescription
        }
    }
}
