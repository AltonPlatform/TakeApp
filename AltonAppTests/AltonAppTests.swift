import XCTest
@testable import AltonApp

final class AltonAppTests: XCTestCase {
    func testPostTypeMapping() {
        XCTAssertEqual(PostType(rawValue: "take"), .take)
        XCTAssertEqual(PostType(rawValue: "shot"), .shot)
    }

    func testAuthTokensExpiration() {
        let fresh = AuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 900,
            userID: "user",
            username: "demo",
            issuedAt: Date()
        )
        XCTAssertFalse(fresh.isExpired)

        let expired = AuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 900,
            userID: "user",
            username: "demo",
            issuedAt: Date().addingTimeInterval(-3600)
        )
        XCTAssertTrue(expired.isExpired)
    }

    func testAuthProviderTitles() {
        XCTAssertEqual(AuthProvider.apple.title, "Sign in with Apple")
        XCTAssertEqual(AuthProvider.magicLink.title, "Email Magic Link")
    }

    func testKeyboardPresenceMatchesSystemKeyboardClassesOnly() {
        XCTAssertTrue(EditorKeyboardPresence.isKeyboardClassName("UIKeyboardLayoutStar"))
        XCTAssertTrue(EditorKeyboardPresence.isKeyboardClassName("UIKeyboardImpl"))
        XCTAssertTrue(EditorKeyboardPresence.isKeyboardClassName("UIRemoteKeyboardWindow"))
        XCTAssertFalse(EditorKeyboardPresence.isKeyboardClassName("UITextEffectsWindow"))
        XCTAssertFalse(EditorKeyboardPresence.isKeyboardClassName("UIWindow"))
        XCTAssertFalse(EditorKeyboardPresence.isKeyboardClassName("KeyboardAvoidingView"))
    }

    func testTextDismissGateRequiresIdleKeyboardAndRetiredInput() {
        XCTAssertFalse(
            EditorTextDismissGate.canDestroyComposer(
                keyboardVisible: true,
                inputRetired: true,
                stableIdleTicks: 8
            )
        )
        XCTAssertFalse(
            EditorTextDismissGate.canDestroyComposer(
                keyboardVisible: false,
                inputRetired: false,
                stableIdleTicks: 8
            )
        )
        XCTAssertFalse(
            EditorTextDismissGate.canDestroyComposer(
                keyboardVisible: false,
                inputRetired: true,
                stableIdleTicks: 2
            )
        )
        XCTAssertTrue(
            EditorTextDismissGate.canDestroyComposer(
                keyboardVisible: false,
                inputRetired: true,
                stableIdleTicks: EditorTextDismissGate.requiredIdleTicks
            )
        )
    }

    func testKeyboardDismissAfterCloseDoesNotTouchIMETextView() {
        EditorKeyboardDismiss.dismissOrphanedKeyboard()
        XCTAssertFalse(EditorKeyboardPresence.isKeyboardClassName("UITextView"))
    }

    func testMediaThumbnailURLDerivesThumbSiblingFromImagePlayback() {
        let full = URL(string: "https://cdn.example.com/objects/media/post1/image_2.jpg")!
        let thumb = MediaThumbnailURL.derived(fromPlayback: full)
        XCTAssertEqual(thumb?.path, "/objects/media/post1/thumb_2.webp")
        XCTAssertEqual(thumb?.host, "cdn.example.com")
    }

    func testMediaThumbnailURLUsesHintExtensionAndKeepsQuery() {
        let full = URL(string: "https://cdn.example.com/media/post1/image_0.webp?token=1")!
        let hint = URL(string: "https://cdn.example.com/media/post1/thumb_0.jpg")!
        let thumbs = MediaThumbnailURL.thumbnails(
            imageURLs: [full],
            thumbnailURL: hint,
            thumbnailKey: nil
        )
        XCTAssertEqual(thumbs.first?.path, "/media/post1/thumb_0.jpg")
        XCTAssertEqual(thumbs.first?.query, "token=1")
    }

    func testMediaThumbnailURLDerivesStillThumbForGIF() {
        let gif = URL(string: "https://cdn.example.com/objects/media/post1/image_1.gif?token=1")!
        let thumbs = MediaThumbnailURL.thumbnails(
            imageURLs: [gif],
            thumbnailURL: nil,
            thumbnailKey: nil
        )
        XCTAssertEqual(thumbs.first?.path, "/objects/media/post1/thumb_1.webp")
        XCTAssertEqual(thumbs.first?.query, "token=1")
    }

    func testMediaThumbnailURLDerivesVideoThumb() {
        let video = URL(string: "https://cdn.example.com/media/post1/video.mp4")!
        XCTAssertEqual(
            MediaThumbnailURL.derived(fromPlayback: video)?.lastPathComponent,
            "thumb.webp"
        )
    }

    func testMediaThumbnailURLLeavesExistingThumbUnchanged() {
        let thumb = URL(string: "https://cdn.example.com/media/post1/thumb_0.webp")!
        XCTAssertEqual(MediaThumbnailURL.derived(fromPlayback: thumb), thumb)
    }

    func testMediaThumbnailURLFittedSizeNeverExceedsMaxAndKeepsAspect() {
        let landscape = MediaThumbnailURL.fittedSize(maxWidth: 351, maxHeight: 240, aspect: 16.0 / 9.0)
        XCTAssertEqual(landscape.width, 351, accuracy: 0.5)
        XCTAssertEqual(landscape.height, 351 * 9.0 / 16.0, accuracy: 0.5)

        let portrait = MediaThumbnailURL.fittedSize(maxWidth: 351, maxHeight: 385, aspect: 9.0 / 16.0)
        XCTAssertEqual(portrait.height, 385, accuracy: 0.5)
        XCTAssertEqual(portrait.width, 385 * 9.0 / 16.0, accuracy: 0.5)
        XCTAssertLessThan(portrait.width, 351)
    }

    func testMediaThumbnailURLRowHeightFitsPairWithoutOverflow() {
        let height = MediaThumbnailURL.rowHeight(
            containerWidth: 351,
            aspects: [16.0 / 9.0, 16.0 / 9.0],
            spacing: 8,
            maxHeight: 280
        )
        let totalWidth = height * (16.0 / 9.0) * 2 + 8
        XCTAssertEqual(totalWidth, 351, accuracy: 0.5)
        XCTAssertLessThanOrEqual(height, 280)
    }

    func testPostMediaDesignMapsFigmaVariantsAndScalesWithColumn() {
        XCTAssertEqual(PostMediaDesign.layout(portraits: [false]), .h1)
        XCTAssertEqual(PostMediaDesign.layout(portraits: [true]), .v1)
        XCTAssertEqual(PostMediaDesign.layout(portraits: [false, false]), .h2)
        XCTAssertEqual(PostMediaDesign.layout(portraits: [true, true]), .v2)
        XCTAssertEqual(PostMediaDesign.layout(portraits: [false, false, false]), .h3Plus)
        XCTAssertEqual(PostMediaDesign.layout(portraits: [true, true, true]), .v3Plus)
        XCTAssertEqual(PostMediaDesign.layout(portraits: [true, false]), .mixed)

        let column: CGFloat = 338
        XCTAssertEqual(PostMediaDesign.tileSize(layout: .h1, index: 0, column: column).height, 160, accuracy: 0.01)
        XCTAssertEqual(PostMediaDesign.tileSize(layout: .v1, index: 0, column: column).height, 385, accuracy: 0.01)
        XCTAssertEqual(PostMediaDesign.tileSize(layout: .h3Plus, index: 0, column: column).width, 224, accuracy: 0.01)
        XCTAssertEqual(PostMediaDesign.tileSize(layout: .v3Plus, index: 0, column: column).width, 212, accuracy: 0.01)
        XCTAssertEqual(PostMediaDesign.tileSize(layout: .mixed, index: 1, column: column).width, 141, accuracy: 0.01)

        let scaled = PostMediaDesign.tileSize(layout: .h1, index: 0, column: 400)
        XCTAssertEqual(scaled.height, 400 * (160 / 338), accuracy: 0.01)
        XCTAssertEqual(scaled.width, 400, accuracy: 0.01)

        let nineSixteenSingle = PostMediaDesign.displaySize(
            layout: .v1, rawAspect: 9.0 / 16.0, firstRawAspect: 9.0 / 16.0, column: column
        )
        XCTAssertEqual(nineSixteenSingle.width, column * 2 / 3, accuracy: 0.01)
        XCTAssertEqual(nineSixteenSingle.width / nineSixteenSingle.height, 9.0 / 16.0, accuracy: 0.01)

        let squareSingle = PostMediaDesign.displaySize(
            layout: .h1, rawAspect: 1, firstRawAspect: 1, column: column
        )
        XCTAssertEqual(squareSingle.width, column, accuracy: 0.01)
        XCTAssertEqual(squareSingle.height, column, accuracy: 0.01)

        let fourThreeSingle = PostMediaDesign.displaySize(
            layout: .h1, rawAspect: 4.0 / 3.0, firstRawAspect: 4.0 / 3.0, column: column
        )
        XCTAssertEqual(fourThreeSingle.width, column, accuracy: 0.01)
        XCTAssertEqual(fourThreeSingle.width / fourThreeSingle.height, 4.0 / 3.0, accuracy: 0.01)

        let threeFourSingle = PostMediaDesign.displaySize(
            layout: .v1, rawAspect: 3.0 / 4.0, firstRawAspect: 3.0 / 4.0, column: column
        )
        XCTAssertEqual(threeFourSingle.width, column, accuracy: 0.01)
        XCTAssertEqual(threeFourSingle.width / threeFourSingle.height, 3.0 / 4.0, accuracy: 0.01)

        let sixteenNineSingle = PostMediaDesign.displaySize(
            layout: .h1, rawAspect: 16.0 / 9.0, firstRawAspect: 16.0 / 9.0, column: column
        )
        XCTAssertEqual(sixteenNineSingle.width, column, accuracy: 0.01)
        XCTAssertEqual(sixteenNineSingle.width / sixteenNineSingle.height, 16.0 / 9.0, accuracy: 0.01)

        let albumSquare = PostMediaDesign.displaySize(
            layout: .h3Plus, rawAspect: 1, firstRawAspect: 1, column: column
        )
        XCTAssertEqual(albumSquare.width, column * 2 / 3, accuracy: 0.01)
        XCTAssertEqual(albumSquare.height, column * 2 / 3, accuracy: 0.01)

        let albumWide = PostMediaDesign.displaySize(
            layout: .h2, rawAspect: 16.0 / 9.0, firstRawAspect: 16.0 / 9.0, column: column
        )
        XCTAssertEqual(albumWide.width, column * 2 / 3, accuracy: 0.01)
        XCTAssertEqual(albumWide.width / albumWide.height, 16.0 / 9.0, accuracy: 0.01)

        let mixedFollowsFirst = PostMediaDesign.displaySize(
            layout: .mixed, rawAspect: 16.0 / 9.0, firstRawAspect: 9.0 / 16.0, column: column
        )
        XCTAssertEqual(mixedFollowsFirst.width / mixedFollowsFirst.height, 9.0 / 16.0, accuracy: 0.01)
        XCTAssertEqual(mixedFollowsFirst.width, column * 2 / 3, accuracy: 0.01)

        let iphonePortrait = 9.0 / 19.5
        let tallNineSixteen = PostMediaDesign.displaySize(
            layout: .v1, rawAspect: iphonePortrait, firstRawAspect: iphonePortrait, column: column
        )
        XCTAssertEqual(tallNineSixteen.width, column * 2 / 3, accuracy: 0.01)
        XCTAssertEqual(tallNineSixteen.width / tallNineSixteen.height, iphonePortrait, accuracy: 0.01)
        XCTAssertGreaterThan(tallNineSixteen.height, (column * 2 / 3) * 16.0 / 9.0)
    }

    func testPostRelativeTimestampUsesCompactUnitsThenDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        let locale = Locale(identifier: "en_GB")
        let now = calendar.date(from: DateComponents(year: 2025, month: 9, day: 13, hour: 16))!

        func format(_ date: Date) -> String {
            PostRelativeTimestamp.string(from: date, now: now, calendar: calendar, locale: locale)
        }

        XCTAssertEqual(format(now.addingTimeInterval(-12)), "now")
        XCTAssertEqual(format(now.addingTimeInterval(-12 * 60)), "12m")
        XCTAssertEqual(format(now.addingTimeInterval(-3 * 3600)), "3h")
        XCTAssertEqual(format(now.addingTimeInterval(-86_400)), "12 Sep")
        XCTAssertEqual(
            format(calendar.date(from: DateComponents(year: 2025, month: 9, day: 10, hour: 9))!),
            "10 Sep"
        )
        XCTAssertEqual(
            format(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!),
            "1 Jan 2024"
        )
    }

    func testPostAbsoluteTimestampUsesFigmaDetailFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_GB")
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 18, minute: 42))!
        XCTAssertEqual(
            PostRelativeTimestamp.absoluteString(from: date, calendar: calendar, locale: locale),
            "18:42  06.09.2026"
        )
    }

    func testUserProfileDTOAcceptsLegacyThreadAndVideoCounts() throws {
        let json = """
        {
          "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
          "username": "demo",
          "display_name": "Demo",
          "follower_count": 3,
          "following_count": 2,
          "is_following": false,
          "thread_count": 12,
          "video_count": 4
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(UserProfileDTO.self, from: json)
        XCTAssertEqual(dto.takeCount, 12)
        XCTAssertEqual(dto.shotCount, 4)
    }

    func testUserProfileDTOPrefersTakeAndShotCounts() throws {
        let json = """
        {
          "id": "01JABCDEFGHJKMNPQRSTVWXYZ0",
          "username": "demo",
          "display_name": "Demo",
          "follower_count": 0,
          "following_count": 0,
          "is_following": true,
          "take_count": 8,
          "shot_count": 1,
          "thread_count": 99,
          "video_count": 99
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(UserProfileDTO.self, from: json)
        XCTAssertEqual(dto.takeCount, 8)
        XCTAssertEqual(dto.shotCount, 1)
    }

    func testAPIDateParserReadsChronoRfc3339() {
        let withFraction = "2025-09-13T00:00:00.123456789+00:00"
        XCTAssertNotNil(APIDateParser.parse(withFraction))
        XCTAssertNil(ISO8601DateFormatter().date(from: withFraction))
        XCTAssertNotNil(APIDateParser.parse("2025-09-13T00:00:00Z"))
        XCTAssertNotNil(APIDateParser.parse("2025-09-13T00:00:00+00:00"))
        XCTAssertNil(APIDateParser.parse(nil))
        XCTAssertNil(APIDateParser.parse(""))
    }

    func testAPIDateParserDayRoundTripUsesLocalCalendar() throws {
        let raw = "2000-06-15"
        let date = try XCTUnwrap(APIDateParser.parseDay(raw))
        XCTAssertEqual(APIDateParser.formatDay(date), raw)

        // Local midnight of that calendar day must not shift when formatted.
        var comps = DateComponents()
        comps.year = 1999
        comps.month = 12
        comps.day = 31
        let localMidnight = try XCTUnwrap(Calendar.current.date(from: comps))
        XCTAssertEqual(APIDateParser.formatDay(localMidnight), "1999-12-31")
        XCTAssertEqual(
            APIDateParser.formatDay(try XCTUnwrap(APIDateParser.parseDay("1999-12-31"))),
            "1999-12-31"
        )
    }

    @MainActor
    func testEditProfileForcesSensitiveOffWhenDemotedToMinor() {
        let adultDOB = Calendar.current.date(byAdding: .year, value: -25, to: Date())!
        let minorDOB = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        let adultProfile = UserProfile(
            id: "u1",
            username: "demo",
            displayName: "Demo",
            bio: nil,
            avatarURL: nil,
            suiWallet: nil,
            createdAt: nil,
            followerCount: 0,
            followingCount: 0,
            isFollowing: false,
            takeCount: 0,
            shotCount: 0,
            dateOfBirth: adultDOB,
            showSensitiveContent: true,
            isAdult: true
        )

        XCTAssertTrue(
            EditProfileViewModel.shouldForceSensitiveOff(previous: adultProfile, nextDateOfBirth: nil)
        )
        XCTAssertTrue(
            EditProfileViewModel.shouldForceSensitiveOff(previous: adultProfile, nextDateOfBirth: minorDOB)
        )
        XCTAssertFalse(
            EditProfileViewModel.shouldForceSensitiveOff(previous: adultProfile, nextDateOfBirth: adultDOB)
        )
    }

    func testCommentFallsBackToCurrentUserAvatar() {
        let avatar = URL(string: "https://media.altons.trade/avatars/me.jpg")!
        let comment = Comment(
            id: "c1",
            postID: "p1",
            authorID: "u1",
            authorUsername: "paul",
            authorDisplayName: "Paul Steelway",
            authorAvatarURL: nil,
            content: "hello",
            createdAt: nil,
            showInFeed: true,
            parentCommentID: nil,
            mediaKey: nil,
            thumbnailKey: nil,
            imageURLs: [],
            sticker: nil,
            gif: nil,
            likeCount: 0,
            isLiked: false
        )
        let me = User(
            id: "u1",
            username: "paul",
            displayName: "Paul Steelway",
            bio: nil,
            avatarURL: avatar,
            suiWallet: nil,
            createdAt: nil
        )
        XCTAssertEqual(comment.resolvedAuthorAvatarURL(currentUser: me), avatar)
        XCTAssertEqual(comment.fillingAuthorAvatar(avatar).authorAvatarURL, avatar)
        XCTAssertNil(comment.resolvedAuthorAvatarURL(currentUser: nil))
    }

    @MainActor
    func testShotFeedDefaultAdSlotsMatchTakeCadence() {
        let slots = ShotFeedViewModel.defaultAdSlots(shotCount: 12)
        XCTAssertEqual(slots.map(\.position), [3, 8])
        XCTAssertTrue(slots.allSatisfy { $0.placementID == NativeAdPool.shotFeedPlacementID })
        XCTAssertTrue(ShotFeedViewModel.defaultAdSlots(shotCount: 2).isEmpty)
    }

    @MainActor
    func testShotFeedIgnoresTakePlacementSlots() {
        let mixed = [
            FeedAdSlot(placementID: NativeAdPool.feedPlacementID, position: 3),
            FeedAdSlot(placementID: NativeAdPool.shotFeedPlacementID, position: 5),
        ]
        XCTAssertEqual(ShotFeedViewModel.shotFeedSlots(from: mixed).map(\.position), [5])
    }

    @MainActor
    func testShotFeedBuildDisplayRowsInsertsFullscreenAds() {
        let items = (1...5).map { Self.makeShotFeedItem(id: "s\($0)") }
        let rows = ShotFeedViewModel.buildDisplayRows(
            items: items,
            adSlots: [FeedAdSlot(placementID: NativeAdPool.shotFeedPlacementID, position: 3)]
        )
        XCTAssertEqual(rows.map(\.id), ["s1", "s2", "s3", "ad-shot_feed_native-3", "s4", "s5"])
    }

    private static func makeShotFeedItem(id: String) -> FeedItem {
        FeedItem(
            post: Post(
                id: id,
                creatorID: "user-1",
                creatorUsername: "user",
                creatorDisplayName: "User",
                creatorAvatarURL: nil,
                postType: .shot,
                status: .published,
                content: nil,
                mediaKey: nil,
                thumbnailKey: nil,
                playbackURL: nil,
                thumbnailURL: nil,
                imageURLs: [],
                viewCount: 0,
                likeCount: 0,
                commentCount: 0,
                saveCount: 0,
                shareCount: 0,
                repostCount: 0,
                isLiked: false,
                isBookmarked: false,
                isReposted: false,
                createdAt: nil
            ),
            finalScore: 0,
            userScore: 0,
            creatorScore: 0,
            brandScore: 0
        )
    }

    func testContentCategoryTaxonomyHasExpectedSize() {
        XCTAssertGreaterThanOrEqual(ContentCategory.all.count, 25)
        XCTAssertNotNil(ContentCategory.category(id: "sports"))
        XCTAssertTrue(ContentCategory.category(id: "sports")!.subcategories.contains("football_soccer"))
        let interest = Interest.categoryLevel(category: "gaming", weight: 1)
        XCTAssertEqual(interest.subcategory, "gaming_other")
        XCTAssertEqual(Gender.nonBinary.rawValue, "non_binary")
    }

    func testShotCommentsSheetHeightUsesPreferredRatioWhenKeyboardHidden() {
        let height = ShotCommentsSheetLayout.sheetHeight(
            viewHeight: 800,
            availableAboveKeyboard: 800 - 56
        )
        XCTAssertEqual(height, 800 * 0.65, accuracy: 0.5)
    }

    func testShotCommentsSheetHeightShrinksAboveKeyboard() {
        let height = ShotCommentsSheetLayout.sheetHeight(
            viewHeight: 800,
            availableAboveKeyboard: 320
        )
        XCTAssertEqual(height, 320, accuracy: 0.5)
        XCTAssertLessThan(height, 800 * 0.65)
    }

    func testShotCommentsSheetHeightNeverExceedsAvailableSpace() {
        let height = ShotCommentsSheetLayout.sheetHeight(
            viewHeight: 900,
            availableAboveKeyboard: 200
        )
        XCTAssertLessThanOrEqual(height, 200)
    }

    func testShotCommentsSheetHeightHandlesZeroAvailable() {
        // Keyboard guide not ready yet — fall back to preferred ratio (avoid 0-height flash).
        let height = ShotCommentsSheetLayout.sheetHeight(
            viewHeight: 800,
            availableAboveKeyboard: 0
        )
        XCTAssertEqual(height, 800 * 0.65, accuracy: 0.5)
    }

    func testShotCommentsSheetHeightUsesMinHeightWhenSpaceAllows() {
        // Preferred would be tiny if ratio were small; with normal ratio, minHeight floors when
        // available is between minHeight and preferred.
        let height = ShotCommentsSheetLayout.sheetHeight(
            viewHeight: 400,
            availableAboveKeyboard: 300,
            ratio: 0.5,
            minHeight: 280
        )
        // preferred = 200, space = 300 >= 280 → min(300, max(280, 200)) = 280
        XCTAssertEqual(height, 280, accuracy: 0.5)
    }

    func testShotCommentsSheetHeightDoesNotForceMinHeightAboveAvailable() {
        let height = ShotCommentsSheetLayout.sheetHeight(
            viewHeight: 800,
            availableAboveKeyboard: 200,
            minHeight: 280
        )
        XCTAssertEqual(height, 200, accuracy: 0.5)
    }

    @MainActor
    func testPeekSuppressBlocksOnlyLockedPost() {
        let suppress = ProfilePeekSuppressController(graceNanoseconds: 50_000_000)
        suppress.begin(lockID: "a")
        XCTAssertFalse(suppress.allowsActivation(for: "a"))
        XCTAssertTrue(suppress.allowsActivation(for: "b"))
        suppress.end()
        XCTAssertFalse(suppress.allowsActivation(for: "a"))
        XCTAssertTrue(suppress.allowsActivation(for: "b"))
    }

    @MainActor
    func testPeekSuppressAllowsActivationDoesNotClearLock() {
        let suppress = ProfilePeekSuppressController(graceNanoseconds: 200_000_000)
        suppress.begin(lockID: "a")
        suppress.end()
        XCTAssertFalse(suppress.allowsActivation(for: "a"))
        XCTAssertFalse(suppress.allowsActivation(for: "a"))
        XCTAssertEqual(suppress.lockedPostID, "a")
        suppress.clear()
        XCTAssertNil(suppress.lockedPostID)
        XCTAssertTrue(suppress.allowsActivation(for: "a"))
    }

    @MainActor
    func testPeekSuppressNewPeekInvalidatesPriorGrace() async {
        let suppress = ProfilePeekSuppressController(graceNanoseconds: 20_000_000)
        suppress.begin(lockID: "a")
        suppress.end()
        suppress.begin(lockID: "b")
        XCTAssertEqual(suppress.lockedPostID, "b")
        XCTAssertTrue(suppress.allowsActivation(for: "a"))
        XCTAssertFalse(suppress.allowsActivation(for: "b"))
        suppress.end()
        let unlocked = await waitUntilPeekUnlocked(suppress, timeoutNanoseconds: 500_000_000)
        XCTAssertTrue(unlocked)
    }

    @MainActor
    func testPeekSuppressGraceUnlocksAfterDelay() async {
        let suppress = ProfilePeekSuppressController(graceNanoseconds: 20_000_000)
        suppress.begin(lockID: "a")
        suppress.end()
        XCTAssertEqual(suppress.lockedPostID, "a")
        let unlocked = await waitUntilPeekUnlocked(suppress, timeoutNanoseconds: 500_000_000)
        XCTAssertTrue(unlocked)
    }

    /// Overlay tap-dismiss must call end() — begin without end leaves the cell locked.
    @MainActor
    func testPeekSuppressOverlayDismissRequiresEnd() async {
        let suppress = ProfilePeekSuppressController(graceNanoseconds: 20_000_000)
        suppress.begin(lockID: "shot-1")
        XCTAssertFalse(suppress.allowsActivation(for: "shot-1"))
        suppress.end()
        let unlocked = await waitUntilPeekUnlocked(suppress, timeoutNanoseconds: 500_000_000)
        XCTAssertTrue(unlocked)
        XCTAssertTrue(suppress.allowsActivation(for: "shot-1"))
    }

    @MainActor
    func testPeekSuppressDoubleEndDoesNotRestartGrace() async {
        let suppress = ProfilePeekSuppressController(graceNanoseconds: 40_000_000)
        suppress.begin(lockID: "a")
        suppress.end()
        // Second end (e.g. overlay tap after gesture release) must not restart the timer.
        try? await Task.sleep(nanoseconds: 25_000_000)
        suppress.end()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(suppress.lockedPostID)
    }

    @MainActor
    private func waitUntilPeekUnlocked(
        _ suppress: ProfilePeekSuppressController,
        timeoutNanoseconds: UInt64
    ) async -> Bool {
        let step: UInt64 = 5_000_000
        var waited: UInt64 = 0
        while suppress.lockedPostID != nil, waited < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: step)
            waited += step
        }
        return suppress.lockedPostID == nil
    }
}
