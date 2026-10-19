import SwiftUI

struct DMCameraView: View {
    @Bindable var viewModel: DMCameraViewModel
    var onFinish: ([ChatCapturedPhoto]) -> Void
    var onCancel: () -> Void

    /// Drop the preview layer before the cover animates away.
    @State private var previewAttached = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.phase {
            case .capturing, .countdown:
                captureScreen
            case .reviewing(let photo):
                DMPhotoReviewView(
                    photo: photo,
                    onRetake: { viewModel.discardReview() },
                    onEdit: { viewModel.openMarkup() },
                    onAddText: { viewModel.openMarkup(editingText: true) },
                    onUse: {
                        // Do not flip back to the live preview or restart the session.
                        // That mounts a Metal view and startRunning on the way out and freezes Use.
                        viewModel.beginClose()
                        onFinish(viewModel.captured)
                    }
                )
            case .markup(let photo):
                DMPhotoMarkupView(
                    photo: photo,
                    startsWithText: viewModel.markupStartsWithText,
                    onCancel: { viewModel.cancelMarkup() },
                    onDone: { edited in viewModel.finishMarkup(edited) }
                )
            }

            if viewModel.screenFlashVisible {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .task { await viewModel.prepare() }
        .onDisappear {
            Task { await viewModel.shutdown() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.pauseForBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.resumeFromBackground()
        }
        .alert("Camera", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onCameraCaptureEvent(isEnabled: true) { event in
            switch event.phase {
            case .began:
                viewModel.hardwareCaptureBegan()
            case .ended:
                viewModel.hardwareCaptureEnded(cancelled: false)
            case .cancelled:
                viewModel.hardwareCaptureEnded(cancelled: true)
            @unknown default:
                break
            }
        }
    }

    private func closeCamera() {
        // Drop the preview layer in this update, while the session lock is free.
        // Stop capture on the next turn so session = nil and stopRunning do not
        // wait on each other.
        previewAttached = false
        Task { @MainActor in
            viewModel.beginClose()
            onCancel()
        }
    }

    private var captureScreen: some View {
        ZStack {
            // Preview sits in the capture aspect (4:3 by default). Filling the tall
            // screen with aspect-fill crops in and looks closer than the tile camera.
            GeometryReader { geo in
                let frame = DMCameraAspectMask.visibleRect(in: geo.size, aspect: viewModel.aspect)
                if previewAttached {
                    DMCameraPreviewView(
                        session: viewModel.cameraSession.captureSession,
                        onPinchBegan: { viewModel.pinchBegan() },
                        onPinchScale: { viewModel.pinchScale($0) },
                        onFocus: { viewPoint, devicePoint, lock in
                            if viewModel.panel != .none {
                                viewModel.closePanel()
                                return
                            }
                            viewModel.focus(viewPoint: viewPoint, devicePoint: devicePoint, lock: lock)
                        },
                        onExposurePanBegan: {
                            if viewModel.panel != .none {
                                viewModel.closePanel()
                                return
                            }
                            viewModel.beginExposureAdjust()
                        },
                        onExposurePanChanged: { viewModel.adjustExposure(translationY: $0) },
                        onExposurePanEnded: { viewModel.endExposureAdjust() }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            .ignoresSafeArea()

            DMCameraAspectMask(aspect: viewModel.aspect)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if viewModel.showGrid {
                DMCameraGridOverlay(aspect: viewModel.aspect)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                DMCameraLevelOverlay(reading: viewModel.levelReading)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if let focus = viewModel.focusIndicator {
                DMFocusIndicatorView(
                    state: focus,
                    minBias: viewModel.minExposureBias,
                    maxBias: viewModel.maxExposureBias
                )
            }
            if case .countdown(let value) = viewModel.phase {
                DMCountdownOverlay(value: value)
            }

            VStack(spacing: 0) {
                topBar

                if viewModel.panel == .settings {
                    DMCameraSettingsStrip(
                        timerDelay: viewModel.timerDelay,
                        aspect: viewModel.aspect,
                        showGrid: viewModel.showGrid,
                        onCycleTimer: viewModel.cycleTimer,
                        onCycleAspect: viewModel.cycleAspect,
                        onToggleGrid: viewModel.toggleGrid
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                if viewModel.panel == .filters {
                    DMCameraFilterPanel(
                        filters: viewModel.availableFilters,
                        selectedFilterID: viewModel.activeFilterID,
                        beautyIntensity: viewModel.beautyIntensity,
                        onSelectFilter: viewModel.selectFilter,
                        onBeautyChange: viewModel.setBeauty
                    )
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    zoomAndFiltersRow
                        .padding(.bottom, 8)
                }

                bottomBar
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.panel)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: closeCamera) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: CameraChrome.controlSize, height: CameraChrome.controlSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                viewModel.togglePanel(.settings)
            } label: {
                Image(systemName: viewModel.panel == .settings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(viewModel.panel == .settings ? CameraChrome.accent : .white)
                    .frame(width: CameraChrome.controlSize, height: CameraChrome.controlSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            FlashToggle(
                flashMode: viewModel.flashController.mode,
                isVisible: viewModel.showsFlashControl,
                action: viewModel.cycleFlash
            )
            .frame(width: CameraChrome.controlSize, height: CameraChrome.controlSize)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var zoomAndFiltersRow: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if !viewModel.zoomStops.isEmpty {
                CameraZoomRailView(
                    stops: viewModel.zoomStops,
                    selectedFactor: viewModel.zoomFactor,
                    liveLabel: viewModel.zoomDisplayLabel,
                    onSelect: viewModel.selectZoom
                )
            }
            Button {
                viewModel.togglePanel(.filters)
            } label: {
                Image(systemName: "camera.filters")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        viewModel.activeFilterID != "original" || viewModel.beautyIntensity > 0.01
                            ? CameraChrome.accent
                            : .white
                    )
                    .frame(width: CameraChrome.controlSize, height: CameraChrome.controlSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            thumbnailButton
                .frame(width: 72, alignment: .leading)

            Spacer()

            DMShutterButton(
                isReady: viewModel.isCameraReady,
                onTap: { viewModel.shutterTapped() }
            )

            Spacer()

            Button {
                Task { await viewModel.flipCamera() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isCameraReady)
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var thumbnailButton: some View {
        if viewModel.captured.isEmpty {
            Color.clear.frame(width: 56, height: 56)
        } else {
            Button {
                onFinish(viewModel.captured)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: viewModel.captured.last!.preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2)
                        }

                    if viewModel.captured.count > 1 {
                        Text("\(viewModel.captured.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(CameraChrome.accent, in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(viewModel.captured.count) photos")
        }
    }
}

private struct DMShutterButton: View {
    var isReady: Bool
    var onTap: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: CameraChrome.shutterOuter, height: CameraChrome.shutterOuter)
            Circle()
                .fill(.white)
                .frame(width: CameraChrome.shutterInnerPhoto, height: CameraChrome.shutterInnerPhoto)
        }
        .opacity(isReady ? 1 : 0.5)
        .onTapGesture { onTap() }
        .disabled(!isReady)
        .accessibilityLabel("Shutter")
    }
}
