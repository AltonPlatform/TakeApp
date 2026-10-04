import SwiftUI

// MARK: - Color tokens (literal until the shared composer palette lands)

private extension Color {
    /// #1c1c1e
    static let chromeInk = Color(#colorLiteral(red: 0.1098, green: 0.1098, blue: 0.1176, alpha: 1))
    /// #eaecf0
    static let chromeHairline = Color(#colorLiteral(red: 0.9176, green: 0.9255, blue: 0.9412, alpha: 1))
    /// #a0a3ab
    static let chromeSecondary = Color(#colorLiteral(red: 0.6275, green: 0.6392, blue: 0.6706, alpha: 1))
}

// MARK: - State

/// Rule deciding whether the composer's Post pill is tappable.
struct ComposerPublishState: Equatable {
    let canSubmitContent: Bool
    let isSubmitting: Bool

    var canPublish: Bool { !isSubmitting && canSubmitContent }
}

/// UI state of the bottom chrome that is independent of the draft itself.
struct ComposerChromeState: Equatable {
    var showFormatTools = false

    mutating func toggleFormat() {
        showFormatTools.toggle()
    }
}

// MARK: - Icons

/// Outline icon set for the composer chrome (stroke 1.5, no fill, #1c1c1e).
enum ComposerIcon: CaseIterable {
    // Tool row
    case photos, format, mention, preview, more
    // Format actions
    case bold, italic, underline, strikethrough, spoiler, inlineCode, link
    case quote, bulletList, numberedList, codeBlock

    init(_ action: RichTextFormatAction) {
        switch action {
        case .bold: self = .bold
        case .italic: self = .italic
        case .underline: self = .underline
        case .strikethrough: self = .strikethrough
        case .spoiler: self = .spoiler
        case .code: self = .inlineCode
        case .link: self = .link
        case .quote: self = .quote
        case .bulletList: self = .bulletList
        case .numberedList: self = .numberedList
        case .codeBlock: self = .codeBlock
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .photos: "Add photos"
        case .format: "Format"
        case .mention: "Mention"
        case .preview: "Preview"
        case .more: "More"
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .spoiler: "Spoiler"
        case .inlineCode: "Code"
        case .link: "Link"
        case .quote: "Quote"
        case .bulletList: "Bullet list"
        case .numberedList: "Numbered list"
        case .codeBlock: "Code block"
        }
    }
}

/// Draws a `ComposerIcon` on a 24-unit grid, scaled to the frame it is given.
struct ComposerIconShape: Shape {
    let icon: ComposerIcon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return icon.path24.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// Renders a `ComposerIcon` as an outline: 22pt in the tool row, 24pt in the format capsule.
struct ComposerIconView: View {
    let icon: ComposerIcon
    var size: CGFloat = 22

    var body: some View {
        ComposerIconShape(icon: icon)
            .stroke(Color.chromeInk, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension ComposerIcon {
    /// Outline geometry on a 24×24 grid.
    var path24: Path {
        switch self {
        case .photos: return Self.photosPath
        case .format: return Self.formatPath
        case .mention: return Self.mentionPath
        case .preview: return Self.eyePath(slashed: false)
        case .more: return Self.morePath
        case .bold: return Self.boldPath
        case .italic: return Self.italicPath
        case .underline: return Self.underlinePath
        case .strikethrough: return Self.strikethroughPath
        case .spoiler: return Self.eyePath(slashed: true)
        case .inlineCode: return Self.bracesPath
        case .link: return Self.linkPath
        case .quote: return Self.quotePath
        case .bulletList: return Self.bulletListPath
        case .numberedList: return Self.numberedListPath
        case .codeBlock: return Self.codeBlockPath
        }
    }

    static var photosPath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3, y: 4.5, width: 18, height: 15), cornerSize: CGSize(width: 3, height: 3))
        p.addEllipse(in: CGRect(x: 7, y: 8.5, width: 3, height: 3))
        p.move(to: CGPoint(x: 3.5, y: 17))
        p.addLine(to: CGPoint(x: 8.5, y: 13.5))
        p.addLine(to: CGPoint(x: 13, y: 17))
        p.addLine(to: CGPoint(x: 16, y: 14.5))
        p.addLine(to: CGPoint(x: 20.5, y: 18))
        return p
    }

    static var formatPath: Path {
        var p = Path()
        // Capital A
        p.move(to: CGPoint(x: 2.5, y: 18))
        p.addLine(to: CGPoint(x: 7.5, y: 5.5))
        p.addLine(to: CGPoint(x: 12.5, y: 18))
        p.move(to: CGPoint(x: 4.3, y: 13.8))
        p.addLine(to: CGPoint(x: 10.7, y: 13.8))
        // Lowercase a
        p.addEllipse(in: CGRect(x: 14, y: 11.5, width: 6, height: 6.5))
        p.move(to: CGPoint(x: 20, y: 11.5))
        p.addLine(to: CGPoint(x: 20, y: 18))
        return p
    }

    static var mentionPath: Path {
        var p = Path()
        let center = CGPoint(x: 12, y: 12)
        p.addEllipse(in: CGRect(x: 8.5, y: 8.5, width: 7, height: 7))
        p.move(to: CGPoint(x: 15.5, y: 8.5))
        p.addLine(to: CGPoint(x: 15.5, y: 13))
        p.addCurve(
            to: CGPoint(x: 20.5, y: 12),
            control1: CGPoint(x: 15.5, y: 15.5),
            control2: CGPoint(x: 20.5, y: 15.5)
        )
        // Open outer ring: from 0° counter-clockwise (on screen) to ~50° below the right edge.
        let steps = 48
        for step in 0...steps {
            let degrees = -310.0 * Double(step) / Double(steps)
            let radians = degrees * .pi / 180
            let point = CGPoint(
                x: center.x + 8.5 * CGFloat(cos(radians)),
                y: center.y + 8.5 * CGFloat(sin(radians))
            )
            if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }

    static func eyePath(slashed: Bool) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 2.5, y: 12))
        p.addCurve(to: CGPoint(x: 21.5, y: 12), control1: CGPoint(x: 6, y: 5.5), control2: CGPoint(x: 18, y: 5.5))
        p.addCurve(to: CGPoint(x: 2.5, y: 12), control1: CGPoint(x: 18, y: 18.5), control2: CGPoint(x: 6, y: 18.5))
        p.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
        if slashed {
            p.move(to: CGPoint(x: 4.5, y: 19.5))
            p.addLine(to: CGPoint(x: 19.5, y: 4.5))
        }
        return p
    }

    static var morePath: Path {
        var p = Path()
        for x in [5.0, 12.0, 19.0] {
            p.addEllipse(in: CGRect(x: x - 1.25, y: 10.75, width: 2.5, height: 2.5))
        }
        return p
    }

    static var boldPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 7, y: 5))
        p.addLine(to: CGPoint(x: 13, y: 5))
        p.addCurve(to: CGPoint(x: 13, y: 12), control1: CGPoint(x: 17, y: 5), control2: CGPoint(x: 17, y: 12))
        p.addLine(to: CGPoint(x: 7, y: 12))
        p.move(to: CGPoint(x: 13.5, y: 12))
        p.addCurve(to: CGPoint(x: 13.5, y: 19), control1: CGPoint(x: 19, y: 12), control2: CGPoint(x: 19, y: 19))
        p.addLine(to: CGPoint(x: 7, y: 19))
        p.addLine(to: CGPoint(x: 7, y: 5))
        return p
    }

    static var italicPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 10, y: 5))
        p.addLine(to: CGPoint(x: 18, y: 5))
        p.move(to: CGPoint(x: 6, y: 19))
        p.addLine(to: CGPoint(x: 14, y: 19))
        p.move(to: CGPoint(x: 15, y: 5))
        p.addLine(to: CGPoint(x: 9, y: 19))
        return p
    }

    static var underlinePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 7, y: 4.5))
        p.addLine(to: CGPoint(x: 7, y: 11))
        p.addCurve(to: CGPoint(x: 17, y: 11), control1: CGPoint(x: 7, y: 17.5), control2: CGPoint(x: 17, y: 17.5))
        p.addLine(to: CGPoint(x: 17, y: 4.5))
        p.move(to: CGPoint(x: 5, y: 20.5))
        p.addLine(to: CGPoint(x: 19, y: 20.5))
        return p
    }

    static var strikethroughPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 16, y: 7.5))
        p.addCurve(to: CGPoint(x: 12, y: 5.5), control1: CGPoint(x: 15, y: 6), control2: CGPoint(x: 13.5, y: 5.5))
        p.addCurve(to: CGPoint(x: 7.8, y: 8.5), control1: CGPoint(x: 9.5, y: 5.5), control2: CGPoint(x: 7.8, y: 6.8))
        p.addCurve(to: CGPoint(x: 12, y: 11.5), control1: CGPoint(x: 7.8, y: 10.2), control2: CGPoint(x: 10, y: 11))
        p.addCurve(to: CGPoint(x: 16.2, y: 15), control1: CGPoint(x: 14.5, y: 12), control2: CGPoint(x: 16.2, y: 13.3))
        p.addCurve(to: CGPoint(x: 12, y: 18.5), control1: CGPoint(x: 16.2, y: 17.3), control2: CGPoint(x: 14.5, y: 18.5))
        p.addCurve(to: CGPoint(x: 7.5, y: 16), control1: CGPoint(x: 9.5, y: 18.5), control2: CGPoint(x: 8.2, y: 17.6))
        p.move(to: CGPoint(x: 4, y: 12))
        p.addLine(to: CGPoint(x: 20, y: 12))
        return p
    }

    static var bracesPath: Path {
        func brace(mirrored: Bool) -> Path {
            func x(_ value: CGFloat) -> CGFloat { mirrored ? 24 - value : value }
            var p = Path()
            p.move(to: CGPoint(x: x(9.5), y: 4))
            p.addQuadCurve(to: CGPoint(x: x(7.5), y: 6), control: CGPoint(x: x(7.5), y: 4))
            p.addLine(to: CGPoint(x: x(7.5), y: 10))
            p.addQuadCurve(to: CGPoint(x: x(5), y: 12), control: CGPoint(x: x(7.5), y: 12))
            p.addQuadCurve(to: CGPoint(x: x(7.5), y: 14), control: CGPoint(x: x(7.5), y: 12))
            p.addLine(to: CGPoint(x: x(7.5), y: 18))
            p.addQuadCurve(to: CGPoint(x: x(9.5), y: 20), control: CGPoint(x: x(7.5), y: 20))
            return p
        }
        var p = brace(mirrored: false)
        p.addPath(brace(mirrored: true))
        return p
    }

    static var linkPath: Path {
        func link(centeredAt center: CGPoint) -> Path {
            let rounded = Path(
                roundedRect: CGRect(x: -5.5, y: -3, width: 11, height: 6),
                cornerRadius: 3
            )
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: -.pi / 4)
            return rounded.applying(transform)
        }
        var p = link(centeredAt: CGPoint(x: 9.2, y: 14.8))
        p.addPath(link(centeredAt: CGPoint(x: 14.8, y: 9.2)))
        return p
    }

    static var quotePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 5))
        p.addLine(to: CGPoint(x: 4, y: 19))
        for (y, endX) in [(8.0, 20.0), (12.0, 20.0), (16.0, 15.0)] {
            p.move(to: CGPoint(x: 9, y: y))
            p.addLine(to: CGPoint(x: endX, y: y))
        }
        return p
    }

    static var bulletListPath: Path {
        var p = Path()
        for y in [6.5, 12.0, 17.5] {
            p.addEllipse(in: CGRect(x: 3.5, y: y - 1, width: 2, height: 2))
            p.move(to: CGPoint(x: 10, y: y))
            p.addLine(to: CGPoint(x: 20.5, y: y))
        }
        return p
    }

    static var numberedListPath: Path {
        var p = Path()
        for y in [6.5, 12.0, 17.5] {
            p.move(to: CGPoint(x: 10, y: y))
            p.addLine(to: CGPoint(x: 20.5, y: y))
        }
        // 1
        p.move(to: CGPoint(x: 3.8, y: 5.8))
        p.addLine(to: CGPoint(x: 5.4, y: 4.6))
        p.addLine(to: CGPoint(x: 5.4, y: 8.6))
        // 2
        p.move(to: CGPoint(x: 3.8, y: 10.6))
        p.addCurve(to: CGPoint(x: 6.4, y: 11.2), control1: CGPoint(x: 4.2, y: 9.2), control2: CGPoint(x: 6.4, y: 9.2))
        p.addLine(to: CGPoint(x: 3.8, y: 14))
        p.addLine(to: CGPoint(x: 6.4, y: 14))
        // 3
        p.move(to: CGPoint(x: 3.8, y: 15.6))
        p.addLine(to: CGPoint(x: 6.4, y: 15.6))
        p.addLine(to: CGPoint(x: 5, y: 17.3))
        p.addCurve(to: CGPoint(x: 3.8, y: 19.2), control1: CGPoint(x: 6.8, y: 17.3), control2: CGPoint(x: 6.8, y: 19.2))
        return p
    }

    static var codeBlockPath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: CGSize(width: 3, height: 3))
        p.move(to: CGPoint(x: 10, y: 9))
        p.addLine(to: CGPoint(x: 7, y: 12))
        p.addLine(to: CGPoint(x: 10, y: 15))
        p.move(to: CGPoint(x: 14, y: 9))
        p.addLine(to: CGPoint(x: 17, y: 12))
        p.addLine(to: CGPoint(x: 14, y: 15))
        return p
    }
}

// MARK: - Chrome

/// Bottom glass chrome of the Take composer.
///
/// Row 1 (optional): format capsule. Row 2: tool row, character meter and the Post pill.
/// The whole stack is one `regularMaterial` surface so Post always stays visible above the keyboard.
struct ComposerBottomChrome: View {
    static let toolRowHeight: CGFloat = 56
    /// Format capsule row height including its divider.
    static let formatRowHeight: CGFloat = 47

    @Binding var chromeState: ComposerChromeState
    let isPreviewMode: Bool
    let formatState: RichTextFormatState
    let publishState: ComposerPublishState
    var publishTitle = "Post"
    let attachmentCount: Int
    let maxAttachments: Int
    let usedCharacters: Int
    let characterLimit: Int
    let onPhotos: () -> Void
    let onMention: () -> Void
    let onTogglePreview: () -> Void
    let onFormatAction: (RichTextFormatAction) -> Void
    let onRecordShot: () -> Void
    let onRemoveAllPhotos: () -> Void
    let onPublish: () -> Void

    private var showsFormatCapsule: Bool {
        chromeState.showFormatTools && !isPreviewMode
    }

    private var remainingSlots: Int {
        max(0, maxAttachments - attachmentCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsFormatCapsule {
                formatCapsuleRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Rectangle()
                    .fill(Color.chromeHairline)
                    .frame(height: 1)
            }
            toolRow
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.chromeHairline)
                .frame(height: 1)
        }
    }

    // MARK: Row 1 — format capsule

    private var formatCapsuleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(RichTextFormatAction.inlineActions) { action in
                    formatButton(action)
                }

                Rectangle()
                    .fill(Color.chromeHairline)
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 6)

                ForEach(RichTextFormatAction.blockActions) { action in
                    formatButton(action)
                }
            }
            .padding(.horizontal, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.chromeHairline, lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .frame(height: Self.formatRowHeight - 1)
    }

    private func formatButton(_ action: RichTextFormatAction) -> some View {
        let icon = ComposerIcon(action)
        let isOn = formatState.isActive(action)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onFormatAction(action)
        } label: {
            ComposerIconView(icon: icon, size: 24)
                .frame(width: 36, height: 36)
                .background(isOn ? Color.chromeHairline : Color.clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.accessibilityLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Row 2 — tools, meter, Post

    private var toolRow: some View {
        HStack(spacing: 0) {
            toolButton(.photos, disabled: remainingSlots == 0 || isPreviewMode, action: onPhotos)
                .accessibilityValue("\(attachmentCount) of \(maxAttachments)")
            toolButton(
                .format,
                isActive: chromeState.showFormatTools && !isPreviewMode,
                disabled: isPreviewMode
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    chromeState.toggleFormat()
                }
            }
            toolButton(.mention, disabled: isPreviewMode, action: onMention)
            toolButton(.preview, isActive: isPreviewMode, action: onTogglePreview)
            moreMenu

            Spacer(minLength: 8)

            characterMeter
            postPill
        }
        .padding(.horizontal, 6)
        .frame(height: Self.toolRowHeight)
    }

    private func toolLabel(_ icon: ComposerIcon, isActive: Bool, disabled: Bool = false) -> some View {
        ComposerIconView(icon: icon, size: 22)
            .frame(width: 40, height: 32)
            .background(isActive ? Color.chromeHairline : Color.clear, in: Capsule())
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.35 : 1)
    }

    private func toolButton(
        _ icon: ComposerIcon,
        isActive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolLabel(icon, isActive: isActive, disabled: disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(icon.accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onRecordShot) {
                Label("Record shot", systemImage: "video")
            }
            if attachmentCount > 0 {
                Button(role: .destructive, action: onRemoveAllPhotos) {
                    Label("Remove all photos", systemImage: "trash")
                }
            }
        } label: {
            toolLabel(.more, isActive: false)
        }
        .accessibilityLabel(ComposerIcon.more.accessibilityLabel)
    }

    // MARK: Character meter

    private var remainingCharacters: Int { characterLimit - usedCharacters }

    @ViewBuilder
    private var characterMeter: some View {
        if remainingCharacters <= 400 {
            let progress = min(1, max(0, Double(usedCharacters) / Double(characterLimit)))
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.chromeHairline, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.chromeInk, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

                if remainingCharacters < 200 {
                    Text("\(remainingCharacters)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(remainingCharacters < 0 ? Color.chromeInk : Color.chromeSecondary)
                }
            }
            .padding(.trailing, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(usedCharacters) of \(characterLimit) characters")
        }
    }

    // MARK: Post pill

    private var postPill: some View {
        let isDimmed = !publishState.canSubmitContent && !publishState.isSubmitting
        return Button(action: onPublish) {
            Group {
                if publishState.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(publishTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(isDimmed ? Color.chromeSecondary : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(isDimmed ? Color.chromeHairline : Color.chromeInk, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!publishState.canPublish)
        .accessibilityLabel(publishTitle)
    }
}
