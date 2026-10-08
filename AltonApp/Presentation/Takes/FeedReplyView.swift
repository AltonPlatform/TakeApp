import SwiftUI
import NukeUI

struct FeedReplyView: View {
    let item: FeedReplyItem
    let currentUser: User?
    var container: DependencyContainer?
    var session: AuthSession?
    @Bindable var engagementController: PostEngagementController
    let onReply: (Post) -> Void
    var onOpenMentionProfile: (String) -> Void = { _ in }
    var onOpenParent: ((Post) -> Void)? = nil

    @State private var mentionProfileUserID: String?
    @State private var showShareSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            UserAvatarView(
                user: item.comment.authorAsUser(currentUser: currentUser),
                size: 32
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.comment.resolvedDisplayName)
                        .font(PostFont.name)
                        .foregroundStyle(PostColor.labelPrimary)
                        .lineLimit(1)
                    if let username = item.comment.authorUsername, !username.isEmpty {
                        Text("@\(username)")
                            .font(PostFont.handle)
                            .foregroundStyle(PostColor.handle)
                            .lineLimit(1)
                    }
                    if let createdAt = item.comment.createdAt {
                        Text(PostRelativeTimestamp.string(from: createdAt))
                            .font(PostFont.handle)
                            .foregroundStyle(PostColor.handle)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                if !item.comment.content.isEmpty {
                    TakeMarkdownContent(
                        content: item.comment.content,
                        onContentTap: { onReply(parentPost) },
                        onMentionTap: openMentionProfile
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let sticker = item.comment.sticker {
                    CommentStickerImageView(sticker: sticker)
                }

                if let gif = item.comment.gif {
                    CommentGifImageView(gif: gif)
                }

                if !item.comment.imageURLs.isEmpty {
                    PostMediaStripView(urls: item.comment.imageURLs)
                }

                PostReplyEmbedCard(preview: item.parentPost) {
                    if let onOpenParent {
                        onOpenParent(parentPost)
                    } else {
                        onReply(parentPost)
                    }
                }

                PostActionBar(
                    post: parentPost,
                    layout: .horizontal,
                    feedStyle: true,
                    onLike: {
                        Task {
                            _ = await engagementController.toggleLike(for: parentPost)
                        }
                    },
                    onComment: { onReply(parentPost) },
                    onRepost: {
                        Task { _ = await engagementController.toggleRepost(for: parentPost) }
                    },
                    onShare: {
                        Task {
                            if await engagementController.prepareShare(postID: parentPost.id) {
                                showShareSheet = true
                            }
                        }
                    },
                    onBookmark: {
                        Task { _ = await engagementController.toggleBookmark(for: parentPost) }
                    }
                )
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .sheet(isPresented: $showShareSheet) {
            if let payload = engagementController.makeSharePayload(for: parentPost) {
                ActivityShareSheet(payload: payload) { completed, channel in
                    showShareSheet = false
                    if completed, let channel {
                        Task {
                            _ = await engagementController.completeShare(
                                post: parentPost,
                                channel: channel
                            )
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var parentPost: Post {
        Post(
            id: item.parentPost.id,
            creatorID: item.parentPost.creatorID,
            creatorUsername: item.parentPost.creatorUsername,
            creatorDisplayName: item.parentPost.creatorDisplayName,
            creatorAvatarURL: item.parentPost.creatorAvatarURL,
            postType: .take,
            status: .published,
            content: item.parentPost.content,
            mediaKey: nil,
            thumbnailKey: nil,
            playbackURL: nil,
            thumbnailURL: item.parentPost.thumbnailURL,
            imageURLs: item.parentPost.thumbnailURL.map { [$0] } ?? [],
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            saveCount: 0,
            shareCount: 0,
            repostCount: 0,
            isLiked: false,
            isBookmarked: false,
            isReposted: false,
            createdAt: item.parentPost.createdAt,
            sensitiveBlur: item.parentPost.sensitiveBlur,
            ageGated: item.parentPost.ageGated
        )
    }

    private func openMentionProfile(_ username: String) {
        guard let container else { return }
        Task {
            if let userID = await MentionNavigation.resolveUserID(
                username: username,
                searchUseCase: container.searchUseCase
            ) {
                mentionProfileUserID = userID
                onOpenMentionProfile(userID)
            } else {
                container.appState.showToast("User @\(username) not found")
            }
        }
    }

}
