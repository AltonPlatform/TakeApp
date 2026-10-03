import SwiftUI
import NukeUI

/// Nested original post card from Figma `Reply` (radius 16, optional bottom media).
struct PostReplyEmbedCard: View {
    let preview: ParentPostPreview
    var currentUser: User?
    var onTap: (() -> Void)? = nil

    var body: some View {
        AgeRestrictedMediaGate(isAgeGated: preview.ageGated, contentID: preview.id) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    UserAvatarView(
                        user: User(
                            id: preview.creatorID,
                            username: preview.creatorUsername ?? "",
                            displayName: preview.creatorDisplayName
                                ?? preview.creatorUsername
                                ?? preview.creatorID,
                            bio: nil,
                            avatarURL: preview.creatorAvatarURL,
                            suiWallet: nil,
                            createdAt: nil
                        ),
                        size: 24
                    )

                    Text(displayName)
                        .font(PostTypography.semiBold(14, relativeTo: .subheadline))
                        .foregroundStyle(PostColors.labelPrimary)
                        .lineLimit(1)

                    if let handle = atUsername {
                        Text(handle)
                            .font(PostTypography.handle)
                            .foregroundStyle(PostColors.labelSecondary)
                            .lineLimit(1)
                    }

                    if let createdAt = preview.createdAt {
                        Text(PostRelativeTimestamp.string(from: createdAt))
                            .font(PostTypography.handle)
                            .foregroundStyle(PostColors.labelSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, preview.content == nil && preview.thumbnailURL == nil ? 8 : 0)
                .contentShape(Rectangle())
                .onTapGesture { onTap?() }

                if let content = preview.content, !content.isEmpty {
                    Text(content)
                        .font(PostTypography.body)
                        .foregroundStyle(PostColors.labelPrimary)
                        .lineSpacing(14 * 0.4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?() }
                }

                if let thumbnailURL = preview.thumbnailURL {
                    LazyImage(url: thumbnailURL) { state in
                        if let image = state.image {
                            let pixel = state.imageContainer?.image.size
                            let aspect = (pixel?.height ?? 0) > 0 ? pixel!.width / pixel!.height : nil
                            SensitiveMediaOverlay(
                                isSensitive: preview.sensitiveBlur,
                                onTapWhenVisible: { onTap?() }
                            ) {
                                image
                                    .resizable()
                                    .scaledToFill()
                            }
                            .aspectRatio(aspect, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 200)
                        }
                    }
                    .processors([.resize(width: 512)])
                    .frame(maxWidth: .infinity, maxHeight: 200)
                }
            }
        }
        .id(preview.id)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PostColors.border, lineWidth: 1)
        }
    }

    private var displayName: String {
        if let name = preview.creatorDisplayName, !name.isEmpty { return name }
        if let username = preview.creatorUsername, !username.isEmpty { return username }
        return preview.creatorID
    }

    private var atUsername: String? {
        guard let username = preview.creatorUsername, !username.isEmpty else { return nil }
        return username.hasPrefix("@") ? username : "@\(username)"
    }
}
