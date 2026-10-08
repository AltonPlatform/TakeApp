import SwiftUI

struct WelcomeView: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: 28) {
                    header
                    providerSection
                    footerNote
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: magicLinkSheetBinding) {
            MagicLinkSheet(viewModel: viewModel)
        }
        .sheet(isPresented: passkeySheetBinding) {
            PasskeySheet(viewModel: viewModel)
        }
        .alert("Couldn’t sign in", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.12),
                Color(.systemBackground),
                Color(.secondarySystemBackground),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("BrandLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text("Take")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            Text("Your social\nworld awaits")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Sign in without a password using the same providers as Take SSO.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerSection: some View {
        VStack(spacing: 12) {
            // Use the shared button → AppleAuthProvider ASAuthorizationController.
            // SignInWithAppleButton + a second controller caused a broken double auth sheet.
            ForEach(AuthProvider.allCases) { provider in
                AuthProviderButton(
                    provider: provider,
                    isLoading: viewModel.loadingProvider == provider
                ) {
                    Task { await viewModel.signIn(with: provider) }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }

    private var footerNote: some View {
        VStack(spacing: 8) {
            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
            }

            Text("By continuing, you agree to Take’s Terms and Privacy Policy.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var magicLinkSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.magicLinkStep != .hidden },
            set: { isPresented in
                if !isPresented { viewModel.cancelMagicLink() }
            }
        )
    }

    private var passkeySheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.passkeyStep != .hidden },
            set: { isPresented in
                if !isPresented { viewModel.cancelPasskey() }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }
}

private struct AuthProviderButton: View {
    let provider: AuthProvider
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.systemImage)
                    .font(.title3)
                    .frame(width: 24)

                Text(provider.title)
                    .font(.body.weight(.semibold))

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PasskeySheet: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var dismissController = KeyboardDismissController()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $viewModel.passkeyUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Enter the username linked to your passkey.")
                }

                Section {
                    Button {
                        Task {
                            await viewModel.signInWithPasskey()
                            if viewModel.errorMessage == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.loadingProvider == .passkey {
                            ProgressView()
                        } else {
                            Text("Continue with Passkey")
                        }
                    }
                    .disabled(viewModel.passkeyUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }
            }
            .navigationTitle("Passkey")
            .navigationBarTitleDisplayMode(.inline)
            .liquidGlassKeyboardDismiss(controller: dismissController)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelPasskey()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct MagicLinkSheet: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var dismissController = KeyboardDismissController()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $viewModel.magicLinkEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                } footer: {
                    if viewModel.magicLinkStep == .linkSent {
                        Text("Open the link from your email to finish signing in. In development, check SSO service logs for the link.")
                    } else {
                        Text("We’ll send a one-time sign-in link to your inbox.")
                    }
                }

                Section {
                    if viewModel.magicLinkStep == .linkSent {
                        Button("Done") { dismiss() }
                    } else {
                        Button {
                            Task { await viewModel.sendMagicLink() }
                        } label: {
                            if viewModel.loadingProvider == .magicLink {
                                ProgressView()
                            } else {
                                Text("Send Magic Link")
                            }
                        }
                        .disabled(viewModel.magicLinkEmail.isEmpty || viewModel.isLoading)
                    }
                }
            }
            .navigationTitle("Magic Link")
            .navigationBarTitleDisplayMode(.inline)
            .liquidGlassKeyboardDismiss(controller: dismissController)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelMagicLink()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    WelcomeView(
        viewModel: AuthViewModel(
            authUseCase: AuthUseCase(repository: PreviewAuthRepository()),
            onAuthenticated: { _ in }
        )
    )
}

@MainActor
private final class PreviewAuthRepository: AuthRepositoryProtocol {
    func signInWithApple() async throws -> AuthSession { try await signIn() }
    func signInWithGoogle() async throws -> AuthSession { try await signIn() }
    func signInWithPasskey(username: String) async throws -> AuthSession { try await signIn() }
    func sendMagicLink(to email: String) async throws {}
    func verifyMagicLink(token: String) async throws -> AuthSession { try await signIn() }
    func refreshTokens() async throws -> AuthSession { try await signIn() }
    func logout() async throws {}
    func currentSession() async -> AuthSession? { nil }

    private func signIn() async throws -> AuthSession {
        AuthSession(
            user: User(id: "1", username: "demo", displayName: "Demo", bio: nil, avatarURL: nil, suiWallet: nil, createdAt: nil),
            tokens: AuthTokens(accessToken: "a", refreshToken: "r", expiresIn: 900, userID: "1", username: "demo")
        )
    }
}
