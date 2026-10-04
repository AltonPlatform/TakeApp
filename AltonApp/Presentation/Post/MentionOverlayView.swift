import SwiftUI
import NukeUI

/// Candidate user for mention autocompletion.
typealias MentionCandidate = FollowUser

/// State model representing the mention overlay's candidate list and visibility.
struct MentionOverlayState: Equatable {
    var candidates: [MentionCandidate]

    init(candidates: [MentionCandidate] = []) {
        self.candidates = candidates
    }

    var isVisible: Bool { !candidates.isEmpty }
}

// MARK: - Color tokens (adaptive; matching ComposerBottomChrome)

private extension Color {
    /// Light `#1c1c1e` / dark `#f5f5f7`.
    static let overlayInk = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
            : UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
    })
    /// Light `#eaecf0` / dark `#2c2c2e`.
    static let overlayHairline = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
            : UIColor(red: 234 / 255, green: 236 / 255, blue: 240 / 255, alpha: 1)
    })
    /// Light `#a0a3ab` / dark `#8e8e93`.
    static let overlaySecondary = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
            : UIColor(red: 160 / 255, green: 163 / 255, blue: 171 / 255, alpha: 1)
    })
}

// MARK: - MentionOverlayView

/// Floating glass overlay displaying mention suggestions above the bottom chrome.
struct MentionOverlayView: View {
    let candidates: [MentionCandidate]
    var query: String = ""
    var onSelect: (MentionCandidate) -> Void

    private var contentHeight: CGFloat {
        let rows = min(candidates.count, 4)
        return CGFloat(rows) * 44
    }

    var body: some View {
        if candidates.isEmpty {
            EmptyView()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        row(for: candidate)

                        if candidate.id != candidates.last?.id {
                            Rectangle()
                                .fill(Color.overlayHairline)
                                .frame(height: 1)
                                .padding(.leading, 50)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.overlayHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        }
    }

    private func row(for candidate: MentionCandidate) -> some View {
        Button {
            onSelect(candidate)
        } label: {
            HStack(spacing: 10) {
                avatarView(for: candidate)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName.isEmpty ? candidate.username : candidate.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.overlayInk)
                        .lineLimit(1)

                    Text("@\(candidate.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.overlaySecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func avatarView(for candidate: MentionCandidate) -> some View {
        if let avatarURL = candidate.avatarURL {
            LazyImage(url: avatarURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    avatarPlaceholder(for: candidate)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            avatarPlaceholder(for: candidate)
        }
    }

    private func avatarPlaceholder(for candidate: MentionCandidate) -> some View {
        Circle()
            .fill(Color.overlayHairline)
            .frame(width: 28, height: 28)
            .overlay {
                let initial = String((candidate.displayName.isEmpty ? candidate.username : candidate.displayName).prefix(1)).uppercased()
                Text(initial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.overlaySecondary)
            }
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.2).ignoresSafeArea()

        MentionOverlayView(
            candidates: [
                FollowUser(id: "1", username: "alice", displayName: "Alice Wonderland", avatarURL: nil, isFollowing: false),
                FollowUser(id: "2", username: "albert", displayName: "Albert Einstein", avatarURL: nil, isFollowing: true),
                FollowUser(id: "3", username: "alex", displayName: "Alex", avatarURL: nil, isFollowing: false),
                FollowUser(id: "4", username: "alicia", displayName: "Alicia Keys", avatarURL: nil, isFollowing: false),
                FollowUser(id: "5", username: "alton", displayName: "Alton Official", avatarURL: nil, isFollowing: true),
            ],
            query: "al",
            onSelect: { _ in }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 56)
    }
}
