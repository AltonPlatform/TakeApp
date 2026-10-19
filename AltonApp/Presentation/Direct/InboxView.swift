import SwiftUI
import UIKit

/// Remembers the inbox size without publishing it back into SwiftUI.
private final class InboxChromeMetrics {
    var width: CGFloat = 0
    var height: CGFloat = 0
}

struct InboxView: View {
    @Bindable var viewModel: InboxHomeViewModel
    let container: DependencyContainer
    let session: AuthSession
    var isTabSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCompose = false
    @State private var showNewGroup = false
    @State private var showRequests = false
    @State private var didStart = false
    @State private var searchText = ""

    @State private var openConversation: DMConversation?
    @State private var tabBarCovered = false
    @State private var chatProgress: CGFloat = 0
    @State private var isChatSettled = false
    @State private var isEdgeDragging = false
    @State private var chrome = InboxChromeMetrics()
    @State private var motionSource = ChatMotionSource()
    @State private var plateImages: ChatPlateImages?

    private var filteredConversations: [DMConversation] {
        guard viewModel.inbox.ownerUserID == session.user.id else { return [] }
        let all = viewModel.inbox.conversations
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { conversation in
            conversation.displayTitle.localizedCaseInsensitiveContains(query)
                || conversation.peerUsername.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let screen = UIScreen.main.bounds
        let inboxPresented = (plateImages != nil && !reduceMotion)
            ? ChatDissolveMotion.presentedAmount(chatProgress)
            : chatProgress
        let plateSlide = (plateImages != nil && !reduceMotion)
            ? (1 - inboxPresented) * screen.width
            : 0
        let pinList = openConversation != nil && chrome.height > 1
        listStack
            .allowsHitTesting(openConversation == nil)
            .accessibilityHidden(openConversation != nil)
            // While a chat is open the tab bar hides and this container grows downward.
            // Keep the list at the height and top edge it had, so the inbox does not jump.
            .frame(
                maxWidth: .infinity,
                maxHeight: pinList ? chrome.height : .infinity,
                alignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                // Stored on a class so this write does not invalidate layout.
                // Writing @State here makes SwiftUI report a geometry cycle.
                guard openConversation == nil else { return }
                if size.width > 1, abs(size.width - chrome.width) > 1 {
                    chrome.width = size.width
                }
                if size.height > 1, abs(size.height - chrome.height) > 1 {
                    chrome.height = size.height
                }
            }
            .overlay {
                if let conversation = openConversation {
                    chatCover(
                        conversation,
                        screen: screen,
                        plateSlide: plateSlide
                    )
                    .frame(width: screen.width, height: screen.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                }
            }
            .toolbar(tabBarCovered ? .hidden : .visible, for: .tabBar)
    }

    private func chatCover(
        _ conversation: DMConversation,
        screen: CGRect,
        plateSlide: CGFloat
    ) -> some View {
        let plateVisible = plateImages != nil
        return ZStack {
            DirectChatHost(
                conversation: conversation,
                container: container,
                session: session,
                edgeBackEnabled: isChatSettled || isEdgeDragging,
                liveEnabled: isChatSettled,
                motionSource: motionSource,
                onClose: { closeChat() },
                onEdgeBegan: { view in
                    beginSwipePlate(from: view)
                },
                onEdgeChanged: { swipeProgress in
                    isEdgeDragging = true
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        chatProgress = 1 - swipeProgress
                    }
                },
                onEdgeEnded: { swipeProgress, velocityX in
                    isEdgeDragging = false
                    finishEdgeSwipe(progress: swipeProgress, velocityX: velocityX)
                }
            )
            .frame(width: screen.width, height: screen.height)
            .background(ChatScreenBackground())
            .chatLayerTransition(
                progress: plateVisible ? 1 : chatProgress,
                width: screen.width,
                reduceMotion: reduceMotion
            )
            .opacity(plateVisible ? 0 : 1)
            .offset(x: plateVisible ? plateSlide : 0)
            .allowsHitTesting(isChatSettled || isEdgeDragging)

            ChatSwipePlate(
                images: plateImages ?? ChatPlateImages.empty,
                progress: plateVisible ? chatProgress : 1,
                width: screen.width,
                animatesChanges: !isEdgeDragging
            )
            .frame(width: screen.width, height: screen.height)
            .background(Color.clear)
            .offset(x: plateSlide)
            .opacity(plateVisible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            ChatSeamChevron(
                progress: chatProgress,
                width: screen.width,
                height: screen.height,
                reduceMotion: reduceMotion
            )
            .frame(width: screen.width, height: screen.height)
            .allowsHitTesting(false)
        }
    }

    private var listStack: some View {
        NavigationStack {
            List {
                Section {
                    categoryChips
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    if viewModel.inbox.isLoading && viewModel.inbox.conversations.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else if filteredConversations.isEmpty {
                        emptyState
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredConversations) { conversation in
                            Button {
                                openChat(conversation)
                            } label: {
                                InboxRow(
                                    conversation: conversation,
                                    presenceStore: container.presenceStore
                                )
                            }
                            .buttonStyle(InboxRowButtonStyle())
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        if viewModel.inbox.nextCursor != nil, searchText.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .task { await viewModel.inbox.loadMore() }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New message", systemImage: "square.and.pencil") {
                            showCompose = true
                        }
                        Button("New group", systemImage: "person.3") {
                            showNewGroup = true
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                            .directGlass(Circle(), interactive: true)
                    }
                    .accessibilityLabel("Compose")
                }
            }
            .sheet(isPresented: $showCompose) {
                NewMessageView(
                    viewModel: container.makeNewMessageViewModel(currentUserID: session.user.id),
                    onOpened: { conversation in
                        openChat(conversation)
                    }
                )
            }
            .sheet(isPresented: $showNewGroup) {
                NewGroupView(
                    viewModel: NewGroupViewModel(
                        currentUserID: session.user.id,
                        userUseCase: container.userUseCase,
                        directUseCase: container.directUseCase
                    ),
                    onCreated: { conversation in
                        openChat(conversation)
                    }
                )
            }
            .sheet(isPresented: $showRequests, onDismiss: {
                Task { await viewModel.refreshSummaries() }
            }) {
                RequestsView(
                    viewModel: {
                        let vm = InboxViewModel(
                            useCase: container.directUseCase,
                            realtime: container.realtimeClient,
                            repository: container.directRepository
                        )
                        vm.folder = "requests"
                        vm.ownerUserID = session.user.id
                        return vm
                    }(),
                    container: container
                )
            }
            .onAppear {
                viewModel.inbox.adopt(userID: session.user.id)
                guard !didStart else { return }
                didStart = true
                viewModel.start()
            }
            .onChange(of: session.user.id) { _, userID in
                viewModel.inbox.adopt(userID: userID)
                didStart = true
                viewModel.start()
            }
            .onChange(of: isTabSelected) { _, selected in
                if !selected {
                    Self.setTabBarCovered(false)
                } else if openConversation != nil {
                    Self.setTabBarCovered(true)
                    tabBarCovered = true
                }
            }
            .onDisappear {
                if Self.lockedTabBottomInset != nil {
                    Self.setTabBarCovered(false)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                InboxCategoryChip(
                    title: NotificationCategory.followers.shortTitle,
                    systemImage: NotificationCategory.followers.systemImage,
                    unreadCount: viewModel.followersSummary.unreadCount
                ) {
                    presentCategoryPanel(.followers)
                }
                InboxCategoryChip(
                    title: NotificationCategory.activity.shortTitle,
                    systemImage: NotificationCategory.activity.systemImage,
                    unreadCount: viewModel.activitySummary.unreadCount
                ) {
                    presentCategoryPanel(.activity)
                }
                InboxCategoryChip(
                    title: NotificationCategory.system.shortTitle,
                    systemImage: NotificationCategory.system.systemImage,
                    unreadCount: viewModel.systemSummary.unreadCount
                ) {
                    presentCategoryPanel(.system)
                }
                if viewModel.requestsSummary.hasContent {
                    InboxCategoryChip(
                        title: "Requests",
                        systemImage: "envelope.badge.fill",
                        unreadCount: viewModel.requestsSummary.unreadCount
                    ) {
                        showRequests = true
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Start a conversation")
                .font(.title3.weight(.semibold))
            Text(
                searchText.isEmpty
                    ? "Message people you follow or find someone new."
                    : "No chats match “\(searchText)”."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            if searchText.isEmpty {
                Button {
                    showCompose = true
                } label: {
                    Text("New message")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .directGlass(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func presentCategoryPanel(_ category: NotificationCategory) {
        let home = viewModel
        GrokPanelPresenter.present(onDismiss: {
            Task { await home.refreshSummaries() }
        }) {
            NavigationStack {
                ActivityView(
                    viewModel: container.makeActivityViewModel(category: category),
                    session: session,
                    container: container
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            GrokPanelPresenter.dismiss()
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
        }
    }

    private func openChat(_ conversation: DMConversation) {
        guard openConversation == nil else { return }
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        UIView.setAnimationsEnabled(false)
        let openAnimation = ChatDissolveMotion.open(reduceMotion: reduceMotion)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            openConversation = conversation
            chatProgress = 0
            isChatSettled = false
            plateImages = nil
        }
        DispatchQueue.main.async {
            UIView.setAnimationsEnabled(false)
            Self.setTabBarCovered(true)
            Self.reassertCoveredTabBarInsets()
            var cover = Transaction()
            cover.disablesAnimations = true
            withTransaction(cover) {
                tabBarCovered = true
            }
            UIView.setAnimationsEnabled(true)
            withAnimation(openAnimation) {
                chatProgress = 1
            } completion: {
                isChatSettled = true
                playSettleHaptic()
            }
        }
    }

    /// Hides the tab bar without letting the inbox safe area change size.
    private static var lockedTabBottomInset: CGFloat?

    private static func setTabBarCovered(_ covered: Bool) {
        guard let tab = tabBarController() else { return }
        UIView.performWithoutAnimation {
            if covered {
                let before = tab.view.safeAreaInsets.bottom
                lockedTabBottomInset = before
                tab.setTabBarHidden(true, animated: false)
                tab.view.layoutIfNeeded()
                let after = tab.view.safeAreaInsets.bottom
                tab.additionalSafeAreaInsets.bottom = max(0, before - after)
                tab.view.layoutIfNeeded()
            } else {
                lockedTabBottomInset = nil
                tab.additionalSafeAreaInsets.bottom = 0
                tab.setTabBarHidden(false, animated: false)
                tab.view.layoutIfNeeded()
            }
        }
    }

    /// SwiftUI's toolbar hide can clear the inset on the next turn. Put it back
    /// before the chat slide starts, while animations are still off.
    private static func reassertCoveredTabBarInsets() {
        guard let locked = lockedTabBottomInset, let tab = tabBarController() else { return }
        UIView.performWithoutAnimation {
            let delta = locked - tab.view.safeAreaInsets.bottom
            guard abs(delta) > 0.5 else { return }
            tab.additionalSafeAreaInsets.bottom += delta
            tab.view.layoutIfNeeded()
        }
    }

    private static func tabBarController() -> UITabBarController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let root = (scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first)?.rootViewController
        return findTabBarController(root)
    }

    private static func findTabBarController(_ controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tab = controller as? UITabBarController { return tab }
        for child in controller.children {
            if let found = findTabBarController(child) { return found }
        }
        return findTabBarController(controller.presentedViewController)
    }

    private func closeChat(releaseVelocity: CGFloat = 0) {
        guard openConversation != nil else { return }
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        if plateImages == nil, let view = motionSource.view {
            beginSwipePlate(from: view)
        }
        isChatSettled = false
        // The gesture callback sits in a disabled transaction, so animating here snaps
        // and the completion removes the plate in the same frame. The inbox then pops.
        let animation = ChatDissolveMotion.release(
            initialVelocity: releaseVelocity,
            reduceMotion: reduceMotion
        )
        DispatchQueue.main.async {
            withAnimation(animation) {
                chatProgress = 0
            } completion: {
                UIView.setAnimationsEnabled(false)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    clearPlate()
                    openConversation = nil
                    tabBarCovered = false
                }
                Self.setTabBarCovered(false)
                DispatchQueue.main.async {
                    UIView.setAnimationsEnabled(true)
                }
                playSettleHaptic()
                Task { await viewModel.refresh() }
            }
        }
    }

    private func finishEdgeSwipe(progress: CGFloat, velocityX: CGFloat) {
        let width = max(chrome.width, UIScreen.main.bounds.width, 1)
        let rawVelocity = -velocityX / width
        let shouldClose = progress > ChatDissolveMotion.edgeCloseProgressThreshold
            || velocityX > ChatDissolveMotion.edgeCloseVelocityThreshold
        if shouldClose {
            closeChat(releaseVelocity: min(0, rawVelocity))
        } else {
            // Same disabled transaction as the close path. Animate on the next turn
            // so the plate offset and the inbox move back together.
            isChatSettled = false
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: ChatDissolveMotion.cancelDuration)) {
                    chatProgress = 1
                } completion: {
                    guard !isEdgeDragging, chatProgress == 1 else { return }
                    clearPlate()
                    isChatSettled = true
                    playSettleHaptic()
                }
            }
        }
    }

    private func playSettleHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Snapshot once, then the finger only moves that image. Skip when Reduce Motion is on.
    private func beginSwipePlate(from view: UIView) {
        guard !reduceMotion, plateImages == nil else { return }
        guard let images = ChatPlateImage.make(from: view) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            plateImages = images
        }
    }

    private func clearPlate() {
        guard plateImages != nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            plateImages = nil
        }
    }
}

struct InboxCategoryChip: View {
    let title: String
    let systemImage: String
    let unreadCount: Int
    var action: () -> Void

    private var hasUnread: Bool { unreadCount > 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if hasUnread {
                    Text("\(unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary))
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(.secondarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasUnread ? "\(title), \(unreadCount) unread" : title)
    }
}

struct InboxRow: View {
    let conversation: DMConversation
    var presenceStore: PresenceStore?

    private var relativeTime: String? {
        guard let date = APIDateParser.parse(conversation.updatedAt) else { return nil }
        return PostRelativeTimestamp.string(from: date)
    }

    private func inboxPreview(for conversation: DMConversation) -> String {
        switch conversation.previewKind {
        case "image": return conversation.previewText.isEmpty ? "Photo" : conversation.previewText
        case "gif": return conversation.previewText.isEmpty ? "GIF" : conversation.previewText
        case "post_share": return conversation.previewText.isEmpty ? "Shared a post" : conversation.previewText
        case "location": return conversation.previewText.isEmpty ? "Location" : conversation.previewText
        case "checklist": return conversation.previewText.isEmpty ? "Checklist" : conversation.previewText
        case "poll": return conversation.previewText.isEmpty ? "Poll" : conversation.previewText
        default:
            return conversation.previewText.isEmpty ? " " : conversation.previewText
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            UserAvatarView(
                user: User(
                    id: conversation.isGroup ? conversation.id : conversation.peerUserID,
                    username: conversation.isGroup ? "" : conversation.peerUsername,
                    displayName: conversation.displayTitle,
                    bio: nil,
                    avatarURL: conversation.isGroup ? conversation.groupAvatarURL : conversation.peerAvatarURL,
                    suiWallet: nil,
                    createdAt: nil
                ),
                size: 52,
                showOnlineIndicator: !conversation.isGroup,
                presenceStore: presenceStore
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(conversation.displayTitle)
                        .font(.body.weight(conversation.unreadCount > 0 ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if conversation.isGroup {
                        Text("\(conversation.memberCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let relativeTime {
                        Text(relativeTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    Text(inboxPreview(for: conversation))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct InboxRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
