import SwiftUI

/// Primary display name with optional `@username` when the name is a real display name.
struct UserHandleLabel: View {
    let displayName: String
    let atUsername: String?
    var font: Font = .subheadline.weight(.semibold)
    var secondaryFont: Font = .caption
    var showUsernameWhenDifferent: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Text(displayName)
                .font(font)
                .lineLimit(1)
            if showUsernameWhenDifferent,
               let atUsername,
               !atUsername.isEmpty,
               atUsername != displayName,
               !displayName.hasPrefix("@") {
                Text(atUsername)
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    static func forPost(_ post: Post, currentUser: User?) -> UserHandleLabel {
        let display = post.resolvedCreatorDisplayName(currentUser: currentUser)
        let at = post.resolvedAtUsername(currentUser: currentUser)
        return UserHandleLabel(displayName: display, atUsername: at)
    }

    static func forComment(
        displayName: String?,
        username: String?,
        fallbackID: String
    ) -> UserHandleLabel {
        let resolvedDisplay: String
        if let displayName, !displayName.isEmpty {
            resolvedDisplay = displayName
        } else if let username, !username.isEmpty {
            resolvedDisplay = "@\(username)"
        } else {
            resolvedDisplay = fallbackID
        }
        let at: String? = {
            guard let username, !username.isEmpty else { return nil }
            return "@\(username)"
        }()
        return UserHandleLabel(displayName: resolvedDisplay, atUsername: at)
    }
}
