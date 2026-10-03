import NukeUI
import SwiftUI

struct ActivityRow: View {
    let item: NotificationItem
    var onFollowBack: (() -> Void)?
    var onAppeal: (() -> Void)?
    var onAppear: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if item.isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 18)
            } else {
                Color.clear.frame(width: 8, height: 8)
            }

            ZStack(alignment: .bottomTrailing) {
                UserAvatarView(
                    user: User(
                        id: item.actorID ?? "",
                        username: item.actorUsername ?? "",
                        displayName: item.actorResolvedName,
                        bio: nil,
                        avatarURL: item.actorAvatarURL,
                        suiWallet: nil,
                        createdAt: nil
                    ),
                    size: 44
                )

                Image(systemName: item.type.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(badgeColor, in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.actorResolvedName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let createdAt = item.createdAt {
                        Text(PostRelativeTimestamp.string(from: createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                Text(item.actionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let preview = previewText {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                if item.type == .follow || item.type == .profileView {
                    if onFollowBack != nil {
                        Button("Follow back", action: { onFollowBack?() })
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                    }
                }

                if item.type == .commentRemoved {
                    if let reason = item.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    if item.canAppeal, onAppeal != nil {
                        Button("Appeal", action: { onAppeal?() })
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                }
            }

            if let thumbnailURL = item.postThumbnailURL {
                LazyImage(url: thumbnailURL) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color(.tertiarySystemFill)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onAppear { onAppear?() }
    }

    private var previewText: String? {
        if let comment = item.commentPreview, !comment.isEmpty { return comment }
        if let parent = item.parentCommentContent, !parent.isEmpty { return parent }
        if let post = item.postPreview, !post.isEmpty { return post }
        return nil
    }

    private var badgeColor: Color {
        switch item.type {
        case .like: return .pink
        case .comment, .reply: return .blue
        case .commentRemoved: return .red
        case .follow, .profileView: return .purple
        case .repost: return .green
        case .mention: return .orange
        }
    }

}
