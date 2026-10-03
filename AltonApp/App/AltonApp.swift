import SwiftUI
import GoogleSignIn

@main
struct AltonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
                .task {
                    PipelineLogger.media.debug(
                        "app launch api=\(AppEnvironment.current.apiBaseURL.absoluteString, privacy: .public) media=\(AppEnvironment.current.mediaBaseURL.absoluteString, privacy: .public)"
                    )
                    CASManager.shared.initialize()
                    await container.configureAuth()
                    PushRegistrationCenter.configure(apiClient: container.apiClient)
                    PushRegistrationCenter.onDeepLink = { url in
                        Task { await container.sessionStore.handleIncomingURL(url) }
                    }
                    await container.sessionStore.restoreSession()
                    if container.sessionStore.session != nil {
                        PushRegistrationCenter.reRegisterIfNeeded()
                    }
                    container.draftStore.purgeStaleOnLaunch()
                    _ = await ATTConsentManager.shared.requestTrackingAuthorization()
                    await AppSessionTracker.shared.startSession()
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task {
                        await container.sessionStore.handleUniversalLink(url)
                    }
                }
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    Task {
                        await container.sessionStore.handleIncomingURL(url)
                    }
                }
        }
    }
}
