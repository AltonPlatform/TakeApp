import SwiftUI

struct PostActionBar: View {
    private let metrics: FeedEngagementMetrics
    var layout: Layout = .horizontal
    var showsCounts: Bool = true
    var showsRepost: Bool = true
    var showsBookmark: Bool = true
    var feedStyle: Bool = false
    var shotFeedStyle: Bool = false
    var onLike: () -> Void
    var onComment: () -> Void
    var onRepost: (() -> Void)? = nil
    var onShare: () -> Void
    var onBookmark: (() -> Void)? = nil

    enum Layout {
        case horizontal
        case vertical
    }

    /// Engagement numbers for feed-style chrome (posts and comment cards).
    struct FeedEngagementMetrics {
        var likeCount: Int
        var isLiked: Bool
        var commentCount: Int
        var shareCount: Int
        var repostCount: Int
        var isReposted: Bool
        var isBookmarked: Bool

        init(post: Post) {
            likeCount = post.likeCount
            isLiked = post.isLiked
            commentCount = post.commentCount
            shareCount = post.shareCount
            repostCount = post.repostCount
            isReposted = post.isReposted
            isBookmarked = post.isBookmarked
        }

        init(
            likeCount: Int,
            isLiked: Bool,
            commentCount: Int = 0,
            shareCount: Int = 0,
            repostCount: Int = 0,
            isReposted: Bool = false,
            isBookmarked: Bool = false
        ) {
            self.likeCount = likeCount
            self.isLiked = isLiked
            self.commentCount = commentCount
            self.shareCount = shareCount
            self.repostCount = repostCount
            self.isReposted = isReposted
            self.isBookmarked = isBookmarked
        }
    }

    init(
        post: Post,
        layout: Layout = .horizontal,
        showsCounts: Bool = true,
        showsRepost: Bool = true,
        showsBookmark: Bool = true,
        feedStyle: Bool = false,
        shotFeedStyle: Bool = false,
        onLike: @escaping () -> Void,
        onComment: @escaping () -> Void,
        onRepost: (() -> Void)? = nil,
        onShare: @escaping () -> Void,
        onBookmark: (() -> Void)? = nil
    ) {
        self.metrics = FeedEngagementMetrics(post: post)
        self.layout = layout
        self.showsCounts = showsCounts
        self.showsRepost = showsRepost
        self.showsBookmark = showsBookmark
        self.feedStyle = feedStyle
        self.shotFeedStyle = shotFeedStyle
        self.onLike = onLike
        self.onComment = onComment
        self.onRepost = onRepost
        self.onShare = onShare
        self.onBookmark = onBookmark
    }

    init(
        metrics: FeedEngagementMetrics,
        layout: Layout = .horizontal,
        showsCounts: Bool = true,
        showsRepost: Bool = true,
        showsBookmark: Bool = true,
        feedStyle: Bool = false,
        shotFeedStyle: Bool = false,
        onLike: @escaping () -> Void,
        onComment: @escaping () -> Void,
        onRepost: (() -> Void)? = nil,
        onShare: @escaping () -> Void,
        onBookmark: (() -> Void)? = nil
    ) {
        self.metrics = metrics
        self.layout = layout
        self.showsCounts = showsCounts
        self.showsRepost = showsRepost
        self.showsBookmark = showsBookmark
        self.feedStyle = feedStyle
        self.shotFeedStyle = shotFeedStyle
        self.onLike = onLike
        self.onComment = onComment
        self.onRepost = onRepost
        self.onShare = onShare
        self.onBookmark = onBookmark
    }

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                if feedStyle {
                    feedHorizontalBar
                } else {
                    horizontalBar
                }
            case .vertical:
                verticalBar
            }
        }
    }

    /// Figma feed chrome: like / comments / share | repost / bookmark
    private var feedHorizontalBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                feedAction(
                    asset: "post.heart",
                    systemFallback: metrics.isLiked ? "heart.fill" : "heart",
                    count: metrics.likeCount,
                    tint: metrics.isLiked ? .red : PostColor.labelSecondary,
                    action: onLike
                )
                feedAction(
                    asset: "post.comment",
                    systemFallback: "bubble.right",
                    count: metrics.commentCount,
                    tint: PostColor.labelSecondary,
                    action: onComment
                )
                feedAction(
                    asset: "post.share",
                    systemFallback: "paperplane",
                    count: metrics.shareCount,
                    tint: PostColor.labelSecondary,
                    action: onShare
                )
            }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                if showsRepost, let onRepost {
                    feedAction(
                        asset: "post.repost",
                        systemFallback: "arrow.2.squarepath",
                        count: metrics.repostCount,
                        tint: metrics.isReposted ? .green : PostColor.labelSecondary,
                        action: onRepost
                    )
                }
                if showsBookmark, let onBookmark {
                    Button(action: onBookmark) {
                        Image("post.bookmark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(metrics.isBookmarked ? PostColor.showMore : PostColor.labelSecondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(metrics.isBookmarked ? "Remove bookmark" : "Bookmark")
                }
            }
        }
    }

    private var horizontalBar: some View {
        HStack(spacing: 24) {
            actionButton(
                icon: metrics.isLiked ? "heart.fill" : "heart",
                count: metrics.likeCount,
                tint: metrics.isLiked ? .red : .primary,
                action: onLike
            )
            actionButton(
                icon: "bubble.right",
                count: metrics.commentCount,
                tint: .primary,
                action: onComment
            )
            if showsRepost, let onRepost {
                actionButton(
                    icon: "arrow.2.squarepath",
                    count: metrics.repostCount,
                    tint: metrics.isReposted ? .green : .primary,
                    action: onRepost
                )
            }
            actionButton(
                icon: "paperplane",
                count: metrics.shareCount,
                tint: .primary,
                action: onShare
            )
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }

    private var verticalBar: some View {
        VStack(spacing: shotFeedStyle ? 20 : 22) {
            verticalAction(
                icon: metrics.isLiked ? "heart.fill" : "heart",
                count: metrics.likeCount,
                tint: metrics.isLiked ? .red : .white,
                action: onLike
            )
            verticalAction(
                icon: shotFeedStyle ? "message.fill" : "bubble.right",
                count: metrics.commentCount,
                tint: .white,
                action: onComment
            )
            verticalAction(
                icon: shotFeedStyle ? "arrowshape.turn.up.forward.fill" : "paperplane",
                count: metrics.shareCount,
                tint: .white,
                action: onShare
            )
        }
    }

    private func feedAction(
        asset: String,
        systemFallback: String,
        count: Int,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                if showsCounts {
                    Text(formatCount(count))
                        .font(PostFont.count)
                }
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(systemFallback)
    }

    private func actionButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body)
                if showsCounts, count > 0 {
                    Text(formatCount(count))
                        .font(.subheadline)
                }
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func verticalAction(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if shotFeedStyle {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    if showsCounts {
                        Text(formatCount(count))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .frame(minWidth: 28)
                            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    }
                }
                .frame(width: 52, height: 58)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
            } else {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.title2)
                    if showsCounts, count > 0 {
                        Text(formatCount(count))
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(tint)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.borderless)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
