import SwiftUI
import NukeUI

struct UserAvatarView: View {
    let user: User
    var size: CGFloat = 44
    /// When true, shows a green online dot (requires `presenceStore`).
    var showOnlineIndicator: Bool = false
    var presenceStore: PresenceStore? = nil

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
        .overlay(alignment: .bottomTrailing) {
            if showOnlineIndicator, presenceStore?.isOnline(user.id) == true {
                Circle()
                    .fill(Color.green)
                    .frame(width: max(8, size * 0.28), height: max(8, size * 0.28))
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 1, y: 1)
                    .accessibilityLabel("Online")
            }
        }
        .onAppear {
            if showOnlineIndicator {
                presenceStore?.track(user.id)
            }
        }
        .onChange(of: user.id) { _, newID in
            if showOnlineIndicator {
                presenceStore?.track(newID)
            }
        }
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
