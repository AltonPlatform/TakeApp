import Foundation

/// Merges a hydrated `Post` with the lightweight `DMPostCard` for DM share cards.
/// Priority: Post fields win when present; card fills gaps until hydration finishes.
struct ChatSharedPostDisplay: Equatable, Sendable {
    let postID: String
    let postType: String
    let creatorID: String
    let displayName: String
    let handle: String
    let avatarURL: URL?
    let contentPreview: String
    let thumbnailURLs: [URL]
    let viewCount: Int
    let unavailable: Bool
    let createdAt: Date?
    let ageGated: Bool
    let sensitiveBlur: Bool
    let hasHydratedPost: Bool

    var isShot: Bool { postType.lowercased() == "shot" }
    var isTake: Bool { !isShot }

    static func merge(
        postID: String,
        postTypeHint: String?,
        post: Post?,
        card: DMPostCard?
    ) -> ChatSharedPostDisplay {
        if let post {
            let type = post.postType == .shot ? "shot" : "take"
            let thumbs: [URL]
            if type == "shot" {
                thumbs = [post.thumbnailURL].compactMap { $0 }
            } else if !post.feedThumbnailURLs.isEmpty {
                thumbs = post.feedThumbnailURLs
            } else if !post.imageURLs.isEmpty {
                thumbs = post.imageURLs
            } else {
                thumbs = [post.thumbnailURL].compactMap { $0 }
            }
            let handleRaw = post.creatorUsername ?? card?.creatorUsername ?? ""
            let handle = handleRaw.isEmpty
                ? ""
                : (handleRaw.hasPrefix("@") ? handleRaw : "@\(handleRaw)")
            let display = post.resolvedCreatorDisplayName(currentUser: nil)
            return ChatSharedPostDisplay(
                postID: post.id,
                postType: type,
                creatorID: post.creatorID,
                displayName: display.isEmpty ? (handle.isEmpty ? "User" : handle) : display,
                handle: handle,
                avatarURL: post.creatorAvatarURL ?? card?.creatorAvatarURL,
                contentPreview: post.content ?? card?.contentPreview ?? "",
                thumbnailURLs: thumbs,
                viewCount: post.viewCount,
                unavailable: false,
                createdAt: post.createdAt,
                ageGated: post.ageGated,
                sensitiveBlur: post.sensitiveBlur,
                hasHydratedPost: true
            )
        }

        if let card {
            let type = card.postType.isEmpty
                ? (postTypeHint ?? "take")
                : card.postType
            let handleRaw = card.creatorUsername
            let handle = handleRaw.isEmpty
                ? ""
                : (handleRaw.hasPrefix("@") ? handleRaw : "@\(handleRaw)")
            return ChatSharedPostDisplay(
                postID: card.postID,
                postType: type,
                creatorID: card.creatorID,
                displayName: handle.isEmpty ? "User" : String(handle.dropFirst()),
                handle: handle,
                avatarURL: card.creatorAvatarURL,
                contentPreview: card.contentPreview,
                thumbnailURLs: [card.thumbnailURL].compactMap { $0 },
                viewCount: 0,
                unavailable: card.unavailable,
                createdAt: nil,
                ageGated: false,
                sensitiveBlur: false,
                hasHydratedPost: false
            )
        }

        let type = postTypeHint ?? "take"
        return ChatSharedPostDisplay(
            postID: postID,
            postType: type,
            creatorID: "",
            displayName: "Post",
            handle: "",
            avatarURL: nil,
            contentPreview: "",
            thumbnailURLs: [],
            viewCount: 0,
            unavailable: false,
            createdAt: nil,
            ageGated: false,
            sensitiveBlur: false,
            hasHydratedPost: false
        )
    }
}
