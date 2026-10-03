import SwiftUI
import NukeUI

struct UserAvatarView: View {
    let user: User
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let avatarURL = user.avatarURL {
                LazyImage(url: avatarURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                }
                .processors([.resize(width: size * UIScreen.main.scale)])
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(.blue.gradient)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        let source = user.displayName.isEmpty ? user.username : user.displayName
        return String(source.prefix(1)).uppercased()
    }
}
