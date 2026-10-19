import Foundation

/// Callbacks for interactive shared-post cards inside DM bubbles.
struct ChatSharedPostActions {
    var onAppear: (String) -> Void = { _ in }
    var onOpen: () -> Void = {}
    var onLike: (Post) -> Void = { _ in }
    var onRepost: (Post) -> Void = { _ in }
    var onBookmark: (Post) -> Void = { _ in }
    var onComment: (Post) -> Void = { _ in }
    var onShare: (Post) -> Void = { _ in }
    var onForward: () -> Void = {}

    static let noop = ChatSharedPostActions()
}
