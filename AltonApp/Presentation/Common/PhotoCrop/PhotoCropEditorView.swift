import SwiftUI
import UIKit

enum PhotoCropMask: Equatable {
    case rectangle
    case circle
}

enum PhotoCropAspect: String, CaseIterable, Identifiable, Hashable {
    case free
    case original
    case square
    case portrait
    case landscape
    case story
    /// DM max tall crop (1:3).
    case dmMaxPortrait
    /// DM max wide crop (3:1).
    case dmMaxLandscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .landscape: return "16:9"
        case .story: return "9:16"
        case .dmMaxPortrait: return "1:3"
        case .dmMaxLandscape: return "3:1"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .free, .original: return nil
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .landscape: return 16.0 / 9.0
        case .story: return 9.0 / 16.0
        case .dmMaxPortrait: return 1.0 / 3.0
        case .dmMaxLandscape: return 3.0
        }
    }

    /// Aspects shown in the editor picker (DM extremes are opt-in via `initialAspect`).
    static var pickerCases: [PhotoCropAspect] {
        [.free, .original, .square, .portrait, .landscape, .story]
    }
}

enum PhotoEditorTool: String, CaseIterable, Identifiable {
    case crop
    case rotate
    case adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crop: return "Crop"
        case .rotate: return "Rotate"
        case .adjust: return "Adjust"
        }
    }

    var systemImage: String {
        switch self {
        case .crop: return "crop"
        case .rotate: return "crop.rotate"
        case .adjust: return "slider.horizontal.3"
        }
    }
}

struct PhotoCropDraft: Identifiable {
    let id: UUID
    let image: UIImage
    var pickerItemID: String?
    var replacingAttachmentID: UUID?

    init(
        id: UUID = UUID(),
        image: UIImage,
        pickerItemID: String? = nil,
        replacingAttachmentID: UUID? = nil
    ) {
        self.id = id
        self.image = image
        self.pickerItemID = pickerItemID
        self.replacingAttachmentID = replacingAttachmentID
    }
}

/// Full-screen photo editor: crop, rotate/flip/straighten, and color adjustments.
struct PhotoCropEditorView: View {
    static let minimumCropScale: CGFloat = 1
    static let maximumCropScale: CGFloat = 8

    let image: UIImage
    let mask: PhotoCropMask
    var initialAspect: PhotoCropAspect = .original
    let onCancel: () -> Void
    let onComplete: (UIImage) -> Void

    @State private var tool: PhotoEditorTool = .crop
    @State private var aspect: PhotoCropAspect
    @State private var baseImage: UIImage
    @State private var adjustments = PhotoAdjustments()
    @State private var straightenDegrees: CGFloat = 0
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var selectedAdjust: AdjustParameter = .brightness
    @State private var lookRevision = 0
    @State private var canvasHandle = PhotoCropCanvasHandle()
    @Namespace private var toolNamespace
    @Namespace private var aspectNamespace

    init(
        image: UIImage,
        mask: PhotoCropMask,
        initialAspect: PhotoCropAspect = .original,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (UIImage) -> Void
    ) {
        let normalized = image.fixedOrientation()
        self.image = image
        self.mask = mask
        self.initialAspect = initialAspect
        self.onCancel = onCancel
        self.onComplete = onComplete
        _aspect = State(initialValue: mask == .circle ? .square : initialAspect)
        _baseImage = State(initialValue: normalized)
        _tool = State(initialValue: .crop)
    }

    var body: some View {
        GeometryReader { geo in
            let chromeTop: CGFloat = 52
            let chromeBottom: CGFloat = usesTickRuler ? 204 : 168
            let inset: CGFloat = mask == .circle ? 28 : 20
            let available = CGSize(
                width: max(1, geo.size.width - inset * 2),
                height: max(1, geo.size.height - chromeTop - chromeBottom - inset)
            )
            let cropSize: CGSize = {
                if mask == .circle {
                    let side = floor(min(available.width, available.height))
                    return CGSize(width: side, height: side)
                }
                return Self.cropFrameSize(
                    in: available,
                    imageSize: baseImage.size,
                    aspect: aspect,
                    mask: mask
                )
            }()

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    toolbar
                        .frame(height: chromeTop)

                    Spacer(minLength: 0)

                    canvas(cropSize: cropSize, available: available)
                        .frame(width: available.width, height: available.height)
                        .clipped()
                        .animation(Self.cropSpring, value: aspect)

                    Spacer(minLength: 0)

                    bottomChrome
                        .frame(height: chromeBottom)
                }
            }
            .onAppear {
                if viewportSize == .zero {
                    viewportSize = cropSize
                }
            }
            .onChange(of: cropSize.width) { _, _ in
                syncViewport(to: cropSize)
            }
            .onChange(of: cropSize.height) { _, _ in
                syncViewport(to: cropSize)
            }
            .onChange(of: aspect) { _, _ in
                withAnimation(Self.cropSpring) {
                    scale = 1
                    offset = .zero
                    viewportSize = cropSize
                }
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onChange(of: tool) { _, _ in
            commitLiveLook()
        }
        .onChange(of: selectedAdjust) { _, _ in
            commitLiveLook()
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.body)
                .foregroundStyle(.white)

            Spacer()

            Text(mask == .circle ? "Profile Photo" : "Edit")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Button("Done") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onComplete(renderFinalImage())
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
    }

    private func canvas(cropSize: CGSize, available: CGSize) -> some View {
        let shape: AnyShape = mask == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        return ZStack {
            PhotoCropInteractiveCanvas(
                image: baseImage,
                cropSize: cropSize,
                adjustments: adjustments,
                straightenDegrees: straightenDegrees,
                lookRevision: lookRevision,
                handle: canvasHandle,
                scale: $scale,
                offset: $offset
            )

            cropWindowOverlay(cropSize: cropSize, available: available, shape: shape)
        }
        .frame(width: available.width, height: available.height)
    }

    private func cropWindowOverlay(cropSize: CGSize, available: CGSize, shape: AnyShape) -> some View {
        ZStack {
            dimmingPath(available: available, cropSize: cropSize)
                .fill(Color.black.opacity(0.52), style: FillStyle(eoFill: true))

            if tool == .crop || tool == .rotate, mask == .rectangle {
                gridOverlay(size: cropSize)
                    .frame(width: cropSize.width, height: cropSize.height)
            }

            shape
                .stroke(.white.opacity(0.95), lineWidth: mask == .circle ? 2 : 1.25)
                .frame(width: cropSize.width, height: cropSize.height)
        }
        .allowsHitTesting(false)
    }

    private func dimmingPath(available: CGSize, cropSize: CGSize) -> Path {
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: available))
        let hole = CGRect(
            x: (available.width - cropSize.width) / 2,
            y: (available.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        )
        if mask == .circle {
            path.addEllipse(in: hole)
        } else {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14))
        }
        return path
    }

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            toolPanel
                .frame(height: usesTickRuler ? 108 : 72)
                .animation(Self.cropSpring, value: tool)

            toolPicker
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch tool {
        case .crop:
            if mask == .rectangle {
                aspectPicker
            } else {
                Text("Move and scale")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .rotate:
            rotatePanel
        case .adjust:
            adjustPanel
        }
    }

    private var usesTickRuler: Bool {
        tool == .rotate || tool == .adjust
    }

    private var toolPicker: some View {
        HStack(spacing: 28) {
            ForEach(PhotoEditorTool.allCases) { item in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    if tool == item {
                        resetActiveTool()
                        return
                    }
                    withAnimation(Self.cropSpring) {
                        tool = item
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(tool == item ? .white : .white.opacity(0.45))
                    .frame(width: 64)
                    .overlay(alignment: .top) {
                        if tool == item {
                            Capsule()
                                .fill(.white)
                                .frame(width: 18, height: 3)
                                .offset(y: -8)
                                .matchedGeometryEffect(id: "toolDot", in: toolNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aspectPickerOptions: [PhotoCropAspect] {
        var options = PhotoCropAspect.pickerCases
        if !options.contains(aspect) {
            options.insert(aspect, at: 0)
        }
        return options
    }

    private var aspectPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(aspectPickerOptions) { option in
                    let selected = aspect == option
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(Self.cropSpring) {
                            aspect = option
                        }
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .foregroundStyle(selected ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(.white)
                                        .matchedGeometryEffect(id: "aspectSelection", in: aspectNamespace)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var rotatePanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                rotateAction("Rotate", systemImage: "rotate.right") {
                    baseImage = PhotoEditRenderer.rotate90Clockwise(baseImage)
                    resetCropTransform()
                }
                rotateAction("Flip H", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    baseImage = PhotoEditRenderer.flipHorizontal(baseImage)
                }
                rotateAction("Flip V", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                    baseImage = PhotoEditRenderer.flipVertical(baseImage)
                }
            }

            TickRuler(
                value: Double(straightenDegrees),
                range: -45...45,
                step: 1,
                pointsPerUnit: 10
            ) { value in
                setStraightenLive(CGFloat(value))
            } onEnded: { value in
                setStraightenLive(CGFloat(value))
            } onReset: {
                resetStraighten()
            }
            .frame(height: 52)
            .padding(.horizontal, 8)
        }
    }

    private func rotateAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 72, height: 44)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var adjustPanel: some View {
        VStack(spacing: 6) {
            TickRuler(
                value: selectedAdjust.displayValue(currentAdjustValue),
                range: -100...100,
                step: 1,
                pointsPerUnit: 8
            ) { value in
                applyAdjustDisplay(value, commit: false)
            } onEnded: { value in
                applyAdjustDisplay(value, commit: true)
            } onReset: {
                resetSelectedAdjust()
            }
            .frame(height: 52)
            .padding(.horizontal, 8)
            .id(selectedAdjust)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(AdjustParameter.allCases) { parameter in
                        adjustIcon(parameter)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func adjustIcon(_ parameter: AdjustParameter) -> some View {
        let selected = selectedAdjust == parameter
        let dirty = !parameter.isAtIdentity(storedValue(for: parameter))
        let accent = PhotoEditAccent.yellow
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if selected {
                if dirty {
                    resetSelectedAdjust()
                }
                return
            }
            withAnimation(Self.cropSpring) {
                selectedAdjust = parameter
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            dirty ? accent : Color.white.opacity(selected ? 0.95 : 0.28),
                            lineWidth: selected || dirty ? 2 : 1
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: parameter.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(dirty ? accent : (selected ? Color.white : Color.white.opacity(0.55)))
                }
                Text(parameter.title)
                    .font(.caption2.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
    }

    private var currentAdjustValue: Double {
        switch selectedAdjust {
        case .brightness: return adjustments.brightness
        case .contrast: return adjustments.contrast
        case .saturation: return adjustments.saturation
        case .exposure: return adjustments.exposure
        case .warmth: return adjustments.warmth
        }
    }

    private func setAdjustValue(_ value: Double, on adjustments: inout PhotoAdjustments) {
        switch selectedAdjust {
        case .brightness: adjustments.brightness = value
        case .contrast: adjustments.contrast = value
        case .saturation: adjustments.saturation = value
        case .exposure: adjustments.exposure = value
        case .warmth: adjustments.warmth = value
        }
    }

    private func storedValue(for parameter: AdjustParameter) -> Double {
        switch parameter {
        case .brightness: return adjustments.brightness
        case .contrast: return adjustments.contrast
        case .saturation: return adjustments.saturation
        case .exposure: return adjustments.exposure
        case .warmth: return adjustments.warmth
        }
    }

    private func resetActiveTool() {
        switch tool {
        case .crop:
            break
        case .rotate:
            resetRotateEdits()
        case .adjust:
            resetSelectedAdjust()
        }
    }

    private func resetRotateEdits() {
        baseImage = image.fixedOrientation()
        resetStraighten()
        resetCropTransform()
    }

    private func resetStraighten() {
        setStraightenLive(0)
        lookRevision += 1
    }

    private func applyAdjustDisplay(_ display: Double, commit: Bool) {
        let stored = selectedAdjust.storedValue(from: display)
        var next = adjustments
        setAdjustValue(stored, on: &next)
        canvasHandle.view?.setLook(adjustments: next, straighten: straightenDegrees)
        guard commit else { return }
        setAdjustValue(stored, on: &adjustments)
        commitLiveLook()
    }

    private func resetSelectedAdjust() {
        setAdjustValue(selectedAdjust.identity, on: &adjustments)
        lookRevision += 1
        canvasHandle.view?.setLook(adjustments: adjustments, straighten: straightenDegrees)
    }

    private func commitLiveLook() {
        guard let look = canvasHandle.view?.currentLook() else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            adjustments = look.adjustments
            straightenDegrees = look.straighten
        }
    }

    private func setStraightenLive(_ value: CGFloat) {
        canvasHandle.view?.setLook(adjustments: adjustments, straighten: value)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            straightenDegrees = value
        }
    }

    private func gridOverlay(size: CGSize) -> some View {
        Path { path in
            let w = size.width
            let h = size.height
            path.move(to: CGPoint(x: w / 3, y: 0))
            path.addLine(to: CGPoint(x: w / 3, y: h))
            path.move(to: CGPoint(x: 2 * w / 3, y: 0))
            path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
            path.move(to: CGPoint(x: 0, y: h / 3))
            path.addLine(to: CGPoint(x: w, y: h / 3))
            path.move(to: CGPoint(x: 0, y: 2 * h / 3))
            path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
        }
        .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
    }

    private func resetCropTransform() {
        withAnimation(Self.cropSpring) {
            scale = 1
            offset = .zero
        }
    }

    private func applyClampedOffset(cropSize: CGSize) {
        let next = Self.clampOffset(
            offset,
            scale: scale,
            cropSize: cropSize,
            imageSize: baseImage.size,
            straightenDegrees: straightenDegrees
        )
        guard next != offset else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = next
        }
    }

    private func syncViewport(to cropSize: CGSize) {
        let delta = abs(cropSize.width - viewportSize.width) + abs(cropSize.height - viewportSize.height)
        guard delta > 1.5 else { return }
        viewportSize = cropSize
        applyClampedOffset(cropSize: cropSize)
    }

    private func renderFinalImage() -> UIImage {
        commitLiveLook()
        let export = canvasHandle.view?.currentExportState()
        if let export {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                adjustments = export.adjustments
                straightenDegrees = export.straighten
                scale = export.scale
                offset = export.offset
            }
        }
        let adjusted = PhotoEditRenderer.apply(
            to: baseImage,
            adjustments: export?.adjustments ?? adjustments,
            maxPixelSize: 2048
        )
        let cropSize = viewportSize == .zero
            ? CGSize(width: 1080, height: 1080)
            : viewportSize
        return Self.crop(
            image: adjusted,
            cropSize: cropSize,
            scale: export?.scale ?? scale,
            offset: export?.offset ?? offset,
            straightenDegrees: export?.straighten ?? straightenDegrees
        )
    }

    // MARK: - Geometry

    static let cropSpring = Animation.spring(response: 0.34, dampingFraction: 0.88)

    static func cropFrameSize(
        in available: CGSize,
        imageSize: CGSize,
        aspect: PhotoCropAspect,
        mask: PhotoCropMask
    ) -> CGSize {
        let ratio: CGFloat
        if mask == .circle {
            ratio = 1
        } else if let r = aspect.ratio {
            ratio = r
        } else if imageSize.height > 0 {
            ratio = imageSize.width / imageSize.height
        } else {
            ratio = 1
        }

        var width = available.width
        var height = width / ratio
        if height > available.height {
            height = available.height
            width = height * ratio
        }
        return CGSize(width: max(1, floor(width)), height: max(1, floor(height)))
    }

    static func aspectFillSize(_ imageSize: CGSize, into bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func straightenCoverScale(
        degrees: CGFloat,
        imageSize: CGSize,
        cropSize: CGSize
    ) -> CGFloat {
        guard abs(degrees) > 0.05,
              imageSize.width > 0,
              imageSize.height > 0,
              cropSize.width > 0,
              cropSize.height > 0 else {
            return 1
        }
        let filled = aspectFillSize(imageSize, into: cropSize)
        let radians = degrees * .pi / 180
        let cosT = cos(radians)
        let sinT = sin(radians)
        let hw = cropSize.width / 2
        let hh = cropSize.height / 2
        let imgHw = max(filled.width / 2, 0.5)
        let imgHh = max(filled.height / 2, 0.5)
        var needed: CGFloat = 1
        let samples = [
            CGPoint(x: hw, y: hh),
            CGPoint(x: hw, y: -hh),
        ]
        for point in samples {
            let x = abs(point.x * cosT + point.y * sinT)
            let y = abs(-point.x * sinT + point.y * cosT)
            needed = max(needed, x / imgHw, y / imgHh)
        }
        return needed
    }

    static func clampOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        cropSize: CGSize,
        imageSize: CGSize,
        straightenDegrees: CGFloat = 0
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let cover = straightenCoverScale(
            degrees: straightenDegrees,
            imageSize: imageSize,
            cropSize: cropSize
        )
        let totalScale = scale * cover
        if abs(straightenDegrees) < 0.05 {
            let filled = aspectFillSize(imageSize, into: cropSize)
            let maxX = max(0, (filled.width * totalScale - cropSize.width) / 2)
            let maxY = max(0, (filled.height * totalScale - cropSize.height) / 2)
            return CGSize(
                width: min(max(proposed.width, -maxX), maxX),
                height: min(max(proposed.height, -maxY), maxY)
            )
        }
        if offsetFits(
            proposed,
            scale: scale,
            cropSize: cropSize,
            imageSize: imageSize,
            straightenDegrees: straightenDegrees
        ) {
            return proposed
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<18 {
            let mid = (low + high) / 2
            let trial = CGSize(width: proposed.width * mid, height: proposed.height * mid)
            if offsetFits(
                trial,
                scale: scale,
                cropSize: cropSize,
                imageSize: imageSize,
                straightenDegrees: straightenDegrees
            ) {
                low = mid
            } else {
                high = mid
            }
        }
        return CGSize(width: proposed.width * low, height: proposed.height * low)
    }

    static func offsetFits(
        _ offset: CGSize,
        scale: CGFloat,
        cropSize: CGSize,
        imageSize: CGSize,
        straightenDegrees: CGFloat
    ) -> Bool {
        let cover = straightenCoverScale(
            degrees: straightenDegrees,
            imageSize: imageSize,
            cropSize: cropSize
        )
        let totalScale = max(scale * cover, 0.0001)
        let filled = aspectFillSize(imageSize, into: cropSize)
        let imgHw = filled.width / 2
        let imgHh = filled.height / 2
        let radians = straightenDegrees * .pi / 180
        let cosT = cos(radians)
        let sinT = sin(radians)
        let hw = cropSize.width / 2
        let hh = cropSize.height / 2
        let corners = [
            CGPoint(x: hw, y: hh),
            CGPoint(x: hw, y: -hh),
            CGPoint(x: -hw, y: hh),
            CGPoint(x: -hw, y: -hh),
        ]
        let epsilon: CGFloat = 0.75
        for point in corners {
            let dx = point.x - offset.width
            let dy = point.y - offset.height
            let x = (dx * cosT + dy * sinT) / totalScale
            let y = (-dx * sinT + dy * cosT) / totalScale
            if abs(x) > imgHw + epsilon || abs(y) > imgHh + epsilon {
                return false
            }
        }
        return true
    }

    static func crop(
        image: UIImage,
        cropSize: CGSize,
        scale: CGFloat,
        offset: CGSize,
        straightenDegrees: CGFloat = 0
    ) -> UIImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        let cover = straightenCoverScale(
            degrees: straightenDegrees,
            imageSize: imageSize,
            cropSize: cropSize
        )
        let totalScale = scale * cover
        let filled = aspectFillSize(imageSize, into: cropSize)
        guard filled.width > 0, filled.height > 0 else { return image }
        let viewToImage = imageSize.width / filled.width
        let outputSize = CGSize(
            width: max(1, (cropSize.width * viewToImage).rounded()),
            height: max(1, (cropSize.height * viewToImage).rounded())
        )
        let radians = straightenDegrees * .pi / 180

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: outputSize))
            context.cgContext.translateBy(
                x: outputSize.width / 2 + offset.width * viewToImage,
                y: outputSize.height / 2 + offset.height * viewToImage
            )
            context.cgContext.rotate(by: radians)
            context.cgContext.scaleBy(x: totalScale, y: totalScale)
            image.draw(in: CGRect(
                x: -imageSize.width / 2,
                y: -imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            ))
        }
    }
}

private enum AdjustParameter: String, CaseIterable, Identifiable {
    case brightness, contrast, saturation, exposure, warmth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .exposure: return "Exposure"
        case .warmth: return "Warmth"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness: return -0.4...0.4
        case .contrast: return 0.6...1.5
        case .saturation: return 0...2
        case .exposure: return -1.2...1.2
        case .warmth: return -1...1
        }
    }

    var identity: Double {
        switch self {
        case .brightness, .exposure, .warmth: return 0
        case .contrast, .saturation: return 1
        }
    }

    var systemImage: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop"
        case .exposure: return "plusminus.circle"
        case .warmth: return "thermometer.medium"
        }
    }

    func isAtIdentity(_ stored: Double) -> Bool {
        abs(stored - identity) < 0.001
    }

    func displayValue(_ stored: Double) -> Double {
        if stored >= identity {
            let span = range.upperBound - identity
            return span <= 0 ? 0 : ((stored - identity) / span) * 100
        }
        let span = identity - range.lowerBound
        return span <= 0 ? 0 : ((stored - identity) / span) * 100
    }

    func storedValue(from display: Double) -> Double {
        if display >= 0 {
            return identity + (display / 100) * (range.upperBound - identity)
        }
        return identity + (display / 100) * (identity - range.lowerBound)
    }
}

private enum PhotoEditAccent {
    static let yellow = Color(red: 1, green: 0.78, blue: 0.16)
}

private struct AnyShape: Shape {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

// MARK: - Interactive canvas

private final class PhotoCropCanvasHandle {
    weak var view: PhotoCropCanvasUIView?
}

/// UIKit pan/pinch so releasing a finger never snaps back through SwiftUI `GestureState`.
private struct PhotoCropInteractiveCanvas: UIViewRepresentable {
    var image: UIImage
    var cropSize: CGSize
    var adjustments: PhotoAdjustments
    var straightenDegrees: CGFloat
    var lookRevision: Int
    var handle: PhotoCropCanvasHandle
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PhotoCropCanvasUIView {
        let view = PhotoCropCanvasUIView()
        handle.view = view
        context.coordinator.bind(scale: $scale, offset: $offset)
        context.coordinator.appliedLookRevision = lookRevision
        view.onCommit = { [weak view, coordinator = context.coordinator] nextScale, nextOffset in
            guard view?.window != nil else { return }
            coordinator.commit(scale: nextScale, offset: nextOffset)
        }
        view.setCropSize(cropSize)
        view.setSource(image)
        view.setLook(adjustments: adjustments, straighten: straightenDegrees)
        view.syncTransform(scale: scale, offset: offset, animated: false)
        return view
    }

    func updateUIView(_ view: PhotoCropCanvasUIView, context: Context) {
        handle.view = view
        context.coordinator.bind(scale: $scale, offset: $offset)
        view.onCommit = { [weak view, coordinator = context.coordinator] nextScale, nextOffset in
            guard view?.window != nil else { return }
            coordinator.commit(scale: nextScale, offset: nextOffset)
        }
        view.setCropSize(cropSize)
        view.setSource(image)
        if lookRevision != context.coordinator.appliedLookRevision {
            context.coordinator.appliedLookRevision = lookRevision
            view.setLook(adjustments: adjustments, straighten: straightenDegrees)
        }
        if !view.isBusy {
            view.syncTransform(
                scale: scale,
                offset: offset,
                animated: context.transaction.animation != nil
            )
        }
    }

    final class Coordinator {
        var appliedLookRevision = -1
        private var scale: Binding<CGFloat> = .constant(1)
        private var offset: Binding<CGSize> = .constant(.zero)

        func bind(scale: Binding<CGFloat>, offset: Binding<CGSize>) {
            self.scale = scale
            self.offset = offset
        }

        func commit(scale: CGFloat, offset: CGSize) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.scale.wrappedValue = scale
                self.offset.wrappedValue = offset
            }
        }
    }
}

private final class PhotoCropCanvasUIView: UIView, UIGestureRecognizerDelegate {
    var onCommit: ((CGFloat, CGSize) -> Void)?

    private let imageView = UIImageView()
    private let previewQueue = DispatchQueue(label: "take.photo-crop.preview", qos: .userInteractive)
    private var sourceImage: UIImage?
    private var sourceImageSize: CGSize = .zero
    private var cropSize: CGSize = .zero
    /// Downscaled CPU bitmap for Adjust sliders (no Core Image / Metal).
    private var previewCGImage: CGImage?
    private var displayImageScale: CGFloat = 3
    private var adjustments = PhotoAdjustments()
    private var straighten: CGFloat = 0
    private var lookGeneration = 0
    private var isRenderingLook = false
    private var hasPendingLook = false
    private var lastLayoutSize: CGSize = .zero
    private var scale: CGFloat = 1
    private var offset: CGSize = .zero
    private var activeGestures = 0
    private var isSettling = false
    private var settleGeneration = 0
    private var lastPanTranslation: CGPoint = .zero
    private var lastPinchScale: CGFloat = 1
    private var lastPanVelocity: CGPoint = .zero

    var isBusy: Bool { activeGestures > 0 || isSettling }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        clipsToBounds = true

        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = false
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.delegate = self
        pan.maximumNumberOfTouches = 2
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageView()
        let sizeChanged = abs(lastLayoutSize.width - bounds.width) > 2
            || abs(lastLayoutSize.height - bounds.height) > 2
        if sizeChanged, bounds.width > 1, bounds.height > 1 {
            lastLayoutSize = bounds.size
            rebuildPreviewBitmap()
            renderLook()
            clampInPlace()
            applyTransform()
        }
    }

    func currentLook() -> (adjustments: PhotoAdjustments, straighten: CGFloat) {
        (adjustments, straighten)
    }

    func currentExportState() -> (
        adjustments: PhotoAdjustments,
        straighten: CGFloat,
        scale: CGFloat,
        offset: CGSize
    ) {
        (adjustments, straighten, scale, offset)
    }

    func setCropSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let delta = abs(cropSize.width - size.width) + abs(cropSize.height - size.height)
        guard delta > 0.5 else { return }
        cropSize = size
        rebuildPreviewBitmap()
        layoutImageView()
        clampInPlace()
        applyTransform()
    }

    func setSource(_ image: UIImage) {
        guard sourceImage !== image else { return }
        let bitmap = image.photoCropBitmapImage()
        sourceImage = bitmap
        sourceImageSize = bitmap.size
        // Show pixels immediately so a failed/slow filter path never leaves a black frame.
        imageView.image = bitmap
        rebuildPreviewBitmap()
        layoutImageView()
        renderLook()
        clampInPlace()
        applyTransform()
    }

    func setLook(adjustments: PhotoAdjustments, straighten: CGFloat) {
        let filtersChanged = adjustments != self.adjustments
        self.adjustments = adjustments
        self.straighten = straighten
        if filtersChanged {
            renderLook()
        }
        clampInPlace()
        applyTransform()
    }

    func syncTransform(scale: CGFloat, offset: CGSize, animated: Bool) {
        let scaleDelta = abs(self.scale - scale)
        let offsetDelta = hypot(self.offset.width - offset.width, self.offset.height - offset.height)
        guard scaleDelta > 0.002 || offsetDelta > 0.5 else { return }
        self.scale = scale
        self.offset = offset
        clampInPlace()
        if animated {
            settle(to: self.scale, offset: self.offset, commit: false)
        } else {
            applyTransform()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginGesture()
            lastPanTranslation = .zero
            lastPanVelocity = .zero
        case .changed:
            let translation = gesture.translation(in: self)
            offset.width += translation.x - lastPanTranslation.x
            offset.height += translation.y - lastPanTranslation.y
            lastPanTranslation = translation
            lastPanVelocity = gesture.velocity(in: self)
            clampInPlace()
            applyTransform()
        case .ended, .cancelled, .failed:
            lastPanVelocity = gesture.velocity(in: self)
            lastPanTranslation = .zero
            endGesture()
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginGesture()
            lastPinchScale = 1
        case .changed:
            let incremental = gesture.scale / max(lastPinchScale, 0.0001)
            lastPinchScale = gesture.scale
            let rawScale = scale * incremental
            let nextScale = min(
                max(rawScale, PhotoCropEditorView.minimumCropScale),
                PhotoCropEditorView.maximumCropScale
            )
            applyScale(nextScale, around: gesture.location(in: self))
            clampInPlace()
            applyTransform()
        case .ended, .cancelled, .failed:
            lastPinchScale = 1
            endGesture()
        default:
            break
        }
    }

    private func beginGesture() {
        settleGeneration += 1
        if isSettling {
            capturePresentationTransform()
            imageView.layer.removeAllAnimations()
            isSettling = false
        }
        activeGestures += 1
    }

    private func endGesture() {
        activeGestures = max(0, activeGestures - 1)
        guard activeGestures == 0 else { return }
        let target = settledTransform()
        scale = target.scale
        offset = target.offset
        onCommit?(target.scale, target.offset)
        settle(to: target.scale, offset: target.offset, commit: false)
    }

    private func settledTransform() -> (scale: CGFloat, offset: CGSize) {
        let targetScale = min(
            max(scale, PhotoCropEditorView.minimumCropScale),
            PhotoCropEditorView.maximumCropScale
        )
        var targetOffset = CGSize(
            width: offset.width + lastPanVelocity.x * 0.16,
            height: offset.height + lastPanVelocity.y * 0.16
        )
        lastPanVelocity = .zero
        targetOffset = PhotoCropEditorView.clampOffset(
            targetOffset,
            scale: targetScale,
            cropSize: activeCropSize,
            imageSize: sourceImageSize,
            straightenDegrees: straighten
        )
        return (targetScale, targetOffset)
    }

    private func settle(to targetScale: CGFloat, offset targetOffset: CGSize, commit: Bool) {
        let start = imageView.transform
        let end = currentTransform(scale: targetScale, offset: targetOffset)
        scale = targetScale
        offset = targetOffset
        if commit {
            onCommit?(targetScale, targetOffset)
        }
        let same = abs(start.a - end.a) < 0.002
            && abs(start.b - end.b) < 0.002
            && abs(start.tx - end.tx) < 0.5
            && abs(start.ty - end.ty) < 0.5
        if same {
            imageView.transform = end
            isSettling = false
            return
        }
        settleGeneration += 1
        let generation = settleGeneration
        isSettling = true
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.imageView.transform = end
        } completion: { [weak self] finished in
            guard let self, generation == self.settleGeneration else { return }
            if finished {
                self.isSettling = false
            }
        }
    }

    private func capturePresentationTransform() {
        let presented = imageView.layer.presentation()?.affineTransform() ?? imageView.transform
        let totalScale = max(hypot(presented.a, presented.c), 0.01)
        let cover = PhotoCropEditorView.straightenCoverScale(
            degrees: straighten,
            imageSize: sourceImageSize,
            cropSize: activeCropSize
        )
        scale = max(totalScale / cover, PhotoCropEditorView.minimumCropScale)
        offset = CGSize(width: presented.tx, height: presented.ty)
        imageView.transform = presented
        clampInPlace()
    }

    private func applyTransform() {
        imageView.transform = currentTransform(scale: scale, offset: offset)
    }

    private func applyScale(_ newScale: CGFloat, around location: CGPoint) {
        let previous = max(scale, 0.0001)
        let factor = newScale / previous
        // Uniform T·R·S: a view point stays put with offset' = p - factor * (p - offset).
        let point = CGPoint(x: location.x - bounds.midX, y: location.y - bounds.midY)
        let rotatedDelta = CGPoint(
            x: point.x - offset.width,
            y: point.y - offset.height
        )
        offset = CGSize(
            width: point.x - rotatedDelta.x * factor,
            height: point.y - rotatedDelta.y * factor
        )
        scale = newScale
    }

    private func clampInPlace() {
        scale = min(
            max(scale, PhotoCropEditorView.minimumCropScale),
            PhotoCropEditorView.maximumCropScale
        )
        offset = PhotoCropEditorView.clampOffset(
            offset,
            scale: scale,
            cropSize: activeCropSize,
            imageSize: sourceImageSize,
            straightenDegrees: straighten
        )
    }

    private var activeCropSize: CGSize {
        cropSize.width > 1 ? cropSize : bounds.size
    }

    private func currentTransform(scale: CGFloat, offset: CGSize) -> CGAffineTransform {
        let cover = PhotoCropEditorView.straightenCoverScale(
            degrees: straighten,
            imageSize: sourceImageSize,
            cropSize: activeCropSize
        )
        let total = scale * cover
        let radians = straighten * .pi / 180
        return CGAffineTransform(translationX: offset.width, y: offset.height)
            .rotated(by: radians)
            .scaledBy(x: total, y: total)
    }

    private func layoutImageView() {
        let filled = PhotoCropEditorView.aspectFillSize(sourceImageSize, into: activeCropSize)
        let current = imageView.transform
        imageView.transform = .identity
        imageView.bounds = CGRect(origin: .zero, size: filled == .zero ? activeCropSize : filled)
        imageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        imageView.transform = current
    }

    private func rebuildPreviewBitmap() {
        guard let sourceImage, activeCropSize.width > 1, activeCropSize.height > 1 else { return }
        let filled = PhotoCropEditorView.aspectFillSize(sourceImageSize, into: activeCropSize)
        let screen = window?.screen.scale ?? UIScreen.main.scale
        displayImageScale = screen
        var pixel = CGSize(width: filled.width * screen, height: filled.height * screen)
        let longest = max(pixel.width, pixel.height)
        // Keep Adjust previews cheap on CPU (no Metal).
        if longest > 720 {
            let shrink = 720 / longest
            pixel = CGSize(width: pixel.width * shrink, height: pixel.height * shrink)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: max(pixel.width, 1), height: max(pixel.height, 1))
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let preview = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: size))
        }
        previewCGImage = preview.cgImage
    }

    private func renderLook() {
        // Identity filters: keep the full bitmap (straighten is a view transform).
        if adjustments.isIdentity {
            if let sourceImage {
                imageView.image = sourceImage
            }
            return
        }
        guard let previewCGImage else {
            rebuildPreviewBitmap()
            guard let previewCGImage else { return }
            applyAdjustmentsAsync(previewCGImage)
            return
        }
        applyAdjustmentsAsync(previewCGImage)
    }

    private func applyAdjustmentsAsync(_ preview: CGImage) {
        guard !isRenderingLook else {
            hasPendingLook = true
            return
        }
        isRenderingLook = true
        lookGeneration += 1
        let generation = lookGeneration
        let adjustments = self.adjustments
        let screenScale = displayImageScale
        let fallback = sourceImage
        previewQueue.async {
            let cgImage = PhotoEditRenderer.applyCPU(to: preview, adjustments: adjustments)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRenderingLook = false
                if generation == self.lookGeneration {
                    if let cgImage {
                        self.imageView.image = UIImage(cgImage: cgImage, scale: screenScale, orientation: .up)
                    } else if let fallback {
                        self.imageView.image = fallback
                    }
                }
                if self.hasPendingLook {
                    self.hasPendingLook = false
                    self.renderLook()
                }
            }
        }
    }

    }

private extension UIImage {
    /// Flatten orientation / decode into a CGImage-backed bitmap CI can consume reliably.
    func photoCropBitmapImage() -> UIImage {
        if let cgImage, imageOrientation == .up, cgImage.width > 0, cgImage.height > 0 {
            return self
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct TickRuler: UIViewRepresentable {
    var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var pointsPerUnit: CGFloat = 10
    var onChanging: (Double) -> Void
    var onEnded: (Double) -> Void
    var onReset: () -> Void

    func makeUIView(context: Context) -> StraightenRulerUIView {
        let view = StraightenRulerUIView()
        view.minimumValue = range.lowerBound
        view.maximumValue = range.upperBound
        view.step = step
        view.pointsPerUnit = pointsPerUnit
        view.onChanging = onChanging
        view.onEnded = onEnded
        view.onReset = onReset
        return view
    }

    func updateUIView(_ view: StraightenRulerUIView, context: Context) {
        view.minimumValue = range.lowerBound
        view.maximumValue = range.upperBound
        view.step = step
        view.pointsPerUnit = pointsPerUnit
        view.onChanging = onChanging
        view.onEnded = onEnded
        view.onReset = onReset
        if !view.isTracking {
            view.setValue(value, animated: false)
        }
    }
}

private final class StraightenRulerUIView: UIView, UIScrollViewDelegate {
    var minimumValue: Double = -45
    var maximumValue: Double = 45
    var onChanging: (Double) -> Void = { _ in }
    var onEnded: (Double) -> Void = { _ in }
    var onReset: () -> Void = {}
    var step: Double = 1
    var pointsPerUnit: CGFloat = 10
    private(set) var isTracking = false
    private(set) var currentValue: Double = 0
    private var didCenterInitialValue = false

    private let scrollView = UIScrollView()
    private let ticksView = StraightenTicksView()
    private let centerLine = UIView()
    private let badge = UIButton(type: .system)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let zeroFeedback = UIImpactFeedbackGenerator(style: .light)
    private var lastHapticDegree = 0
    private var ignoreScrollCallbacks = false
    private var isProgrammaticScroll = false
    private var lastLayoutWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.decelerationRate = .fast
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)
        scrollView.addSubview(ticksView)

        ticksView.backgroundColor = .clear
        ticksView.isOpaque = false

        centerLine.backgroundColor = UIColor(red: 1, green: 0.78, blue: 0.16, alpha: 1)
        centerLine.isUserInteractionEnabled = false
        addSubview(centerLine)

        badge.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        badge.setTitleColor(.black, for: .normal)
        badge.backgroundColor = UIColor(red: 1, green: 0.78, blue: 0.16, alpha: 1)
        badge.layer.cornerRadius = 16
        badge.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        badge.isHidden = true
        addSubview(badge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1 else { return }
        ignoreScrollCallbacks = true
        scrollView.frame = CGRect(x: 0, y: 20, width: bounds.width, height: max(0, bounds.height - 20))
        let span = CGFloat(maximumValue - minimumValue)
        let contentWidth = span * pointsPerUnit
        ticksView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: scrollView.bounds.height)
        ticksView.minimumValue = minimumValue
        ticksView.maximumValue = maximumValue
        ticksView.pointsPerDegree = pointsPerUnit
        ticksView.setNeedsDisplay()
        scrollView.contentSize = ticksView.frame.size
        let inset = bounds.width / 2
        scrollView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        scrollView.contentOffset.y = 0
        ignoreScrollCallbacks = false
        centerLine.frame = CGRect(
            x: bounds.midX - 0.75,
            y: 24,
            width: 1.5,
            height: max(0, scrollView.bounds.height - 10)
        )
        badge.frame = CGRect(x: bounds.midX - 16, y: 0, width: 32, height: 32)
        let widthChanged = abs(lastLayoutWidth - bounds.width) > 0.5
        lastLayoutWidth = bounds.width
        if !isTracking, !isProgrammaticScroll, widthChanged || !didCenterInitialValue {
            didCenterInitialValue = true
            setValue(currentValue, animated: false)
        }
    }

    func setValue(_ value: Double, animated: Bool) {
        let clamped = min(max(value, minimumValue), maximumValue)
        currentValue = clamped
        let offsetX = CGFloat(clamped - minimumValue) * pointsPerUnit - scrollView.contentInset.left
        let alreadyThere = abs(scrollView.contentOffset.x - offsetX) < 0.5
        if alreadyThere || !animated {
            ignoreScrollCallbacks = true
            scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: false)
            ignoreScrollCallbacks = false
            isProgrammaticScroll = false
        } else {
            isProgrammaticScroll = true
            scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
        }
        ticksView.highlightedDegree = Int(clamped.rounded())
        updateBadge()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
        ignoreScrollCallbacks = false
        isTracking = true
        selectionFeedback.prepare()
        zeroFeedback.prepare()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !ignoreScrollCallbacks, !isProgrammaticScroll else { return }
        let raw = Double((scrollView.contentOffset.x + scrollView.contentInset.left) / pointsPerUnit)
            + minimumValue
        let snapped = snap(raw)
        if snapped != currentValue {
            let degree = Int(snapped)
            if degree != lastHapticDegree {
                if degree == 0 {
                    zeroFeedback.impactOccurred()
                } else {
                    selectionFeedback.selectionChanged()
                    selectionFeedback.prepare()
                }
                lastHapticDegree = degree
            }
            currentValue = snapped
            ticksView.highlightedDegree = degree
            updateBadge()
            onChanging(snapped)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            finishTracking()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishTracking()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
    }

    private func finishTracking() {
        isTracking = false
        setValue(currentValue, animated: false)
        onEnded(currentValue)
    }

    private func snap(_ value: Double) -> Double {
        let clamped = min(max(value, minimumValue), maximumValue)
        guard step > 0 else { return clamped }
        return min(max((clamped / step).rounded() * step, minimumValue), maximumValue)
    }

    @objc private func resetTapped() {
        setValue(0, animated: true)
        onReset()
        onEnded(0)
    }

    private func updateBadge() {
        let rounded = Int(currentValue.rounded())
        badge.isHidden = false
        badge.setTitle("\(rounded)", for: .normal)
        let isNeutral = abs(currentValue) < 0.5
        badge.backgroundColor = isNeutral
            ? UIColor.white.withAlphaComponent(0.18)
            : UIColor(red: 1, green: 0.78, blue: 0.16, alpha: 1)
        badge.setTitleColor(isNeutral ? .white : .black, for: .normal)
        badge.isEnabled = !isNeutral
    }
}

private final class StraightenTicksView: UIView {
    var minimumValue: Double = -45
    var maximumValue: Double = 45
    var pointsPerDegree: CGFloat = 10
    var highlightedDegree: Int = 0 {
        didSet {
            if oldValue != highlightedDegree {
                setNeedsDisplay()
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let minDegree = Int(minimumValue.rounded())
        let maxDegree = Int(maximumValue.rounded())
        for degree in minDegree...maxDegree {
            let x = CGFloat(degree - minDegree) * pointsPerDegree
            let isMajor = degree % 10 == 0
            let isMid = degree % 5 == 0
            let isCurrent = degree == highlightedDegree
            let height: CGFloat = isMajor ? 18 : (isMid ? 12 : 7)
            let color: UIColor
            if isCurrent && degree != 0 {
                color = UIColor(red: 1, green: 0.78, blue: 0.16, alpha: 1)
            } else if degree == 0 {
                color = UIColor.white.withAlphaComponent(0.95)
            } else if isMajor {
                color = UIColor.white.withAlphaComponent(0.7)
            } else {
                color = UIColor.white.withAlphaComponent(0.28)
            }
            context.setFillColor(color.cgColor)
            context.fill(CGRect(
                x: x - 0.5,
                y: (bounds.height - height) / 2,
                width: 1,
                height: height
            ))
        }
    }
}

private struct LiveValueSlider: UIViewRepresentable {
    var value: Double
    var range: ClosedRange<Double>
    var step: Double?
    var onChanging: (Double) -> Void
    var onEnded: (Double) -> Void

    init(
        value: Double,
        range: ClosedRange<Double>,
        step: Double? = nil,
        onChanging: @escaping (Double) -> Void,
        onEnded: @escaping (Double) -> Void
    ) {
        self.value = value
        self.range = range
        self.step = step
        self.onChanging = onChanging
        self.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.ended(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.step = step
        context.coordinator.onChanging = onChanging
        context.coordinator.onEnded = onEnded
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        if !slider.isTracking {
            slider.value = Float(value)
        }
    }

    final class Coordinator {
        var step: Double?
        var onChanging: (Double) -> Void = { _ in }
        var onEnded: (Double) -> Void = { _ in }

        @objc func changed(_ slider: UISlider) {
            onChanging(resolvedValue(slider))
        }

        @objc func ended(_ slider: UISlider) {
            onEnded(resolvedValue(slider))
        }

        private func resolvedValue(_ slider: UISlider) -> Double {
            var value = Double(slider.value)
            if let step, step > 0 {
                value = (value / step).rounded() * step
            }
            return value
        }
    }
}

extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
