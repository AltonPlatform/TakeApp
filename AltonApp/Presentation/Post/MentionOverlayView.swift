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

// MARK: - MentionOverlayView

/// Floating glass overlay displaying mention suggestions above the bottom chrome.
struct MentionOverlayView: View {
    static let rowHeight: CGFloat = 44
    static let maxVisibleRows: Int = 4

    static func overlayHeight(candidateCount: Int) -> CGFloat {
        guard candidateCount > 0 else { return 0 }
        let rows = min(candidateCount, maxVisibleRows)
        return CGFloat(rows) * rowHeight
    }

    let candidates: [MentionCandidate]
    var query: String = ""
    var onSelect: (MentionCandidate) -> Void

    private var contentHeight: CGFloat {
        Self.overlayHeight(candidateCount: candidates.count)
    }

    var body: some View {
        if candidates.isEmpty {
            EmptyView()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        row(for: candidate, isLast: candidate.id == candidates.last?.id)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ComposerPalette.monochrome.divider, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        }
    }

    private func row(for candidate: MentionCandidate, isLast: Bool) -> some View {
        Button {
            onSelect(candidate)
        } label: {
            HStack(spacing: 10) {
                avatarView(for: candidate)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName.isEmpty ? candidate.username : candidate.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ComposerPalette.monochrome.primary)
                        .lineLimit(1)

                    Text("@\(candidate.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(ComposerPalette.monochrome.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(ComposerPalette.monochrome.divider)
                        .frame(height: 1)
                        .padding(.leading, 50)
                }
            }
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
            .processors([.resize(width: 28 * UIScreen.main.scale)])
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            avatarPlaceholder(for: candidate)
        }
    }

    private func avatarPlaceholder(for candidate: MentionCandidate) -> some View {
        Circle()
            .fill(ComposerPalette.monochrome.divider)
            .frame(width: 28, height: 28)
            .overlay {
                let initial = String((candidate.displayName.isEmpty ? candidate.username : candidate.displayName).prefix(1)).uppercased()
                Text(initial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ComposerPalette.monochrome.secondary)
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
