import SwiftUI
import UIKit
import os

struct DMPhotoMarkupView: View {
    let photo: ChatCapturedPhoto
    var startsWithText = false
    var onCancel: () -> Void
    var onDone: (ChatCapturedPhoto) -> Void

    @State private var displayImage: UIImage?
    @State private var displayCGImage: CGImage?
    /// Full-res file used for export (original capture or post-crop JPEG).
    @State private var workingFileURL: URL?
    @State private var document = MarkupDocument()
    @State private var mode: MarkupMode = .idle
    @State private var brush: MarkupBrush = .pen
    @State private var colorHex = MarkupPalette.defaultDrawColor
    @State private var widthSlider: CGFloat = 0.35
    @State private var reloadToken = 0
    @State private var textDraft: MarkupTextDraft?
    @State private var showCrop = false
    @State private var isExporting = false
    @State private var fittedCanvas: CGSize = CGSize(width: 300, height: 400)
    @State private var gestureState = MarkupTextGestureState()
    @State private var trashFlight: TrashFlight?
    @State private var hasFitted = false

    private let signposter = OSSignposter(
        logger: Logger(subsystem: Bundle.main.bundleIdentifier ?? "AltonApp", category: "DMMarkup")
    )

    private enum MarkupMode: Equatable {
        case idle
        case draw
    }

    private struct TrashFlight: Equatable {
        var id: UUID
        var center: MarkupPoint
        var scale: CGFloat
        var rotation: CGFloat
    }

    private var chromeHidden: Bool {
        textDraft != nil || gestureState.isInteracting
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let displayImage {
                GeometryReader { geo in
                    let fitted = Self.fittedSize(for: displayImage.size, in: geo.size)
                    let _ = updateFitted(fitted)
                    let origin = CGPoint(
                        x: (geo.size.width - fitted.width) / 2,
                        y: (geo.size.height - fitted.height) / 2
                    )
                    ZStack {
                        canvas(image: displayImage, size: fitted)
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: origin.x + fitted.width / 2, y: origin.y + fitted.height / 2)

                        if mode == .draw, !chromeHidden {
                            MarkupVerticalSlider(value: $widthSlider)
                                .position(x: 28, y: geo.size.height * 0.42)
                        }
                    }
                }
                .ignoresSafeArea(.all)
            } else {
                ProgressView().tint(.white)
            }

            if !chromeHidden {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if mode == .draw {
                        MarkupDrawToolbar(
                            brush: $brush,
                            colorHex: $colorHex,
                            widthSlider: $widthSlider
                        )
                    }
                    modeBar
                }
                .transition(.opacity)
            }

            if let draftBinding = draftBinding {
                MarkupTextEditorOverlay(
                    draft: draftBinding,
                    canvasSize: fittedCanvas,
                    sampleImage: displayCGImage,
                    onDone: commitTextDraft,
                    onCancel: cancelTextDraft
                )
            }

            if isExporting {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .statusBarHidden(true)
        .ignoresSafeArea(.keyboard)
        .task { await loadDisplayImage() }
        .fullScreenCover(isPresented: $showCrop) {
            if let displayImage {
                PhotoCropEditorView(
                    image: displayImage,
                    mask: .rectangle,
                    initialAspect: .original,
                    onCancel: {
                        showCrop = false
                        mode = .idle
                    },
                    onComplete: { cropped in
                        applyCroppedBase(cropped)
                        document.clearAll()
                        reloadToken += 1
                        showCrop = false
                        mode = .idle
                    }
                )
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            if mode == .draw {
                Button("Done") { mode = .idle }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
            } else {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    document.undo()
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(document.canUndo ? .white : .white.opacity(0.3))
                }
                .disabled(!document.canUndo)
                Button {
                    document.redo()
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .foregroundStyle(document.canRedo ? .white : .white.opacity(0.3))
                }
                .disabled(!document.canRedo)
                Spacer()
                Button("Done") { export() }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .disabled(isExporting || displayImage == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var modeBar: some View {
        HStack(spacing: 20) {
            if mode == .idle {
                toolCircle(label: "Aa") {
                    textDraft = MarkupTextDraft.fresh()
                }
                toolCircle(systemImage: "pencil.tip") {
                    mode = .draw
                }
                toolCircle(systemImage: "crop") {
                    showCrop = true
                }
            }
        }
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private func toolCircle(systemImage: String? = nil, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let label {
                    Text(label).font(.system(size: 18, weight: .bold))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Color.white.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func updateFitted(_ size: CGSize) {
        if hasFitted, textDraft != nil { return }
        if abs(fittedCanvas.width - size.width) > 0.5 || abs(fittedCanvas.height - size.height) > 0.5 || !hasFitted {
            DispatchQueue.main.async {
                fittedCanvas = size
                hasFitted = true
                if startsWithText, textDraft == nil {
                    textDraft = MarkupTextDraft.fresh()
                }
            }
        }
    }

    // MARK: - Canvas

    private func canvas(image: UIImage, size: CGSize) -> some View {
        let trashInCanvas = CGRect(
            x: size.width / 2 - 44,
            y: size.height - 88,
            width: 88,
            height: 88
        )
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: size.width, height: size.height)

            MarkupDrawingRepresentable(
                document: $document,
                brush: brush,
                colorHex: colorHex,
                widthSlider: widthSlider,
                isDrawingEnabled: mode == .draw && textDraft == nil,
                reloadToken: reloadToken
            )
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(mode == .draw)

            MarkupSnapGuides(
                showVertical: gestureState.showVerticalGuide,
                showHorizontal: gestureState.showHorizontalGuide,
                canvasSize: size
            )

            ForEach(document.texts) { item in
                let isActive = gestureState.activeID == item.id
                let flying = trashFlight?.id == item.id
                MarkupTextLayer(
                    item: item,
                    canvasSize: size,
                    liveCenter: flying ? trashFlight?.center : (isActive ? gestureState.center : nil),
                    liveScale: flying ? trashFlight?.scale : (isActive ? gestureState.scale : nil),
                    liveRotation: flying ? trashFlight?.rotation : (isActive ? gestureState.rotation : nil),
                    isHidden: textDraft?.id == item.id,
                    trashHoverScale: isActive && gestureState.trashHovering ? 1.12 : 1,
                    motionAnimation: flying ? .timingCurve(0.45, 0.02, 0.85, 0.35, duration: 0.48) : nil
                )
                .transition(.opacity)
            }
            .animation(
                gestureState.isInteracting ? nil : .spring(response: 0.28, dampingFraction: 0.86),
                value: document.texts.map(\.id)
            )

            if mode == .idle, textDraft == nil {
                MarkupTextGestureRepresentable(
                    texts: document.texts,
                    canvasSize: size,
                    trashFrameInCanvas: trashInCanvas,
                    isEnabled: true,
                    gestureState: gestureState,
                    onEdit: { id in
                        if let item = document.texts.first(where: { $0.id == id }) {
                            textDraft = MarkupTextDraft(from: item, isNew: false)
                        }
                    },
                    onCommit: { id, center, scale, rotation in
                        document.updateTextTransform(
                            id: id,
                            center: center,
                            scale: scale,
                            rotation: rotation
                        )
                    },
                    onDelete: { id, center, scale in
                        flyIntoTrash(id: id, from: center, scale: scale, canvasHeight: size.height)
                    },
                    onTapEmpty: { location in
                        let center = MarkupPoint(
                            x: min(max(location.x / size.width, 0), 1),
                            y: min(max(location.y / size.height, 0), 1)
                        )
                        textDraft = MarkupTextDraft.fresh(at: center)
                    }
                )
                .frame(width: size.width, height: size.height)
            }

            MarkupTrashTarget(
                isActive: gestureState.isInteracting || trashFlight != nil,
                isHovering: gestureState.trashHovering,
                isSwallowing: trashFlight != nil
            )
            .position(x: size.width / 2, y: size.height - 44)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var draftBinding: Binding<MarkupTextDraft>? {
        guard textDraft != nil else { return nil }
        return Binding(
            get: { textDraft! },
            set: { textDraft = $0 }
        )
    }

    // MARK: - Load / text / export

    private func loadDisplayImage() async {
        workingFileURL = photo.fileURL
        let maxEdge = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * min(UIScreen.main.scale, 2)
        if let cg = CPUImageIO.decodeOrientedImage(at: photo.fileURL, maxLongEdge: maxEdge) {
            displayCGImage = cg
            displayImage = CPUImageIO.uiImage(from: cg)
        } else if let full = try? photo.loadFullImage() {
            displayImage = full
            displayCGImage = full.cgImage
        } else {
            onCancel()
        }
    }

    private func applyCroppedBase(_ cropped: UIImage) {
        guard let cg = Self.flattenedCGImage(cropped) else {
            displayImage = cropped
            displayCGImage = cropped.cgImage
            return
        }
        displayCGImage = cg
        displayImage = CPUImageIO.uiImage(from: cg)
        if let data = CPUImageIO.encodeJPEG(cgImage: cg, quality: 0.92) {
            let url = TemporaryCaptureStore.photoURL()
            try? data.write(to: url, options: .atomic)
            if let previous = workingFileURL, previous != photo.fileURL {
                TemporaryCaptureStore.removeIfManaged(previous)
            }
            workingFileURL = url
            if let screen = CPUImageIO.scaled(
                cg,
                maxLongEdge: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * min(UIScreen.main.scale, 2)
            ) {
                displayCGImage = screen
                displayImage = CPUImageIO.uiImage(from: screen)
            }
        }
    }

    private static func flattenedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let w = max(1, Int(image.size.width.rounded()))
        let h = max(1, Int(image.size.height.rounded()))
        guard let ctx = CPUImageIO.makeBitmapContext(width: w, height: h) else {
            return image.cgImage
        }
        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        UIGraphicsPopContext()
        return ctx.makeImage() ?? image.cgImage
    }

    private func flyIntoTrash(id: UUID, from center: MarkupPoint, scale: CGFloat, canvasHeight: CGFloat) {
        let sinkY = max(0.84, (canvasHeight - 44) / max(canvasHeight, 1))
        let rotation = document.texts.first(where: { $0.id == id })?.rotation ?? 0
        trashFlight = TrashFlight(id: id, center: center, scale: scale, rotation: rotation)
        let flight = Animation.timingCurve(0.45, 0.02, 0.85, 0.35, duration: 0.48)
        DispatchQueue.main.async {
            withAnimation(flight) {
                trashFlight?.center = MarkupPoint(x: 0.5, y: sinkY)
                trashFlight?.scale = max(0.04, scale * 0.08)
                trashFlight?.rotation = rotation * 0.2
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                document.removeText(id: id)
                trashFlight = nil
            }
        }
    }

    private func commitTextDraft() {
        guard let draft = textDraft else { return }
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !draft.isNew {
                document.removeText(id: draft.id)
            }
            textDraft = nil
            return
        }
        var item = draft.asItem()
        item.text = trimmed
        MarkupTextPreferences.save(from: item)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            document.upsertText(item)
        }
        textDraft = nil
        mode = .idle
    }

    private func cancelTextDraft() {
        // Outside tap uses Done semantics in editor; Cancel is rare — discard empty new drafts.
        if let draft = textDraft, draft.isNew,
           draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textDraft = nil
            return
        }
        commitTextDraft()
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        let doc = document
        let baseURL = workingFileURL ?? photo.fileURL
        let photoID = photo.id

        Task {
            let state = signposter.beginInterval("dm.markup.export")
            let result: ChatCapturedPhoto? = await Task.detached(priority: .userInitiated) {
                guard let base = CPUImageIO.decodeOrientedImage(
                    at: baseURL,
                    maxLongEdge: DMImageRules.maxLongEdge * 2
                ) else { return nil }

                guard let rendered = MarkupRenderer.renderExport(base: base, document: doc) else {
                    return nil
                }
                guard let jpeg = CPUImageIO.encodeJPEG(cgImage: rendered, quality: 0.9) else {
                    return nil
                }
                let outURL = TemporaryCaptureStore.photoURL()
                do {
                    try jpeg.write(to: outURL, options: .atomic)
                } catch {
                    return nil
                }
                let thumbCG = CPUImageIO.decodeOrientedThumbnail(from: jpeg, maxLongEdge: 240)
                    ?? CPUImageIO.scaled(rendered, maxLongEdge: 240)
                let thumb = thumbCG.map { CPUImageIO.uiImage(from: $0) } ?? UIImage()
                return ChatCapturedPhoto(id: photoID, fileURL: outURL, preview: thumb)
            }.value
            signposter.endInterval("dm.markup.export", state)

            await MainActor.run {
                isExporting = false
                if let result {
                    onDone(result)
                }
            }
        }
    }

    private static func fittedSize(for image: CGSize, in bounds: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return bounds }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
