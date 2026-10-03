import SwiftUI

struct ProfileView: View {
    let session: AuthSession
    let container: DependencyContainer
    let onLogout: () -> Void
    var onOpenDraft: ((UUID) -> Void)?
    var onOpenShotDraft: ((UUID) -> Void)?
    @State private var profileFromSettings: UserProfile?

    var body: some View {
        NavigationStack {
            UserProfileView(
                userID: nil,
                session: session,
                container: container,
                onOpenDraft: onOpenDraft,
                onOpenShotDraft: onOpenShotDraft,
                externalProfileUpdate: $profileFromSettings
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(
                            session: session,
                            container: container,
                            onLogout: onLogout,
                            onOpenDraft: onOpenDraft,
                            onOpenShotDraft: onOpenShotDraft,
                            onProfileUpdated: { profileFromSettings = $0 }
                        )
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
}
