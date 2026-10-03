import SwiftUI

struct ContentView: View {
    let container: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastForegroundRefresh: Date?

    var body: some View {
        Group {
            if container.sessionStore.isRestoringSession {
                SessionRestoringView()
            } else if let currentSession = container.sessionStore.session {
                MainTabView(container: container, session: currentSession) {
                    Task {
                        await PushRegistrationCenter.unregisterOnLogout()
                        try? await container.authUseCase.logout()
                        container.sessionStore.session = nil
                    }
                }
            } else {
                NavigationStack {
                    WelcomeView(
                        viewModel: container.makeAuthViewModel { session in
                            container.sessionStore.session = session
                        }
                    )
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let now = Date()
            if let lastForegroundRefresh,
               now.timeIntervalSince(lastForegroundRefresh) < 30 {
                return
            }
            lastForegroundRefresh = now
            Task {
                await container.sessionStore.refreshIfNeeded()
                if container.sessionStore.session != nil {
                    if AppSessionTracker.shared.sessionID == nil {
                        await AppSessionTracker.shared.startSession()
                    }
                    await AppSessionTracker.shared.recordActivity("foreground")
                }
            }
        }
    }
}

private struct SessionRestoringView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Restoring session…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
