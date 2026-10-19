import NukeUI
import SwiftUI

/// Media-forward shared post card for Direct — separate from the colored chat bubble fill.
struct ChatPostShareCard: View {
    let display: ChatSharedPostDisplay
    let post: Post?
    let isMine: Bool
    /// Time capsule drawn on shot media when there is no caption under the card.
    var mediaMeta: (() -> AnyView)? = nil
    var actions: ChatSharedPostActions = .noop
    @Environment(\.chatBubbleInteractionLocked) private var interactionLocked

    /// Shot frame stays 3:2. Take height follows its text and media.
    static let shotWidth: CGFloat = 210
    static var shotHeight: CGFloat { shotWidth * 3 / 2 }
    static var takeWidth: CGFloat { min(UIScreen.main.bounds.width * 0.8, 320) }

    private var cardWidth: CGFloat {
        display.isShot ? Self.shotWidth : Self.takeWidth
    }

    var body: some View {
        Group {
            if display.unavailable {
                unavailableCard
            } else if display.isShot {
                shotCard
            } else {
                takeCard
            }
        }
        .onAppear {
            actions.onAppear(display.postID)
        }
    }

    // MARK: - Shot

    private var shotCard: some View {
        let width = Self.shotWidth
        let height = Self.shotHeight
        return ZStack(alignment: .bottom) {
            shotThumbnail
                .frame(width: width, height: height)
                .clipped()

            // Top: author
            VStack {
                HStack(spacing: 6) {
                    creatorAvatar(size: 22)
                    Text(shotAuthorLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 56)
                    .frame(maxWidth: .infinity, alignment: .top),
                    alignment: .top
                )
                Spacer(minLength: 0)
            }

            // Bottom: caption + views
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !display.contentPreview.isEmpty {
                            Text(display.contentPreview)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(2)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption2.weight(.semibold))
                            if display.hasHydratedPost {
                                Text(formatCount(display.viewCount))
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let mediaMeta {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        mediaMeta()
                            .padding(.trailing, 8)
                            .padding(.bottom, 6)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !interactionLocked else { return }
            actions.onOpen()
        }
    }

    @ViewBuilder
    private var shotThumbnail: some View {
        if let url = display.thumbnailURLs.first {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.black.opacity(0.12))
                }
            }
            .processors([.resize(width: 480)])
        } else {
            Rectangle().fill(Color.black.opacity(0.12))
        }
    }

    private var shotAuthorLabel: String {
        if !display.displayName.isEmpty, display.displayName != "User", display.displayName != "Post" {
            return display.displayName
        }
        if !display.handle.isEmpty { return display.handle }
        return "Shot"
    }

    // MARK: - Take

    private var takeCard: some View {
        let width = cardWidth
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                creatorAvatar(size: 36)

                VStack(alignment: .leading, spacing: 8) {
                    takeHeader

                    AgeRestrictedMediaGate(isAgeGated: display.ageGated, contentID: display.postID) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !display.contentPreview.isEmpty {
                                takeBodyText
                            }
                            takeMediaGrid
                        }
                    }

                    if let post, display.hasHydratedPost {
                        threadsActionRow(post)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
    }

    /// Threads-style header: bold handle and a quiet relative time on one line.
    private var takeHeader: some View {
        HStack(spacing: 6) {
            Text(takeAuthorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let createdAt = display.createdAt {
                Text(PostRelativeTimestamp.string(from: createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !interactionLocked else { return }
            actions.onOpen()
        }
    }

    private var takeAuthorName: String {
        let handle = display.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if !handle.isEmpty { return handle }
        if !display.displayName.isEmpty,
           display.displayName != "User",
           display.displayName != "Post" {
            return display.displayName
        }
        return "user"
    }

    private func threadsActionRow(_ post: Post) -> some View {
        HStack(spacing: 14) {
            threadsAction(
                systemImage: post.isLiked ? "heart.fill" : "heart",
                count: post.likeCount,
                tint: post.isLiked ? .red : .secondary
            ) {
                actions.onLike(post)
            }
            threadsAction(
                systemImage: "bubble.right",
                count: post.commentCount,
                tint: .secondary
            ) {
                actions.onComment(post)
            }
            threadsAction(
                systemImage: "arrow.2.squarepath",
                count: post.repostCount,
                tint: post.isReposted ? .green : .secondary
            ) {
                actions.onRepost(post)
            }
            threadsAction(
                systemImage: "paperplane",
                count: post.shareCount,
                tint: .secondary
            ) {
                actions.onShare(post)
            }
        }
        .disabled(interactionLocked)
    }

    private func threadsAction(
        systemImage: String,
        count: Int,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !interactionLocked else { return }
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                Text(formatCount(count))
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var takeBodyText: some View {
        let raw = display.contentPreview
        let needsTruncation = raw.count > 250
        let shown = needsTruncation ? truncateAtWordBoundary(raw, limit: 250) : raw
        TakeMarkdownContent(
            content: shown,
            onContentTap: {
                guard !interactionLocked else { return }
                actions.onOpen()
            }
        )
        .lineLimit(needsTruncation ? 8 : nil)
    }

    @ViewBuilder
    private var takeMediaGrid: some View {
        let urls = display.thumbnailURLs
        if urls.isEmpty {
            EmptyView()
        } else if urls.count == 1, let url = urls.first {
            SensitiveMediaOverlay(
                isSensitive: display.sensitiveBlur,
                showsRevealButton: false,
                onTapWhenVisible: {
                    guard !interactionLocked else { return }
                    actions.onOpen()
                }
            ) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(PostColor.mediaPlaceholder.opacity(0.35))
                    }
                }
                .processors([.resize(width: 512)])
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            let first = urls[0]
            let second = urls[1]
            let extra = urls.count - 2
            HStack(spacing: 4) {
                takeTile(url: first)
                ZStack(alignment: .bottomTrailing) {
                    takeTile(url: second)
                    if extra > 0 {
                        Text("+\(extra)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(8)
                    }
                }
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                guard !interactionLocked else { return }
                actions.onOpen()
            }
        }
    }

    private func takeTile(url: URL) -> some View {
        SensitiveMediaOverlay(
            isSensitive: display.sensitiveBlur,
            showsRevealButton: false
        ) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(PostColor.mediaPlaceholder.opacity(0.35))
                }
            }
            .processors([.resize(width: 320)])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Unavailable

    private var unavailableCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Post unavailable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("It may have been deleted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: cardWidth, alignment: .leading)
    }

    // MARK: - Shared

    private func creatorAvatar(size: CGFloat) -> some View {
        UserAvatarView(
            user: User(
                id: display.creatorID,
                username: display.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                displayName: display.displayName,
                bio: nil,
                avatarURL: display.avatarURL,
                suiWallet: nil,
                createdAt: nil
            ),
            size: size
        )
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

    private func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        var truncated = String(text[..<endIndex])
        if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            truncated = String(truncated[..<lastSpace])
        }
        let trimmed = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? String(text.prefix(limit)) : trimmed) + "…"
    }
}

/// Side forward button for shot shares (outside the bubble clip).
struct ChatShotForwardButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .directGlass(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Forward")
    }
}

extension ChatPostShareCard {
    /// Whether this share should draw the bubble drop-tail (take yes, shot no).
    static func showsTail(postType: String?, card: DMPostCard?, post: Post?, showTail: Bool) -> Bool {
        guard showTail else { return false }
        if let post { return post.postType != .shot }
        let type = (card?.postType ?? postType ?? "").lowercased()
        return type != "shot"
    }
}
