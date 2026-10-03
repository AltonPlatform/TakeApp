import SwiftUI

struct PostContextMenuButton: View {
    let post: Post
    var iconColor: Color = .secondary
    var shotFeedStyle: Bool = false
    var feedStyle: Bool = false
    var onBookmark: () -> Void
    var onRepost: () -> Void
    var onInsights: (() -> Void)? = nil
    var onActivity: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onCopy: (() -> Void)?

    var body: some View {
        Menu {
            if let onInsights {
                Button(action: onInsights) {
                    Label("View insights", systemImage: "chart.xyaxis.line")
                }
            }

            if let onActivity {
                Button(action: onActivity) {
                    Label("Post activity", systemImage: "chart.bar")
                }
            }

            if let onCopy, post.allowsCopyingContent, let content = post.content {
                Button {
                    UIPasteboard.general.string = content
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            Button(action: onBookmark) {
                Label(
                    post.isBookmarked ? "Remove from saved" : "Save",
                    systemImage: post.isBookmarked ? "bookmark.fill" : "bookmark"
                )
            }

            Button(action: onRepost) {
                Label(
                    post.isReposted ? "Undo repost" : "Repost",
                    systemImage: "arrow.2.squarepath"
                )
            }

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }

            if let onReport, post.canReport {
                Button(role: .destructive, action: onReport) {
                    Label("Report", systemImage: "flag")
                }
            }
        } label: {
            Group {
                if feedStyle {
                    Image("post.more")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } else if shotFeedStyle {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 22, weight: .bold))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(feedStyle ? PostColor.labelSecondary : iconColor)
            .frame(width: shotFeedStyle ? 48 : 32, height: shotFeedStyle ? 48 : 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
