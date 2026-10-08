import SwiftUI

struct ShotPublicationView: View {
    @Bindable var viewModel: CameraViewModel
    let videoURL: URL
    var session: AuthSession
    var onPublishStarted: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showCoverPicker = false
    @State private var showHashtagSheet = false
    @State private var hashtagQuery = ""
    @State private var draftSavedToast = false
    @State private var dismissController = KeyboardDismissController()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 20) {
                        videoHero
                        editRow
                        captionSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            VStack { Spacer(); bottomBar }
            if draftSavedToast {
                Text("Draft saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.75), in: Capsule())
                    .transition(.opacity)
            }
        }
        .liquidGlassKeyboardDismiss(controller: dismissController)
        .sheet(isPresented: $showCoverPicker) {
            CoverFramePicker(videoURL: videoURL, selectedTime: $viewModel.thumbnailTime, coverImage: $viewModel.coverImage)
        }
        .sheet(isPresented: $showHashtagSheet) {
            HashtagInsertSheet(caption: $viewModel.caption, query: $hashtagQuery)
        }
    }

    private var topBar: some View {
        HStack {
            Button { viewModel.backFromPublication() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            Spacer()
            Text("New Shot").font(.headline)
            Spacer()
            Button { publish() } label: {
                if viewModel.isUploading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Post")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .disabled(viewModel.isUploading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var videoHero: some View {
        ZStack {
            Group {
                if let cover = viewModel.coverImage {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    ShotPlayerView(url: videoURL, isActive: false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
    }

    private var editRow: some View {
        HStack(spacing: 10) {
            editPill("scissors", "Edit shot") { viewModel.openFullEditorFromPublication() }
            editPill("photo", "Cover") { showCoverPicker = true }
            Spacer()
        }
    }

    private func editPill(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var captionSection: some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatarView(user: session.user, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.user.username).font(.subheadline.weight(.semibold))
                TextField("Add a caption...", text: $viewModel.caption, axis: .vertical)
                    .lineLimit(3...8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button { showHashtagSheet = true } label: {
                Image(systemName: "number").font(.system(size: 18)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add hashtag")
            Spacer()
            Button {
                Task {
                    let ok = await viewModel.saveShotDraft()
                    if ok {
                        withAnimation { draftSavedToast = true }
                        try? await Task.sleep(for: .seconds(1.2))
                        draftSavedToast = false
                        onDismiss?()
                        dismiss()
                    }
                }
            } label: {
                if viewModel.isSavingDraft {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save draft").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .disabled(viewModel.isSavingDraft)
            Button { publish() } label: {
                Text("Post")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isUploading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func publish() {
        viewModel.publishVideo {
            onPublishStarted?()
            dismiss()
        }
    }
}
