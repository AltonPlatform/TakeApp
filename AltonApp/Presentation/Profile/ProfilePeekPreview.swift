import SwiftUI
import UIKit
import NukeUI

/// Instagram-style long-press peek: hold to preview, release to dismiss.
struct ProfilePeekOverlay<Content: View>: View {
    let isPresented: Bool
    var onDismiss: () -> Void = {}
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(isPresented ? 0.55 : 0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.2), value: isPresented)
                .allowsHitTesting(isPresented)

            if isPresented {
                content()
                    .scaleEffect(1.0)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
                    .padding(.horizontal, 28)
                    .transition(
                        .scale(scale: 0.85)
                            .combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .allowsHitTesting(isPresented)
        .onTapGesture(perform: onDismiss)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isPresented)
    }
}

enum ProfilePeekActivation {
    /// 3D Touch / Instagram-style hold before peek appears.
    static let minimumPressDuration: TimeInterval = 0.5
    /// Finger movement beyond this fails the long-press (dismiss-on-drag / scroll wins).
    static let maximumDistance: CGFloat = 20
    /// Brief lock after release so the lift-off touch cannot open the post.
    static let suppressGraceNanoseconds: UInt64 = 300_000_000
}

/// Per-post lock during peek + short grace after release. Does not clear on activation checks.
@Observable
@MainActor
final class ProfilePeekSuppressController {
    private(set) var lockedPostID: String?
    private var generation = 0
    private var task: Task<Void, Never>?
    private let graceNanoseconds: UInt64

    init(graceNanoseconds: UInt64 = ProfilePeekActivation.suppressGraceNanoseconds) {
        self.graceNanoseconds = graceNanoseconds
    }

    func allowsActivation(for postID: String) -> Bool {
        lockedPostID != postID
    }

    func begin(lockID: String) {
        task?.cancel()
        task = nil
        generation &+= 1
        lockedPostID = lockID
    }

    /// Schedules unlock after grace. Idempotent while a grace task is already running for this lock.
    func end() {
        guard lockedPostID != nil else { return }
        guard task == nil else { return }
        let token = generation
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: graceNanoseconds)
            defer { if token == generation { task = nil } }
            guard !Task.isCancelled, token == generation else { return }
            lockedPostID = nil
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        generation &+= 1
        lockedPostID = nil
    }
}

struct ProfilePeekGestureModifier: ViewModifier {
    @Binding var isPeeking: Bool
    var onPeekBegan: () -> Void
    var onPeekEnded: () -> Void
    var minimumDuration: Double = ProfilePeekActivation.minimumPressDuration

    /// Release / fail / disappear can all fire — only the first should end the peek.
    private func finishPeek() {
        guard isPeeking else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPeeking = false
        }
        onPeekEnded()
    }

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(
                minimumDuration: minimumDuration,
                maximumDistance: ProfilePeekActivation.maximumDistance,
                pressing: { pressing in
                    // Touch-down: wait for `perform`. Lift / fail after peek: dismiss.
                    if !pressing {
                        finishPeek()
                    }
                },
                perform: {
                    guard !isPeeking else { return }
                    onPeekBegan()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isPeeking = true
                    }
                }
            )
            .onDisappear {
                finishPeek()
            }
    }
}

extension View {
    func profilePeekGesture(
        isPeeking: Binding<Bool>,
        onPeekBegan: @escaping () -> Void,
        onPeekEnded: @escaping () -> Void,
        minimumDuration: Double = ProfilePeekActivation.minimumPressDuration
    ) -> some View {
        modifier(ProfilePeekGestureModifier(
            isPeeking: isPeeking,
            onPeekBegan: onPeekBegan,
            onPeekEnded: onPeekEnded,
            minimumDuration: minimumDuration
        ))
    }
}

struct ProfileShotPeekCard: View {
    let post: Post

    private var isAgeRestricted: Bool {
        post.ageGated && !AgeGateConfirmationStore.shared.isConfirmed(post.id)
    }

    private var isSensitiveLocked: Bool {
        post.isSensitiveImage(at: 0) || post.sensitiveBlur
    }

    var body: some View {
        SensitiveMediaOverlay(
            isSensitive: isSensitiveLocked,
            isAgeRestricted: isAgeRestricted,
            showsRevealButton: false,
            managesRevealInternally: false,
            moderationReason: post.moderationReason,
            cornerRadius: 16
        ) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = post.playbackURL, !isAgeRestricted {
                        ShotPlayerView(
                            url: url,
                            isActive: true,
                            isMuted: isSensitiveLocked
                        )
                    } else if let url = post.thumbnailURL {
                        LazyImage(url: url) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        .processors([.resize(width: 720)])
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                if let content = post.content, !content.isEmpty {
                    Text(content)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(16)
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

