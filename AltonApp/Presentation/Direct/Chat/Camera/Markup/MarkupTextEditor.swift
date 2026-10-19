import SwiftUI
import UIKit

struct MarkupTextDraft: Equatable {
    var id: UUID
    var text: String
    var center: MarkupPoint
    var colorHex: String
    var font: MarkupTextFont
    var background: MarkupTextBackground
    var alignment: MarkupTextAlignment
    var scale: CGFloat
    var rotation: CGFloat
    var fontSizeNorm: CGFloat
    var isNew: Bool

    init(from item: MarkupTextItem, isNew: Bool) {
        id = item.id
        text = item.text
        center = item.center
        colorHex = item.colorHex
        font = item.font
        background = item.background
        alignment = item.alignment
        scale = item.scale
        rotation = item.rotation
        fontSizeNorm = item.fontSizeNorm
        self.isNew = isNew
    }

    func asItem() -> MarkupTextItem {
        MarkupTextItem(
            id: id,
            text: text,
            center: center,
            scale: scale,
            rotation: rotation,
            colorHex: colorHex,
            font: font,
            background: background,
            alignment: alignment,
            fontSizeNorm: fontSizeNorm
        )
    }

    static func fresh(at center: MarkupPoint = MarkupPoint(x: 0.5, y: 0.5)) -> MarkupTextDraft {
        var item = MarkupTextItem(text: "", center: center)
        MarkupTextPreferences.apply(to: &item)
        return MarkupTextDraft(from: item, isNew: true)
    }
}

private enum EditorAccessory: Equatable {
    case fonts
    case palette
    case hueStrip
}

struct MarkupTextEditorOverlay: View {
    @Binding var draft: MarkupTextDraft
    var canvasSize: CGSize
    var sampleImage: CGImage?
    var onDone: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool
    @State private var accessory: EditorAccessory = .fonts
    @State private var showEyedropper = false
    @State private var keyboardOverlap: CGFloat = 0
    @State private var chromeIn = false
    @State private var topSafe: CGFloat = 54
    /// After Done, the field flies from the editing center to its place on the photo.
    @State private var placing = false
    /// Slider 0...1 mapped to fontSizeNorm 0.035...0.16
    @State private var sizeSlider: CGFloat = 0.35

    var body: some View {
        GeometryReader { geo in
            let origin = CGPoint(
                x: (geo.size.width - canvasSize.width) / 2,
                y: (geo.size.height - canvasSize.height) / 2
            )
            let accessoryHeight: CGFloat = 64
            let topInset = topSafe + 56
            let visibleBottom = geo.size.height - keyboardOverlap - accessoryHeight
            let editY = topInset + max(0, visibleBottom - topInset) / 2
            let home = CGPoint(
                x: origin.x + draft.center.x * canvasSize.width,
                y: origin.y + draft.center.y * canvasSize.height
            )
            ZStack {
                Color.black.opacity(placing ? 0 : 0.5)
                    .ignoresSafeArea()
                    .opacity(chromeIn ? 1 : 0)
                    .onTapGesture {
                        guard !placing else { return }
                        commitIfPossible()
                    }

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                }
                .opacity(chromeIn && !placing ? 1 : 0)
                .offset(y: chromeIn ? 0 : -16)
                .allowsHitTesting(!placing)

                textField
                    .scaleEffect(chromeIn ? 1 : 0.72, anchor: .center)
                    .opacity(chromeIn ? 1 : 0)
                    .offset(y: chromeIn || placing ? 0 : 22)
                    .position(
                        x: placing ? home.x : geo.size.width / 2,
                        y: placing ? home.y : editY
                    )
                    .animation(.spring(response: 0.42, dampingFraction: 0.84), value: placing)
                    .animation(.easeOut(duration: 0.25), value: keyboardOverlap)

                let photoTop = origin.y + 18
                let photoBottom = min(
                    origin.y + canvasSize.height - 18,
                    geo.size.height - keyboardOverlap - accessoryHeight - 10
                )
                let span = max(96, photoBottom - photoTop)
                let track = min(span * 0.78, span)
                MarkupVerticalSlider(
                    value: $sizeSlider,
                    showsStrokePreview: false,
                    trackHeight: track
                )
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .directGlass(Capsule(), tint: Color.black.opacity(0.18))
                .position(x: max(28, origin.x + 24), y: photoTop + span / 2)
                .offset(x: chromeIn ? 0 : -10)
                .opacity(chromeIn && !placing ? 1 : 0)
                .allowsHitTesting(!placing)
                .onChange(of: sizeSlider) { _, t in
                    draft.fontSizeNorm = 0.035 + t * 0.125
                }

                if showEyedropper, let sampleImage {
                    MarkupEyedropperOverlay(
                        image: sampleImage,
                        canvasSize: canvasSize,
                        onPick: { hex in
                            draft.colorHex = hex
                            showEyedropper = false
                            accessory = .palette
                            focused = true
                        },
                        onCancel: {
                            showEyedropper = false
                            focused = true
                        }
                    )
                    .position(
                        x: origin.x + canvasSize.width / 2,
                        y: origin.y + canvasSize.height / 2
                    )
                }

                if !showEyedropper {
                    VStack {
                        Spacer()
                        bottomAccessory
                            .padding(.bottom, keyboardOverlap)
                    }
                    .opacity(chromeIn && !placing ? 1 : 0)
                    .offset(y: chromeIn ? 0 : 28)
                    .allowsHitTesting(!placing)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            topSafe = Self.windowTopInset
            sizeSlider = min(max((draft.fontSizeNorm - 0.035) / 0.125, 0), 1)
            focused = true
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                chromeIn = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let overlap = max(0, UIScreen.main.bounds.maxY - frame.minY)
            if abs(overlap - keyboardOverlap) > 1 {
                keyboardOverlap = overlap
            }
        }
        .tint(Color(markupHex: draft.colorHex) ?? .white)
    }

    private var topBar: some View {
        ZStack {
            DirectGlassContainer(spacing: 12) {
                HStack(spacing: 12) {
                    alignmentButton
                    colorButton
                    backgroundButton
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button("Done") { commitIfPossible() }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .directGlass(Capsule(), interactive: true, tint: Color.black.opacity(0.15))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, topSafe + 8)
    }

    private var alignmentButton: some View {
        Button {
            cycleAlignment()
        } label: {
            Image(systemName: alignmentIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .directGlass(Circle(), interactive: true, tint: Color.black.opacity(0.15))
    }

    private var colorButton: some View {
        Button {
            accessory = accessory == .palette || accessory == .hueStrip ? .fonts : .palette
        } label: {
            Circle()
                .fill(Color(markupHex: draft.colorHex) ?? .white)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .directGlass(Circle(), interactive: true, tint: Color.black.opacity(0.15))
    }

    private var backgroundButton: some View {
        Button {
            cycleBackground()
        } label: {
            Image(systemName: backgroundIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .directGlass(Circle(), interactive: true, tint: Color.black.opacity(0.15))
    }

    private static var windowTopInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        return window?.safeAreaInsets.top ?? 59
    }

    private var textField: some View {
        let probe = draft.asItem()
        let metrics = MarkupTextLayout.measure(item: probe, canvasSize: canvasSize)
        let textWidth = min(canvasSize.width * 0.85, max(metrics.textSize.width + 6, metrics.fontSize))
        let textHeight = max(metrics.textSize.height, metrics.fontSize * 1.15)
        return TextField("", text: $draft.text, axis: .vertical)
            .focused($focused)
            .font(Font(metrics.font))
            .foregroundStyle(Color(markupHex: draft.colorHex) ?? .white)
            .multilineTextAlignment(swiftAlignment)
            .lineLimit(1...8)
            .submitLabel(.done)
            .textFieldStyle(.plain)
            .frame(width: textWidth, height: textHeight, alignment: frameAlignment)
            .padding(.horizontal, metrics.padX)
            .padding(.vertical, max(4, metrics.padY))
            .background {
                if draft.background != .none {
                    RoundedRectangle(
                        cornerRadius: MarkupTextLayout.backgroundCorner(metrics: metrics),
                        style: .continuous
                    )
                    .fill(draft.background == .solid ? Color.black : Color.black.opacity(0.45))
                }
            }
    }

    private var swiftAlignment: TextAlignment {
        switch draft.alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch draft.alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    @ViewBuilder
    private var bottomAccessory: some View {
        Group {
            switch accessory {
            case .fonts:
                fontStrip
            case .palette:
                paletteStrip
            case .hueStrip:
                MarkupHueBrightnessStrip(colorHex: $draft.colorHex) {
                    accessory = .palette
                }
                .frame(height: 48)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .directGlass(
                    RoundedRectangle(cornerRadius: 20, style: .continuous),
                    tint: Color.black.opacity(0.18)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var fontStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MarkupTextFont.allCases) { font in
                    let selected = draft.font == font
                    Button {
                        draft.font = font
                    } label: {
                        Text("Aa")
                            .font(Font(font.uiFont(size: 20)))
                            .foregroundStyle(selected ? Color.black : Color.white)
                            .frame(width: 48, height: 36)
                            .background(
                                selected ? Color.white : Color.white.opacity(0.001),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(font.title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .directGlass(Capsule(), tint: Color.black.opacity(0.18))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var paletteStrip: some View {
        DirectGlassContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    focused = false
                    showEyedropper = true
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .directGlass(Circle(), interactive: true, tint: Color.black.opacity(0.12))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(MarkupPalette.swatches, id: \.self) { hex in
                            let selected = draft.colorHex.caseInsensitiveCompare(hex) == .orderedSame
                            Circle()
                                .fill(Color(markupHex: hex) ?? .white)
                                .frame(width: selected ? 32 : 26, height: selected ? 32 : 26)
                                .overlay {
                                    Circle().strokeBorder(
                                        Color.white.opacity(selected ? 1 : 0.35),
                                        lineWidth: selected ? 2.5 : 1
                                    )
                                }
                                .shadow(color: .black.opacity(selected ? 0.35 : 0), radius: 4, y: 1)
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                                .onTapGesture { draft.colorHex = hex }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    draft.colorHex = hex
                                    accessory = .hueStrip
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .directGlass(Capsule(), tint: Color.black.opacity(0.18))
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var alignmentIcon: String {
        switch draft.alignment {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }

    private var backgroundIcon: String {
        switch draft.background {
        case .none: return "character"
        case .solid: return "character.textbox"
        case .translucent: return "rectangle.fill.on.rectangle.fill"
        }
    }

    private func cycleAlignment() {
        switch draft.alignment {
        case .left: draft.alignment = .center
        case .center: draft.alignment = .right
        case .right: draft.alignment = .left
        }
    }

    private func cycleBackground() {
        switch draft.background {
        case .none: draft.background = .solid
        case .solid: draft.background = .translucent
        case .translucent: draft.background = .none
        }
    }

    private func commitIfPossible() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !placing else {
            onDone()
            return
        }
        focused = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            placing = true
            chromeIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDone()
        }
    }
}
