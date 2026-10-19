import AVFoundation
import Metal
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Ordered multi-select for attach grid (Telegram-style numbered badges).
struct ChatAttachSelection: Equatable {
    private(set) var orderedIDs: [String] = []

    var count: Int { orderedIDs.count }
    var isEmpty: Bool { orderedIDs.isEmpty }

    func number(for id: String) -> Int? {
        guard let idx = orderedIDs.firstIndex(of: id) else { return nil }
        return idx + 1
    }

    mutating func toggle(_ id: String, maxCount: Int) {
        if let idx = orderedIDs.firstIndex(of: id) {
            orderedIDs.remove(at: idx)
            return
        }
        guard orderedIDs.count < maxCount else { return }
        orderedIDs.append(id)
    }
}

enum ChatAttachTab: String, CaseIterable, Identifiable {
    case gallery
    case location
    case checklist
    case poll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: return "Gallery"
        case .location: return "Location"
        case .checklist: return "List"
        case .poll: return "Poll"
        }
    }

    var symbol: String {
        switch self {
        case .gallery: return "photo.on.rectangle"
        case .location: return "location"
        case .checklist: return "checklist"
        case .poll: return "chart.bar.xaxis"
        }
    }
}

struct ChatAttachSheet: View {
    var maxSelection: Int = ChatComposerLimits.maxPasteImages
    var library: ChatPhotoLibraryModel
    var onSend: (_ orderedIDs: [String], _ captured: [ChatCapturedPhoto], _ caption: String?) -> Void
    var onSendLocation: (DMLocation) -> Void
    var onSendChecklist: (DMChecklist) -> Void
    var onSendPoll: (DMPoll) -> Void
    var onBrowseAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var tab: ChatAttachTab = .gallery
    @State private var detent: PresentationDetent = .medium
    @State private var selection = ChatAttachSelection()
    @State private var caption = ""
    @State private var isLoadingImages = false
    @State private var loadError: String?
    @State private var captured: [ChatCapturedPhoto] = []
    @State private var previewSession: AttachCameraPreviewSession?
    @State private var dmCameraViewModel: DMCameraViewModel?
    @State private var cameraAuthorized = false
    @State private var cameraReady = false
    @State private var cameraCellVisible = true
    @State private var showCamera = false
    /// Stays true until the full-screen camera has finished dismissing, so the
    /// gallery tile does not attach a second preview layer on the way out.
    @State private var cameraCoverVisible = false
    /// False for a short beat after leaving Gallery so the camera session can stop
    /// before the next tab mounts players or a map.
    @State private var contentReady = true
    @State private var contentReveal: Task<Void, Never>?
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                if tab != .gallery, !contentReady {
                    attachTabSkeleton
                } else {
                    switch tab {
                    case .gallery:
                        gallery
                    case .location:
                        ChatLocationTab { location in
                            dismiss()
                            onSendLocation(location)
                        }
                    case .checklist:
                        ChatChecklistComposer { checklist in
                            dismiss()
                            onSendChecklist(checklist)
                        }
                    case .poll:
                        ChatPollComposer { poll in
                            dismiss()
                            onSendPoll(poll)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .defersSystemGestures(on: .bottom)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        // Keep the chat at full brightness. The default sheet scrim shifts bubble and glass colors.
        .presentationBackgroundInteraction(.enabled(upThrough: .large))
        .modifier(AttachPresentationBackground())
        .onChange(of: tab) { _, newTab in
            if newTab != .gallery {
                // Hide the preview before the session stops, so the GIF tab is not
                // waiting on the camera lock.
                cameraReady = false
                previewSession?.invalidateStart()
                selection = ChatAttachSelection()
                caption = ""
            } else {
                startCameraPreviewIfAllowed()
            }
        }
        .onChange(of: selection) { _, newValue in
            if !newValue.isEmpty, tab == .gallery {
                detent = .large
            }
        }
        .onDisappear {
            guard !showCamera, !cameraCoverVisible else { return }
            previewSession?.pause()
            TemporaryCaptureStore.purgeUnreferenced(keeping: Set(captured.map(\.fileURL)))
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            cameraCoverVisible = false
            let model = dmCameraViewModel
            dmCameraViewModel = nil
            Task {
                await model?.shutdown()
                startCameraPreviewIfAllowed()
            }
        }) {
            if let dmCameraViewModel {
                DMCameraView(
                    viewModel: dmCameraViewModel,
                    onFinish: { photos in
                        mergeCaptured(photos)
                        showCamera = false
                    },
                    onCancel: { showCamera = false }
                )
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .directGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if tab == .gallery, library.canReadLibrary {
                Menu {
                    ForEach(library.albums) { album in
                        Button(album.title) { library.selectAlbum(album.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(library.selectedAlbumTitle)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                Text(tab.title)
                    .font(.headline)
            }

            Spacer(minLength: 0)

            Menu {
                Button("All Photos", systemImage: "photo.on.rectangle") {
                    dismiss()
                    onBrowseAll()
                }
                if library.authorization == .limited {
                    Button("Manage Access", systemImage: "slider.horizontal.3") {
                        presentLimitedPicker()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .directGlass(Circle(), interactive: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var gallery: some View {
        switch library.authorization {
        case .authorized, .limited:
            let pixel = thumbPixelSize
            let previewOwner = previewSession
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    AttachCameraCell(
                        showsPreview: cameraAuthorized && cameraReady && !cameraCoverVisible,
                        session: previewSession?.captureSession,
                        onTap: { openCamera() },
                        onVisibilityChange: { visible in
                            cameraCellVisible = visible
                            if visible {
                                startCameraPreviewIfAllowed()
                            } else {
                                previewSession?.pause()
                            }
                        },
                        onDetachPreview: { layer in
                            previewOwner?.detachPreview(layer)
                        }
                    )
                    ForEach(captured) { photo in
                        AttachCapturedCell(
                            photo: photo,
                            number: selection.number(for: photo.id)
                        ) {
                            selection.toggle(photo.id, maxCount: maxSelection)
                        }
                    }
                    if library.isLoadingAssets, library.assetCount == 0 {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(3)
                            .padding(.top, 24)
                    }
                    ForEach(0..<library.assetCount, id: \.self) { index in
                        if let asset = library.asset(at: index) {
                            AttachThumbCell(
                                asset: asset,
                                manager: library.imageManager,
                                pixelSize: pixel,
                                reloadToken: library.thumbReloadToken,
                                number: selection.number(for: asset.localIdentifier)
                            ) {
                                selection.toggle(asset.localIdentifier, maxCount: maxSelection)
                            }
                            .onAppear {
                                library.noteVisibleIndex(index, pixelSize: pixel)
                            }
                        }
                    }
                }
            }
            .task { await preparePreviewAfterSettle() }
        case .denied, .restricted:
            deniedContent
        case .notDetermined:
            ProgressView()
                .task { await requestAccess() }
        @unknown default:
            deniedContent
        }
    }

    private var deniedContent: some View {
        ContentUnavailableView {
            Label("Photos Access Needed", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Allow photo access to send pictures from your library.")
        } actions: {
            Button("Allow Access") {
                Task { await requestAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if tab == .gallery, !selection.isEmpty {
                captionRow
                    .transition(captionRowTransition)
            }
            typeTabs
        }
    }

    private var captionRowTransition: AnyTransition {
        if AccessibilitySettings.reduceMotion {
            return .opacity
        }
        return .modifier(
            active: PastePreviewMotion(progress: 0),
            identity: PastePreviewMotion(progress: 1)
        )
    }

    private var captionRow: some View {
        VStack(spacing: 6) {
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 10) {
                TextField("Add a caption…", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.94))
                    }
                    .directGlass(
                        RoundedRectangle(cornerRadius: 20, style: .continuous),
                        tint: Color(.systemBackground).opacity(0.72)
                    )
                Button {
                    sendSelected()
                } label: {
                    ZStack {
                        if isLoadingImages {
                            ProgressView().tint(Color(.systemBackground))
                        } else {
                            Text("\(selection.count)")
                                .font(.headline)
                                .foregroundStyle(Color(.systemBackground))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.primary))
                }
                .buttonStyle(.plain)
                .disabled(isLoadingImages)
                .accessibilityLabel("Send \(selection.count) photos")
            }
        }
        .padding(.horizontal, 16)
    }

    private var typeTabs: some View {
        HStack(spacing: 0) {
            ForEach(ChatAttachTab.allCases) { item in
                Button {
                    tab = item
                    if item == .gallery {
                        contentReveal?.cancel()
                        contentReady = true
                    } else {
                        // Let the capture session leave the main thread before the
                        // next tab builds images, players, or a map.
                        contentReady = false
                        cameraReady = false
                        previewSession?.invalidateStart()
                        detent = .large
                        contentReveal?.cancel()
                        contentReveal = Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            guard !Task.isCancelled else { return }
                            contentReady = true
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.body.weight(.semibold))
                        Text(item.title)
                            .font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .directGlass(Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var thumbPixelSize: CGSize {
        ChatAttachGrid.thumbPixelSize(
            containerWidth: UIScreen.main.bounds.width,
            scale: displayScale
        )
    }

    /// Waits until the sheet has finished presenting so capture does not compete with the animation.
    private func preparePreviewAfterSettle() async {
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled, tab == .gallery else { return }
        await preparePreview()
    }

    private func preparePreview() async {
        cameraAuthorized = await DevicePermissions.requestCameraAccess()
        guard !Task.isCancelled, tab == .gallery, cameraAuthorized else { return }
        let session = previewSession ?? AttachCameraPreviewSession()
        previewSession = session
        do {
            try await session.start()
            guard !Task.isCancelled, tab == .gallery else {
                session.invalidateStart()
                cameraReady = false
                return
            }
            cameraReady = true
            startCameraPreviewIfAllowed()
        } catch {
            cameraReady = false
        }
    }

    /// Gray cells while the camera session stops. No images, players, or map.
    private var attachTabSkeleton: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .frame(height: 40)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 140)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
    }

    private func startCameraPreviewIfAllowed() {
        guard tab == .gallery,
              contentReady,
              cameraAuthorized,
              cameraReady,
              cameraCellVisible,
              !showCamera,
              !cameraCoverVisible
        else {
            if !showCamera, !cameraCoverVisible {
                previewSession?.pause()
            }
            return
        }
        previewSession?.resume()
    }

    private func openCamera() {
        Task {
            var allowed = cameraAuthorized
            if !allowed {
                allowed = await DevicePermissions.requestCameraAccess()
            }
            cameraAuthorized = allowed
            guard allowed else { return }
            // Drop the tile layer, then stop that session before the full camera starts.
            cameraCoverVisible = true
            await previewSession?.stopAndWait()
            dmCameraViewModel = DMCameraViewModel()
            showCamera = true
        }
    }

    private func mergeCaptured(_ photos: [ChatCapturedPhoto]) {
        for photo in photos {
            if !captured.contains(where: { $0.id == photo.id }) {
                captured.append(photo)
            }
            if selection.number(for: photo.id) == nil {
                selection.toggle(photo.id, maxCount: maxSelection)
            }
        }
    }

    private func requestAccess() async {
        _ = await DevicePermissions.requestPhotoLibraryAccess()
        library.refreshAuthorization()
    }

    private func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private func sendSelected() {
        let ids = selection.orderedIDs
        guard !ids.isEmpty else { return }
        let shots = captured
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
        onSend(ids, shots, trimmed.isEmpty ? nil : trimmed)
    }
}

private struct AttachThumbCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let pixelSize: CGSize
    let reloadToken: Int
    let number: Int?
    var onTap: () -> Void

    @State private var thumb: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    private var loadKey: String {
        let side = Int(pixelSize.width.rounded())
        return "\(asset.localIdentifier)#\(side)#\(reloadToken)"
    }

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.secondary.opacity(0.15)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    AttachSelectionBadge(number: number)
                        .padding(6)
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: loadKey) { await loadThumb() }
        .onDisappear { cancelRequest() }
    }

    private func cancelRequest() {
        let id = requestID
        guard id != PHInvalidImageRequestID else { return }
        requestID = PHInvalidImageRequestID
        manager.cancelImageRequest(id)
    }

    private func loadThumb() async {
        cancelRequest()
        let size = pixelSize == .zero ? CGSize(width: 200, height: 200) : pixelSize
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let image: UIImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var finished = false
                let id = manager.requestImage(
                    for: asset,
                    targetSize: size,
                    contentMode: .aspectFill,
                    options: options
                ) { image, info in
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    if cancelled {
                        if !finished {
                            finished = true
                            continuation.resume(returning: nil)
                        }
                        return
                    }
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if degraded {
                        if let image {
                            Task { @MainActor in thumb = image }
                        }
                        return
                    }
                    guard !finished else { return }
                    finished = true
                    continuation.resume(returning: image)
                }
                requestID = id
            }
        } onCancel: {
            let id = requestID
            if id != PHInvalidImageRequestID {
                manager.cancelImageRequest(id)
            }
        }
        if !Task.isCancelled, let image { thumb = image }
    }
}

private struct AttachPresentationBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.presentationBackground(Color(.systemBackground))
        } else {
            content
        }
    }
}
