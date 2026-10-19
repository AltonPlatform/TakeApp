import SwiftUI

/// Owns a NavigationStack for chat so toolbar / nested destinations keep working
/// while the parent inbox drives dissolve open/close.
struct DirectChatHost: View {
    let conversation: DMConversation
    let container: DependencyContainer
    let session: AuthSession
    var edgeBackEnabled: Bool
    var liveEnabled: Bool
    var motionSource: ChatMotionSource
    var onClose: () -> Void
    var onEdgeBegan: (UIView) -> Void
    var onEdgeChanged: (CGFloat) -> Void
    var onEdgeEnded: (_ progress: CGFloat, _ velocityX: CGFloat) -> Void

    @State private var backSwipeLocked = false
    @State private var viewModel: ChatViewModel

    init(
        conversation: DMConversation,
        container: DependencyContainer,
        session: AuthSession,
        edgeBackEnabled: Bool,
        liveEnabled: Bool,
        motionSource: ChatMotionSource,
        onClose: @escaping () -> Void,
        onEdgeBegan: @escaping (UIView) -> Void,
        onEdgeChanged: @escaping (CGFloat) -> Void,
        onEdgeEnded: @escaping (_ progress: CGFloat, _ velocityX: CGFloat) -> Void
    ) {
        self.conversation = conversation
        self.container = container
        self.session = session
        self.edgeBackEnabled = edgeBackEnabled
        self.liveEnabled = liveEnabled
        self.motionSource = motionSource
        self.onClose = onClose
        self.onEdgeBegan = onEdgeBegan
        self.onEdgeChanged = onEdgeChanged
        self.onEdgeEnded = onEdgeEnded
        _viewModel = State(initialValue: ChatViewModel(
            conversation: conversation,
            useCase: container.directUseCase,
            realtime: container.realtimeClient,
            repository: container.directRepository,
            currentUserID: session.user.id,
            postUseCase: container.postUseCase
        ))
    }

    var body: some View {
        NavigationStack {
            ChatView(
                viewModel: viewModel,
                shareDeps: DirectShareDependencies(
                    directUseCase: container.directUseCase,
                    userUseCase: container.userUseCase,
                    searchUseCase: container.searchUseCase,
                    currentUserID: session.user.id
                ),
                container: container,
                session: session,
                liveEnabled: liveEnabled,
                onClose: onClose
            )
            .onPreferenceChange(ChatBackSwipeLockedKey.self) { locked in
                backSwipeLocked = locked
            }
        }
        .gesture(
            InboxEdgeBackGesture(
                isEnabled: edgeBackEnabled && !backSwipeLocked,
                source: motionSource,
                onBegan: onEdgeBegan,
                onChanged: onEdgeChanged,
                onEnded: onEdgeEnded
            )
        )
    }
}

extension DirectChatHost: Equatable {
    /// Finger ticks only change overlay progress. Skip rebuilding the live chat while it is hidden.
    static func == (lhs: DirectChatHost, rhs: DirectChatHost) -> Bool {
        lhs.conversation.id == rhs.conversation.id
            && lhs.edgeBackEnabled == rhs.edgeBackEnabled
            && lhs.liveEnabled == rhs.liveEnabled
            && lhs.session.user.id == rhs.session.user.id
    }
}
