import SwiftUI
import PhotosUI

enum CreatePostPresentation {
    case sheet
    case fullScreen
}

struct CreatePostView: View {
    @Bindable var viewModel: CreatePostViewModel
    let session: AuthSession
    var searchUseCase: SearchUseCase?
    var presentation: CreatePostPresentation = .fullScreen
    var onPublished: (() -> Void)?
    var onShotPublished: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isPreviewMode = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var shotComposer: ShotComposerPresentation?
    @State private var dismissTask: Task<Void, Never>?
    @State private var mentionPicker: MentionPickerModel
    @State private var pendingFormatAction: RichTextFormatAction?
    @State private var chromeState = ComposerChromeState()
    @State private var formatState = RichTextFormatState()
    @State private var photosPickerPresented = false
    @State private var activeCrop: PhotoCropDraft?
    @State private var editorFocusID = 0
    @State private var composerViewportHeight: CGFloat = 0
    @State private var pendingEdit: PendingComposerEdit?
    @State private var composerEditID = 0
    @State private var dismissController = KeyboardDismissController()

    init(
        viewModel: CreatePostViewModel,
        session: AuthSession,
        searchUseCase: SearchUseCase? = nil,
        presentation: CreatePostPresentation = .fullScreen,
        onPublished: (() -> Void)? = nil,
        onShotPublished: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.session = session
        self.searchUseCase = searchUseCase
        self.presentation = presentation
        self.onPublished = onPublished
        self.onShotPublished = onShotPublished
        _mentionPicker = State(initialValue: MentionPickerModel(searchUseCase: searchUseCase))
    }

    private var showsDismissControl: Bool {
        presentation == .sheet || presentation == .fullScreen
    }

    private var navigationTitle: String {
        viewModel.isEditing ? "Edit Take" : "New Take"
    }

    private var remainingPickerSlots: Int {
        max(0, CreatePostViewModel.maxAttachments - viewModel.attachments.count)
    }

    private var usedCharacters: Int {
        CreatePostViewModel.characterLimit - viewModel.remainingCharacters
    }

    private var editorFloorHeight: CGFloat {
        let attachmentAllowance: CGFloat = viewModel.attachments.isEmpty ? 0 : 124
        let available = composerViewportHeight - attachmentAllowance - 40
        guard composerViewportHeight > 1 else { return 220 }
        return max(168, available)
    }

    private var chromeHeight: CGFloat {
        var height = ComposerBottomChrome.toolRowHeight
        if chromeState.showFormatTools, !isPreviewMode {
            height += ComposerBottomChrome.formatRowHeight
        }
        return height
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 12) {
                        UserAvatarView(user: session.user, size: 40)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(session.user.username)
                                .font(.subheadline.weight(.semibold))
                                .padding(.top, 2)

                            MarkdownEditorView(
                                text: $viewModel.content,
                                isPreviewMode: $isPreviewMode,
                                characterLimit: CreatePostViewModel.characterLimit,
                                editorMinHeight: editorFloorHeight,
                                showsCharacterCount: false,
                                style: .composer,
                                placeholder: "What's new?",
                                autoFocus: true,
                                expandsToFitContent: true,
                                focusRequestID: editorFocusID,
                                onFormatStateChange: { formatState = $0 },
                                onSelectionLengthChange: { length in
                                    guard length > 0, !isPreviewMode, !chromeState.showFormatTools else { return }
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        chromeState.showFormatTools = true
                                    }
                                },
                                onPlainCaretChange: { plain, caret in
                                    mentionPicker.update(plainText: plain, utf16Caret: caret)
                                },
                                pendingEdit: $pendingEdit,
                                pendingFormatAction: $pendingFormatAction
                            )
                            .padding(.top, 6)
                            .id("composerEditor")

                            if !viewModel.attachments.isEmpty {
                                ComposerAttachmentStrip(
                                    attachments: viewModel.attachments,
                                    remainingSlots: remainingPickerSlots,
                                    onRemove: { viewModel.removeAttachment($0) },
                                    onEdit: { attachment in
                                        guard let image = UIImage(data: attachment.data) else { return }
                                        activeCrop = PhotoCropDraft(
                                            image: image,
                                            pickerItemID: attachment.pickerItemID,
                                            replacingAttachmentID: attachment.id
                                        )
                                    },
                                    onAddPhotos: remainingPickerSlots > 0
                                        ? { photosPickerPresented = true }
                                        : nil
                                )
                                .padding(.top, 14)
                            }

                            if let errorMessage = viewModel.errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                    .padding(.top, 12)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .background(Color(.systemBackground))
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                guard abs(composerViewportHeight - geo.size.height) > 1 else { return }
                                composerViewportHeight = geo.size.height
                            }
                            .onChange(of: geo.size.height) { _, height in
                                guard abs(composerViewportHeight - height) > 1 else { return }
                                composerViewportHeight = height
                            }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: mentionPicker.isVisible) { _, visible in
                    guard visible else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("composerEditor", anchor: .top)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .liquidGlassKeyboardDismiss(controller: dismissController)
            .toolbar {
                if showsDismissControl {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            viewModel.cancelComposer()
                            dismiss()
                        }
                        .disabled(viewModel.isSubmitting)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KeyboardSafeHost(content: composerChrome)
                    .frame(height: chromeHeight)
            }
            .overlay(alignment: .bottom) {
                if !mentionPicker.users.isEmpty {
                    MentionOverlayView(
                        candidates: mentionPicker.users,
                        query: ""
                    ) { user in
                        guard let range = mentionPicker.activeRange else { return }
                        composerEditID += 1
                        pendingEdit = PendingComposerEdit(
                            id: composerEditID,
                            replacement: ComposerTextReplacement(
                                location: range.location,
                                length: range.length,
                                text: "@\(user.username) "
                            )
                        )
                        mentionPicker.hide()
                        editorFocusID += 1
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, chromeHeight + 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: mentionPicker.users.isEmpty)
            .onChange(of: viewModel.content) { _, newValue in
                if newValue.isEmpty {
                    mentionPicker.hide()
                }
            }
            .photosPicker(
                isPresented: $photosPickerPresented,
                selection: $selectedPhotoItems,
                maxSelectionCount: max(remainingPickerSlots, 1),
                matching: .any(of: [.images, .livePhotos]),
                photoLibrary: .shared()
            )
            .onChange(of: photosPickerPresented) { _, presented in
                if presented, remainingPickerSlots == 0 {
                    photosPickerPresented = false
                    return
                }
                if !presented {
                    editorFocusID += 1
                }
            }
            .onChange(of: activeCrop?.id) { previous, next in
                if previous != nil, next == nil {
                    editorFocusID += 1
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let snapshot = newItems
                Task {
                    let generation = await viewModel.addAttachments(from: snapshot)
                    if viewModel.attachmentLoadGeneration == generation {
                        selectedPhotoItems = []
                    }
                }
            }
            .fullScreenCover(item: $activeCrop) { draft in
                PhotoCropEditorView(
                    image: draft.image,
                    mask: .rectangle,
                    initialAspect: .original,
                    onCancel: { activeCrop = nil },
                    onComplete: { edited in
                        activeCrop = nil
                        Task {
                            if let replacingID = draft.replacingAttachmentID {
                                await viewModel.replaceAttachment(id: replacingID, with: edited)
                            }
                        }
                    }
                )
            }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .fullScreenCover(item: $shotComposer) { presentation in
            CameraView(
                viewModel: presentation.viewModel,
                session: session,
                onPublishStarted: {
                    shotComposer = nil
                    dismiss()
                }
            )
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
        .onChange(of: viewModel.successMessage) { _, message in
            guard message != nil, showsDismissControl else { return }
            onPublished?()
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    private var composerChrome: some View {
        ComposerBottomChrome(
            chromeState: $chromeState,
            isPreviewMode: isPreviewMode,
            formatState: formatState,
            publishState: ComposerPublishState(
                canSubmitContent: viewModel.canSubmitContent,
                isSubmitting: viewModel.isSubmitting
            ),
            publishTitle: viewModel.isEditing ? "Save" : "Post",
            attachmentCount: viewModel.attachments.count,
            maxAttachments: CreatePostViewModel.maxAttachments,
            usedCharacters: usedCharacters,
            characterLimit: CreatePostViewModel.characterLimit,
            onPhotos: {
                guard remainingPickerSlots > 0 else { return }
                photosPickerPresented = true
            },
            onMention: {
                composerEditID += 1
                pendingEdit = PendingComposerEdit(id: composerEditID, insert: "@")
                editorFocusID += 1
            },
            onTogglePreview: {
                isPreviewMode.toggle()
                if isPreviewMode {
                    chromeState.showFormatTools = false
                } else {
                    editorFocusID += 1
                }
            },
            onFormatAction: { pendingFormatAction = $0 },
            onRecordShot: {
                shotComposer = ShotComposerPresentation(
                    viewModel: viewModel.makeCameraViewModel()
                )
            },
            onRemoveAllPhotos: {
                for attachment in viewModel.attachments {
                    viewModel.removeAttachment(attachment)
                }
            },
            onPublish: { Task { await viewModel.submit() } }
        )
    }
}

private struct ShotComposerPresentation: Identifiable {
    let id = UUID()
    let viewModel: CameraViewModel
}

/// Hosts the composer bar so taps keep the text view first responder.
private struct KeyboardSafeHost<Content: View>: UIViewRepresentable {
    let content: Content

    func makeUIView(context: Context) -> KeyboardSafeContainer<Content> {
        let container = KeyboardSafeContainer<Content>()
        container.backgroundColor = .clear
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.sizingOptions = .intrinsicContentSize
        context.coordinator.host = host
        container.install(host)
        return container
    }

    func updateUIView(_ uiView: KeyboardSafeContainer<Content>, context: Context) {
        context.coordinator.host?.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var host: UIHostingController<Content>?
    }
}

private final class KeyboardSafeContainer<Content: View>: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func install(_ host: UIHostingController<Content>) {
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil {
            RichTextFocusLock.holdForToolbarInteraction()
        }
        return hit
    }
}
