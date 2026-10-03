import CoreGraphics
import Foundation
import ImageIO
import Observation

enum PostType: String, Codable, Sendable {
    case take
    case shot

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "shot", "video":
            self = .shot
        case "take", "thread":
            self = .take
        default:
            self = .take
        }
    }
}

enum PostStatus: String, Codable, Sendable {
    case draft
    case processing
    case moderation
    case published
    case rejected

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "draft": self = .draft
        case "processing": self = .processing
        case "moderation": self = .moderation
        case "published": self = .published
        case "rejected": self = .rejected
        default: self = .processing
        }
    }
}

struct Post: Equatable, Identifiable, Sendable {
    let id: String
    let creatorID: String
    let creatorUsername: String?
    let creatorDisplayName: String?
    let creatorAvatarURL: URL?
    let postType: PostType
    let status: PostStatus
    let content: String?
    let mediaKey: String?
    let thumbnailKey: String?
    let playbackURL: URL?
    let thumbnailURL: URL?
    let imageURLs: [URL]
    var viewCount: Int
    var likeCount: Int
    var commentCount: Int
    var saveCount: Int
    var shareCount: Int
    var repostCount: Int
    var isLiked: Bool
    var isBookmarked: Bool
    var isReposted: Bool
    let createdAt: Date?
    /// Moderation: blur media until the viewer taps through.
    let sensitiveBlur: Bool
    /// Raw v2 moderation action from API (`publish_age_gated`, `hold_for_review`, …).
    let moderationAction: String?
    /// Owner-facing rejection / policy reason (S-code or free text) when present.
    let moderationReason: String?
    /// False after manual review cleared the post (or for own content from the API).
    let canReport: Bool
    /// True when the post may appear in feed candidates.
    let feedEligible: Bool
    /// True when content requires an age gate (18+).
    let ageGated: Bool
    /// Per-image blur flags aligned with `imageURLs`; empty when API omits per-media moderation.
    let mediaBlurFlags: [Bool]
    /// Slots vision never saw — blur stays locked (no tap-to-reveal).
    let mediaUnknownFlags: [Bool]
    let subtitlesURL: URL?
    let subtitlesLanguage: String?

    init(
        id: String,
        creatorID: String,
        creatorUsername: String?,
        creatorDisplayName: String?,
        creatorAvatarURL: URL?,
        postType: PostType,
        status: PostStatus,
        content: String?,
        mediaKey: String?,
        thumbnailKey: String?,
        playbackURL: URL?,
        thumbnailURL: URL?,
        imageURLs: [URL],
        viewCount: Int,
        likeCount: Int,
        commentCount: Int,
        saveCount: Int,
        shareCount: Int,
        repostCount: Int,
        isLiked: Bool,
        isBookmarked: Bool,
        isReposted: Bool,
        createdAt: Date?,
        sensitiveBlur: Bool = false,
        moderationAction: String? = nil,
        moderationReason: String? = nil,
        canReport: Bool = true,
        feedEligible: Bool = true,
        ageGated: Bool = false,
        mediaBlurFlags: [Bool] = [],
        mediaUnknownFlags: [Bool] = [],
        subtitlesURL: URL? = nil,
        subtitlesLanguage: String? = nil
    ) {
        self.id = id
        self.creatorID = creatorID
        self.creatorUsername = creatorUsername
        self.creatorDisplayName = creatorDisplayName
        self.creatorAvatarURL = creatorAvatarURL
        self.postType = postType
        self.status = status
        self.content = content
        self.mediaKey = mediaKey
        self.thumbnailKey = thumbnailKey
        self.playbackURL = playbackURL
        self.thumbnailURL = thumbnailURL
        self.imageURLs = imageURLs
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.saveCount = saveCount
        self.shareCount = shareCount
        self.repostCount = repostCount
        self.isLiked = isLiked
        self.isBookmarked = isBookmarked
        self.isReposted = isReposted
        self.createdAt = createdAt
        self.sensitiveBlur = sensitiveBlur
        self.moderationAction = moderationAction
        self.moderationReason = moderationReason
        self.canReport = canReport
        self.feedEligible = feedEligible
        self.ageGated = ageGated
        self.mediaBlurFlags = mediaBlurFlags
        self.mediaUnknownFlags = mediaUnknownFlags
        self.subtitlesURL = subtitlesURL
        self.subtitlesLanguage = subtitlesLanguage
    }

    func blursImage(at index: Int) -> Bool {
        if mediaBlurFlags.indices.contains(index) {
            return mediaBlurFlags[index]
        }
        return sensitiveBlur
    }

    func isUnknownImage(at index: Int) -> Bool {
        mediaUnknownFlags.indices.contains(index) && mediaUnknownFlags[index]
    }

    func allowsRevealImage(at index: Int) -> Bool {
        !isUnknownImage(at: index)
    }

    func isSensitiveImage(at index: Int) -> Bool {
        blursImage(at: index) || isUnknownImage(at: index)
    }

    var requiresAgeGate: Bool { ageGated }

    var listSnippet: String? {
        AgeRestrictedContentPolicy.snippet(content: content, postID: id, ageGated: ageGated)
    }

    var allowsCopyingContent: Bool {
        AgeRestrictedContentPolicy.allowsCopy(content: content, postID: id, ageGated: ageGated)
    }

    func updatingEngagement(
        viewCount: Int? = nil,
        likeCount: Int? = nil,
        commentCount: Int? = nil,
        saveCount: Int? = nil,
        shareCount: Int? = nil,
        repostCount: Int? = nil,
        isLiked: Bool? = nil,
        isBookmarked: Bool? = nil,
        isReposted: Bool? = nil
    ) -> Post {
        Post(
            id: id,
            creatorID: creatorID,
            creatorUsername: creatorUsername,
            creatorDisplayName: creatorDisplayName,
            creatorAvatarURL: creatorAvatarURL,
            postType: postType,
            status: status,
            content: content,
            mediaKey: mediaKey,
            thumbnailKey: thumbnailKey,
            playbackURL: playbackURL,
            thumbnailURL: thumbnailURL,
            imageURLs: imageURLs,
            viewCount: viewCount ?? self.viewCount,
            likeCount: likeCount ?? self.likeCount,
            commentCount: commentCount ?? self.commentCount,
            saveCount: saveCount ?? self.saveCount,
            shareCount: shareCount ?? self.shareCount,
            repostCount: repostCount ?? self.repostCount,
            isLiked: isLiked ?? self.isLiked,
            isBookmarked: isBookmarked ?? self.isBookmarked,
            isReposted: isReposted ?? self.isReposted,
            createdAt: createdAt,
            sensitiveBlur: sensitiveBlur,
            moderationAction: moderationAction,
            moderationReason: moderationReason,
            canReport: canReport,
            feedEligible: feedEligible,
            ageGated: ageGated,
            mediaBlurFlags: mediaBlurFlags,
            mediaUnknownFlags: mediaUnknownFlags,
            subtitlesURL: subtitlesURL,
            subtitlesLanguage: subtitlesLanguage
        )
    }

    var creatorHandle: String {
        resolvedCreatorHandle(currentUser: nil)
    }

    var creatorInitials: String {
        resolvedCreatorInitials(currentUser: nil)
    }

    /// Prefer first/last display name; fall back to `@username`.
    func resolvedCreatorDisplayName(currentUser: User?) -> String {
        if let creatorDisplayName, !creatorDisplayName.isEmpty {
            return creatorDisplayName
        }
        if let currentUser, creatorID == currentUser.id, !currentUser.displayName.isEmpty {
            return currentUser.displayName
        }
        return resolvedAtUsername(currentUser: currentUser)
    }

    func resolvedAtUsername(currentUser: User?) -> String {
        let username = resolvedCreatorHandle(currentUser: currentUser)
        if username.hasPrefix("@") { return username }
        if username == creatorID { return username }
        return "@\(username)"
    }

    func resolvedCreatorHandle(currentUser: User?) -> String {
        if let creatorUsername, !creatorUsername.isEmpty {
            return creatorUsername
        }
        if let currentUser, creatorID == currentUser.id, !currentUser.username.isEmpty {
            return currentUser.username
        }
        return creatorID
    }

    func resolvedCreatorAvatarURL(currentUser: User?) -> URL? {
        if let creatorAvatarURL {
            return creatorAvatarURL
        }
        if let currentUser, creatorID == currentUser.id {
            return currentUser.avatarURL
        }
        return nil
    }

    func resolvedCreatorInitials(currentUser: User?) -> String {
        String(resolvedCreatorDisplayName(currentUser: currentUser).prefix(2)).uppercased()
    }

    /// 512px thumbs for the feed grid. Full `imageURLs` stay for lightbox only.
    var feedThumbnailURLs: [URL] {
        MediaThumbnailURL.thumbnails(
            imageURLs: imageURLs,
            thumbnailURL: thumbnailURL,
            thumbnailKey: thumbnailKey
        )
    }
}

/// Feed timestamp: `12m` / `3h` within 24 hours, then a calendar date (Figma post header).
enum PostRelativeTimestamp {
    static func string(
        from date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return "now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.doesRelativeDateFormatting = false
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("d MMM y")
        }
        return formatter.string(from: date)
    }

    /// Absolute post time as in Figma detail: `HH:mm  dd.MM.yyyy`.
    static func absoluteString(
        from date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm  dd.MM.yyyy"
        return formatter.string(from: date)
    }
}

/// Storage layout from media-service: `media/{id}/image_{n}.{ext}` + `thumb_{n}.webp`.
enum MediaThumbnailURL {
    static func thumbnails(
        imageURLs: [URL],
        thumbnailURL: URL?,
        thumbnailKey: String?
    ) -> [URL] {
        let ext = thumbExtension(hint: thumbnailURL, thumbnailKey: thumbnailKey)
        if !imageURLs.isEmpty {
            return imageURLs.map { url in
                if url.pathExtension.lowercased() == "gif" {
                    // Still thumb for progressive loading; full GIF loads on top in HugPhoto.
                    return derived(fromPlayback: url, thumbExtension: ext) ?? url
                }
                return derived(fromPlayback: url, thumbExtension: ext) ?? thumbnailURL ?? url
            }
        }
        if let thumbnailURL {
            return [thumbnailURL]
        }
        return []
    }

    static func derived(fromPlayback url: URL, thumbExtension: String? = nil) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let path = components.path
        let fileName = (path as NSString).lastPathComponent
        let directory = (path as NSString).deletingLastPathComponent
        let ext = normalizedExtension(thumbExtension) ?? "webp"

        if fileName.hasPrefix("thumb") {
            return url
        }

        if let index = imageIndex(from: fileName) {
            components.path = directory + "/thumb_\(index).\(ext)"
            return components.url
        }

        if fileName.hasPrefix("video.") {
            components.path = directory + "/thumb.\(ext)"
            return components.url
        }

        return nil
    }

    static func pixelSize(of data: Data) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else {
            return nil
        }

        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    static func fittedSize(maxWidth: CGFloat, maxHeight: CGFloat, aspect: CGFloat) -> CGSize {
        guard aspect > 0, maxWidth > 0, maxHeight > 0 else {
            return CGSize(width: max(maxWidth, 0), height: min(max(maxHeight, 0), 160))
        }
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    /// Shared row height so N photos fill `containerWidth` without letterboxing.
    static func rowHeight(
        containerWidth: CGFloat,
        aspects: [CGFloat],
        spacing: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        guard containerWidth > 0, !aspects.isEmpty else {
            return min(160, maxHeight)
        }
        let sum = aspects.reduce(0, +)
        guard sum > 0 else { return min(160, maxHeight) }
        let gaps = spacing * CGFloat(max(aspects.count - 1, 0))
        return min(maxHeight, max(1, (containerWidth - gaps) / sum))
    }

    private static func imageIndex(from fileName: String) -> String? {
        guard fileName.hasPrefix("image_") else { return nil }
        let stem = (fileName as NSString).deletingPathExtension
        let index = stem.dropFirst("image_".count)
        guard !index.isEmpty, index.allSatisfy(\.isNumber) else { return nil }
        return String(index)
    }

    private static func thumbExtension(hint: URL?, thumbnailKey: String?) -> String {
        if let hintExt = normalizedExtension(hint?.pathExtension) {
            return hintExt
        }
        if let key = thumbnailKey?.split(separator: ",").first {
            let ext = normalizedExtension(URL(fileURLWithPath: String(key)).pathExtension)
            if let ext { return ext }
        }
        return "webp"
    }

    private static func normalizedExtension(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let ext = raw.lowercased()
        if ext == "jpeg" { return "jpg" }
        if ext == "jpg" || ext == "webp" { return ext }
        return nil
    }
}

/// Session-wide 18+ confirms so feed, detail, embeds, and shots share one tap.
/// Unlock is gated by verified adult status from `date_of_birth` (`viewerIsAdult`).
@Observable
final class AgeGateConfirmationStore {
    static let shared = AgeGateConfirmationStore()

    private(set) var confirmedIDs: Set<String> = []
    /// True when the signed-in viewer has a DOB proving age ≥ 18.
    private(set) var viewerIsAdult = false

    func setViewerIsAdult(_ value: Bool) {
        viewerIsAdult = value
    }

    func isConfirmed(_ id: String) -> Bool {
        if viewerIsAdult { return true }
        return !id.isEmpty && confirmedIDs.contains(id)
    }

    /// Per-post confirm only works for verified adults (legacy session unlock).
    func confirm(_ id: String) {
        guard viewerIsAdult, !id.isEmpty else { return }
        var ids = confirmedIDs
        ids.insert(id)
        confirmedIDs = ids
    }

    func reset() {
        confirmedIDs = []
        viewerIsAdult = false
    }
}

/// In-memory consent to open blurred media without the notice until the app session ends.
@Observable
final class SensitiveRevealSessionStore {
    static let shared = SensitiveRevealSessionStore()

    private(set) var allowsImmediateReveal = false

    func allowForSession() {
        allowsImmediateReveal = true
    }

    func reset() {
        allowsImmediateReveal = false
    }
}

enum ShotMediaLockPolicy {
    enum NextReveal: Equatable {
        case revealSensitive
        case none
    }

    /// Age-gated media is locked for non-adults; verified adults never see the gate.
    static func isAgeLocked(ageGated: Bool) -> Bool {
        ageGated && !AgeGateConfirmationStore.shared.viewerIsAdult
    }

    static func isSensitiveLocked(sensitiveBlur: Bool, sensitiveRevealed: Bool) -> Bool {
        sensitiveBlur && !sensitiveRevealed
    }

    static func isMediaLocked(ageLocked: Bool, sensitiveLocked: Bool) -> Bool {
        ageLocked || sensitiveLocked
    }

    static func nextReveal(
        sensitiveBlur: Bool,
        sensitiveRevealed: Bool
    ) -> NextReveal {
        if sensitiveBlur && !sensitiveRevealed {
            return .revealSensitive
        }
        return .none
    }

    static func allowsPlayer(isMediaLocked: Bool, isActive: Bool, isPreloading: Bool) -> Bool {
        !isMediaLocked && (isActive || isPreloading)
    }

    /// Load the player under blur so sensitive shots show a live blurred frame.
    /// Age-locked media still uses a static placeholder (no decode for minors).
    static func shouldLoadForBlur(isSensitiveLocked: Bool, isAgeLocked: Bool) -> Bool {
        isSensitiveLocked && !isAgeLocked
    }
}

/// Shared visibility rules for feed, profile grids, and profile shot pagers.
enum ViewerContentFilterPolicy {
    /// Own profile keeps every post (owner moderation UX); strangers follow feed rules.
    static func allowsPost(
        _ post: Post,
        viewerIsAdult: Bool,
        showSensitiveContent: Bool,
        isOwnProfile: Bool = false
    ) -> Bool {
        allows(
            ageGated: post.ageGated,
            sensitiveBlur: post.sensitiveBlur,
            viewerIsAdult: viewerIsAdult,
            showSensitiveContent: showSensitiveContent,
            isOwnProfile: isOwnProfile
        )
    }

    static func allows(
        ageGated: Bool,
        sensitiveBlur: Bool,
        viewerIsAdult: Bool,
        showSensitiveContent: Bool,
        isOwnProfile: Bool = false
    ) -> Bool {
        if isOwnProfile { return true }
        if !viewerIsAdult && ageGated { return false }
        if !viewerIsAdult && sensitiveBlur { return false }
        if !showSensitiveContent && sensitiveBlur { return false }
        return true
    }

    static func allowsTimelineItem(
        _ item: FeedTimelineItem,
        viewerIsAdult: Bool,
        showSensitiveContent: Bool
    ) -> Bool {
        allows(
            ageGated: item.isAgeGatedContent,
            sensitiveBlur: item.isSensitiveBlurContent,
            viewerIsAdult: viewerIsAdult,
            showSensitiveContent: showSensitiveContent
        )
    }

    static func filterPosts(
        _ posts: [Post],
        viewerIsAdult: Bool,
        showSensitiveContent: Bool,
        isOwnProfile: Bool = false
    ) -> [Post] {
        posts.filter {
            allowsPost(
                $0,
                viewerIsAdult: viewerIsAdult,
                showSensitiveContent: showSensitiveContent,
                isOwnProfile: isOwnProfile
            )
        }
    }

    /// User-facing reason when a deep link / notification targets filtered content.
    static func blockedOpenMessage(
        for post: Post,
        viewerIsAdult: Bool,
        showSensitiveContent: Bool
    ) -> String? {
        guard !allowsPost(
            post,
            viewerIsAdult: viewerIsAdult,
            showSensitiveContent: showSensitiveContent
        ) else { return nil }
        if !viewerIsAdult {
            return "This content isn't available for your account."
        }
        return "Sensitive content is hidden. Turn on Show Sensitive Content in Settings to view it."
    }
}

enum PostMediaLayoutProbe {
    static func shouldProbeRemoteSize(
        isSensitive: Bool,
        isUnknown: Bool,
        isRevealed: Bool = false
    ) -> Bool {
        if isRevealed { return true }
        // Sensitive photos still need their real aspect so the blur matches the picture.
        return !isUnknown
    }
}

enum ParentPreviewNavigationPolicy {
    static func allowsNavigate(ageGated: Bool, ageConfirmed: Bool) -> Bool {
        if !ageGated { return true }
        return AgeGateConfirmationStore.shared.viewerIsAdult || ageConfirmed
    }
}

enum AgeRestrictedContentPolicy {
    static let redactedSnippet = "18+ content"

    static func snippet(content: String?, postID: String, ageGated: Bool) -> String? {
        guard let content, !content.isEmpty else { return nil }
        if ageGated && !AgeGateConfirmationStore.shared.isConfirmed(postID) {
            return redactedSnippet
        }
        return content
    }

    static func allowsCopy(content: String?, postID: String, ageGated: Bool) -> Bool {
        guard let content, !content.isEmpty else { return false }
        return !(ageGated && !AgeGateConfirmationStore.shared.isConfirmed(postID))
    }

    static func forwardsContentInteraction(isGated: Bool) -> Bool {
        !isGated
    }

    static func hidesContentFromAccessibility(isGated: Bool) -> Bool {
        isGated
    }
}

/// Figma `post` photo axis (h1/h2/h3+, v1/v2/v3+, mixed) as fractions of the 338pt media column.
enum PostMediaDesign {
    static let figmaColumn: CGFloat = 338
    static let cornerRadius: CGFloat = 8

    static let h1Height = 160 / figmaColumn
    static let v1Height = 385 / figmaColumn
    static let h2Height = 120 / figmaColumn
    static let h2Gap: CGFloat = 8
    static let h3Width = 224 / figmaColumn
    static let h3Height = 160 / figmaColumn
    static let h3Gap: CGFloat = 10
    static let vTileWidth = 212 / figmaColumn
    static let vTileHeight = 240 / figmaColumn
    static let vGap: CGFloat = 8
    static let mixedWide = 224 / figmaColumn
    static let mixedNarrow = 141 / figmaColumn
    static let mixedHeight = 160 / figmaColumn
    static let mixedGap: CGFloat = 8

    enum Layout: Equatable {
        case h1
        case h2
        case h3Plus
        case v1
        case v2
        case v3Plus
        case mixed
    }

    /// `portrait` is true when height > width.
    static func layout(portraits: [Bool]) -> Layout {
        guard !portraits.isEmpty else { return .h1 }
        if portraits.count == 1 {
            return portraits[0] ? .v1 : .h1
        }
        let portraitCount = portraits.filter(\.self).count
        let landscapeCount = portraits.count - portraitCount
        if portraitCount > 0, landscapeCount > 0 {
            return .mixed
        }
        if portraitCount == portraits.count {
            return portraits.count == 2 ? .v2 : .v3Plus
        }
        return portraits.count == 2 ? .h2 : .h3Plus
    }

    static func tileSize(layout: Layout, index: Int, column: CGFloat) -> CGSize {
        let width = max(column, 1)
        switch layout {
        case .h1:
            return CGSize(width: width, height: width * h1Height)
        case .v1:
            return CGSize(width: width, height: width * v1Height)
        case .h2:
            return CGSize(width: (width - h2Gap) / 2, height: width * h2Height)
        case .h3Plus:
            return CGSize(width: width * h3Width, height: width * h3Height)
        case .v2, .v3Plus:
            return CGSize(width: width * vTileWidth, height: width * vTileHeight)
        case .mixed:
            let ratio = index.isMultiple(of: 2) ? mixedWide : mixedNarrow
            return CGSize(width: width * ratio, height: width * mixedHeight)
        }
    }

    static let albumWidthFraction: CGFloat = 2.0 / 3.0

    enum AspectFormat: CaseIterable, Equatable {
        case sixteenNine
        case fourThree
        case square
        case threeFour
        case nineSixteen

        var aspect: CGFloat {
            switch self {
            case .sixteenNine: return 16.0 / 9.0
            case .fourThree: return 4.0 / 3.0
            case .square: return 1
            case .threeFour: return 3.0 / 4.0
            case .nineSixteen: return 9.0 / 16.0
            }
        }

        /// Snap a raw width/height ratio to the nearest popular feed format.
        static func snapping(_ rawAspect: CGFloat) -> AspectFormat {
            let raw = rawAspect > 0 ? rawAspect : 1
            return AspectFormat.allCases.min { lhs, rhs in
                abs(lhs.aspect - raw) < abs(rhs.aspect - raw)
            } ?? .square
        }
    }

    /// Width follows the snapped format. Height follows the real photo so 9:16-class
    /// shots (often 9:19.5) are not cropped to a shorter 9:16 box.
    /// Mixed uses the first photo's aspect for every tile.
    static func displaySize(
        layout: Layout,
        rawAspect: CGFloat,
        firstRawAspect: CGFloat,
        column: CGFloat
    ) -> CGSize {
        let column = max(column, 1)
        let sourceAspect = layout == .mixed ? firstRawAspect : rawAspect
        let format = AspectFormat.snapping(sourceAspect)
        let isAlbum = layout != .h1 && layout != .v1
        let width: CGFloat
        if isAlbum || format == .nineSixteen {
            width = column * albumWidthFraction
        } else {
            width = column
        }
        let aspect = sourceAspect > 0 ? sourceAspect : format.aspect
        return CGSize(width: width, height: width / aspect)
    }

    /// Tile that keeps the photo's aspect (square stays square). Height bands follow Figma h/v.
    static func uncroppedSize(layout: Layout, aspect: CGFloat, column: CGFloat) -> CGSize {
        displaySize(layout: layout, rawAspect: aspect, firstRawAspect: aspect, column: column)
    }

    static var sliderLayouts: Set<Layout> { [.h2, .h3Plus, .v2, .v3Plus, .mixed] }

    static func spacing(for layout: Layout) -> CGFloat {
        switch layout {
        case .h3Plus: return h3Gap
        case .v2, .v3Plus: return vGap
        case .mixed, .h2: return mixedGap
        case .h1, .v1: return 0
        }
    }
}
