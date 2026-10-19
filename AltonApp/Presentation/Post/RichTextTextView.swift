import UIKit
import UniformTypeIdentifiers

/// Keeps the composer text view first responder while the tool bar handles a tap.
enum RichTextFocusLock {
    static var retain = false

    private static var token = 0

    static func holdForToolbarInteraction() {
        token += 1
        let current = token
        retain = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard token == current else { return }
            retain = false
        }
    }

    /// Clears the retain lock and resigns first responder (keyboard Done).
    @discardableResult
    static func dismissKeyboard(from textView: UITextView) -> Bool {
        retain = false
        return textView.resignFirstResponder()
    }
}

enum RichTextDisplayMode {
    case editor
    case feed
    case composer
}

final class RichTextTextView: UITextView, UIGestureRecognizerDelegate {
    var displayMode: RichTextDisplayMode = .editor {
        didSet { applyDisplayMode() }
    }

    /// Feed/detail: single tap opens the post when nothing is selected.
    var onContentTap: (() -> Void)?
    /// Feed/detail: tap on an attributed link (`mention://`, `hashtag://`, http…).
    /// Return `true` if the link was handled.
    var onLinkTap: ((URL) -> Bool)?

    /// Inline style to keep applying at the caret until the user moves it.
    var pinnedTypingAttributes: [NSAttributedString.Key: Any]?
    var pinnedTypingAnchor = NSRange(location: NSNotFound, length: 0)
    var pinGraceUntil: TimeInterval = 0

    /// Composer: grow with the text and let the parent scroll view move.
    var expandsToFitContent = false {
        didSet {
            guard expandsToFitContent != oldValue else { return }
            isScrollEnabled = !expandsToFitContent
            showsVerticalScrollIndicator = !expandsToFitContent
            bounces = !expandsToFitContent
            lastFittedHeight = -1
            invalidateIntrinsicContentSize()
        }
    }

    var onFittedHeightChange: ((CGFloat) -> Void)?
    /// When set, pasted images are routed here instead of inline NSTextAttachments.
    var onPasteImages: (([UIImage]) -> Void)?
    private var lastFittedHeight: CGFloat = -1

    private var codeBlockCopyButtons: [UIButton] = []
    private var cachedMergedBlocks: [RichTextCodeBlock.Block] = []
    private var cachedMergedBlocksTextHash: Int = 0
    private var suppressNextContentTap = false

    override var attributedText: NSAttributedString! {
        get { super.attributedText }
        set {
            super.attributedText = newValue
            invalidateMergedBlocksCache()
        }
    }

    private lazy var wordSelectionLongPress: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleWordSelectionLongPress(_:))
        )
        gesture.minimumPressDuration = 0.28
        gesture.delegate = self
        return gesture
    }()

    private lazy var contentTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleContentTap(_:))
        )
        gesture.delegate = self
        return gesture
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        addGestureRecognizer(wordSelectionLongPress)
        addGestureRecognizer(contentTapGesture)
        clipsToBounds = true
        applyDisplayMode()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: RichTextTextView, _) in
            view.setNeedsDisplay()
        }
    }

    @objc private func keyboardDoneTapped() {
        _ = RichTextFocusLock.dismissKeyboard(from: self)
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        if RichTextFocusLock.retain {
            return false
        }
        return super.resignFirstResponder()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), onPasteImages != nil {
            return UIPasteboard.general.hasStrings
                || ComposerPasteAttachments.pasteboardHasImages
                || !(UIPasteboard.general.string ?? "").isEmpty
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if let onPasteImages, ComposerPasteAttachments.pasteboardHasImages {
            let images = ComposerPasteAttachments.images(from: .general)
            if !images.isEmpty {
                onPasteImages(images)
                return
            }
        }
        super.paste(sender)
    }

    override var pasteConfiguration: UIPasteConfiguration? {
        get {
            guard onPasteImages != nil else { return super.pasteConfiguration }
            return ComposerPasteAttachments.imagePasteConfiguration
        }
        set {}
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let onPasteImages else {
            super.paste(itemProviders: itemProviders)
            return
        }
        let imageProviders = itemProviders.filter { $0.canLoadObject(ofClass: UIImage.self) }
        let textProviders = itemProviders.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
        }
        if !imageProviders.isEmpty {
            Task { @MainActor in
                let images = await ComposerPasteAttachments.loadImages(from: imageProviders)
                if !images.isEmpty {
                    onPasteImages(images)
                }
            }
            return
        }
        if !textProviders.isEmpty {
            super.paste(itemProviders: textProviders)
        }
    }

    private func applyDisplayMode() {
        let usesSystemSelection = displayMode == .editor || displayMode == .composer
        wordSelectionLongPress.isEnabled = !usesSystemSelection
        contentTapGesture.isEnabled = displayMode == .feed

        switch displayMode {
        case .editor:
            textContainer.lineFragmentPadding = 10
            installKeyboardDoneAccessoryIfNeeded()
        case .feed:
            textContainer.lineFragmentPadding = 0
            textContainerInset = .zero
            inputAccessoryView = nil
        case .composer:
            textContainer.lineFragmentPadding = 0
            textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            installKeyboardDoneAccessoryIfNeeded()
        }
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    private func installKeyboardDoneAccessoryIfNeeded() {
        if inputAccessoryView == nil {
            inputAccessoryView = KeyboardDismiss.makeDoneAccessoryToolbar(
                target: self,
                action: #selector(keyboardDoneTapped)
            )
        }
    }

    func scrollComposerCaretToVisible() {
        guard expandsToFitContent, let selectedTextRange else { return }
        var caret = caretRect(for: selectedTextRange.end)
        guard caret.isNull == false, caret.isInfinite == false else { return }
        caret = caret.insetBy(dx: 0, dy: -48)

        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView, scrollView !== self {
                let target = convert(caret, to: scrollView)
                scrollView.scrollRectToVisible(target, animated: false)
                return
            }
            ancestor = current.superview
        }
    }

    /// Text height from the string itself. Independent of the view's current frame,
    /// so a tall composer field does not feed its own height back into layout.
    func measuredContentHeight() -> CGFloat {
        let text = attributedText?.string ?? ""
        let width = max(bounds.width, 1)
        let insets = textContainerInset
        let measureWidth = max(
            width - insets.left - insets.right - textContainer.lineFragmentPadding * 2,
            1
        )
        guard !text.isEmpty else {
            return ceil(insets.top + insets.bottom + 28)
        }
        let font = (typingAttributes[.font] as? UIFont) ?? RichTextStyle.bodyFont
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: measureWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height + insets.top + insets.bottom + 8)
    }

    override var intrinsicContentSize: CGSize {
        if expandsToFitContent {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        return super.intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if expandsToFitContent, bounds.width > 0 {
            let fitted = measuredContentHeight()
            if abs(fitted - lastFittedHeight) > 1 {
                lastFittedHeight = fitted
                onFittedHeightChange?(fitted)
            }
        }
        layoutCodeBlockCopyButtons()
    }

    override func draw(_ rect: CGRect) {
        drawStyledBackgrounds()
        super.draw(rect)
    }

    @objc private func handleWordSelectionLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        // Editor: always allow. Feed: allow selection with haptic (read-only posts).
        guard isEditable || displayMode == .feed else { return }

        let point = gesture.location(in: self)
        guard let position = closestPosition(to: point) else { return }

        let index = offset(from: beginningOfDocument, to: position)
        let selection = quickSelectionRange(at: index)

        guard selection.length > 0 else { return }

        suppressNextContentTap = true
        selectedRange = selection
        becomeFirstResponder()
        if displayMode == .feed {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    @objc private func handleContentTap(_ gesture: UITapGestureRecognizer) {
        guard displayMode == .feed, gesture.state == .ended else { return }

        if suppressNextContentTap {
            suppressNextContentTap = false
            return
        }

        if selectedRange.length > 0 {
            selectedRange = NSRange(location: 0, length: 0)
            resignFirstResponder()
            return
        }

        let point = gesture.location(in: self)
        if let url = linkURL(at: point) {
            // Consume link taps so the custom gesture does not open the post.
            _ = onLinkTap?(url)
            return
        }

        onContentTap?()
    }

    private func linkURL(at point: CGPoint) -> URL? {
        guard let attributedText, attributedText.length > 0 else { return nil }
        guard let position = closestPosition(to: point) else { return nil }
        let index = offset(from: beginningOfDocument, to: position)
        guard index >= 0, index < attributedText.length else { return nil }

        var effective = NSRange(location: 0, length: 0)
        let value = attributedText.attribute(.link, at: index, effectiveRange: &effective)
        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
    }

    private func quickSelectionRange(at index: Int) -> NSRange {
        let content = attributedText?.string ?? text ?? ""
        let nsContent = content as NSString
        guard nsContent.length > 0 else { return NSRange(location: 0, length: 0) }

        let safeIndex = min(max(index, 0), nsContent.length - 1)

        if isInCodeContext(at: safeIndex) {
            return codeTokenRange(at: safeIndex, in: nsContent)
        }

        return wordOrLineRange(at: safeIndex, in: nsContent)
    }

    private func isInCodeContext(at index: Int) -> Bool {
        guard let attributedText, attributedText.length > 0 else { return false }
        let safeIndex = min(max(index, 0), attributedText.length - 1)
        let attributes = attributedText.attributes(at: safeIndex, effectiveRange: nil)
        return attributes[RichTextAttribute.codeBlock] != nil
            || attributes[RichTextAttribute.inlineCode] != nil
    }

    private func codeTokenRange(at index: Int, in content: NSString) -> NSRange {
        let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
        let whitespace = CharacterSet.whitespacesAndNewlines
        let lineEnd = NSMaxRange(lineRange)

        var start = min(index, max(content.length - 1, 0))
        var end = min(index + 1, lineEnd)

        while start > lineRange.location {
            let previous = content.substring(with: NSRange(location: start - 1, length: 1))
            if previous.rangeOfCharacter(from: whitespace) != nil { break }
            start -= 1
        }

        while end < lineEnd {
            let next = content.substring(with: NSRange(location: end, length: 1))
            if next.rangeOfCharacter(from: whitespace) != nil { break }
            end += 1
        }

        guard end > start else {
            return NSRange(location: safeClampedIndex(index, in: content), length: 1)
        }
        return NSRange(location: start, length: end - start)
    }

    private func wordOrLineRange(at index: Int, in nsContent: NSString) -> NSRange {
        guard nsContent.length > 0 else { return NSRange(location: 0, length: 0) }

        let safeIndex = min(max(index, 0), nsContent.length - 1)
        let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_@#."))

        var start = safeIndex
        var end = safeIndex + 1

        while start > 0 {
            let previous = nsContent.substring(with: NSRange(location: start - 1, length: 1))
            if previous.rangeOfCharacter(from: wordCharacters) == nil { break }
            start -= 1
        }

        while end < nsContent.length {
            let next = nsContent.substring(with: NSRange(location: end, length: 1))
            if next.rangeOfCharacter(from: wordCharacters) == nil { break }
            end += 1
        }

        if end - start <= 1 {
            return nsContent.lineRange(for: NSRange(location: safeIndex, length: 0))
        }

        return NSRange(location: start, length: end - start)
    }

    private func safeClampedIndex(_ index: Int, in content: NSString) -> Int {
        min(max(index, 0), max(content.length - 1, 0))
    }

    private func invalidateMergedBlocksCache() {
        cachedMergedBlocks = []
        cachedMergedBlocksTextHash = 0
    }

    private func cachedCodeBlocks() -> [RichTextCodeBlock.Block] {
        guard let attributedText else { return [] }
        let hash = attributedText.string.hashValue
        if hash == cachedMergedBlocksTextHash, !cachedMergedBlocks.isEmpty || attributedText.length == 0 {
            return cachedMergedBlocks
        }
        cachedMergedBlocks = RichTextCodeBlock.mergedBlocks(in: attributedText)
        cachedMergedBlocksTextHash = hash
        return cachedMergedBlocks
    }

    private func drawStyledBackgrounds() {
        guard let attributedText, attributedText.length > 0 else { return }

        let origin = CGPoint(
            x: textContainerInset.left,
            y: textContainerInset.top
        )

        attributedText.enumerateAttribute(
            RichTextAttribute.inlineCode,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard value != nil else { return }
            drawRoundedBackground(
                for: range,
                fill: RichTextStyle.inlineCodeFill,
                border: nil,
                cornerRadius: 6,
                padding: UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5),
                origin: origin
            )
        }

        var drawnQuotes: [NSRange] = []
        attributedText.enumerateAttribute(
            RichTextAttribute.blockquote,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard value != nil else { return }
            let paragraphRange = (attributedText.string as NSString).paragraphRange(for: range)
            guard !drawnQuotes.contains(where: { NSEqualRanges($0, paragraphRange) }) else { return }
            drawnQuotes.append(paragraphRange)
            drawQuoteAccent(for: paragraphRange, origin: origin)
        }

        for block in cachedCodeBlocks() {
            drawUnifiedCodeBlock(block, origin: origin)
        }

        attributedText.enumerateAttribute(
            RichTextAttribute.spoiler,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard value != nil else { return }
            drawRoundedBackground(
                for: range,
                fill: RichTextStyle.spoilerBackground,
                border: nil,
                cornerRadius: 4,
                padding: UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3),
                origin: origin
            )
        }
    }

    private func drawUnifiedCodeBlock(_ block: RichTextCodeBlock.Block, origin: CGPoint) {
        guard let bodyRect = boundingRect(for: block.range, origin: origin)?.insetBy(dx: -10, dy: -8) else {
            return
        }

        let headerHeight = RichTextStyle.codeBlockHeaderHeight
        var containerRect = bodyRect
        containerRect.origin.y -= headerHeight
        containerRect.size.height += headerHeight

        let containerPath = UIBezierPath(roundedRect: containerRect, cornerRadius: 12)
        RichTextStyle.codeBlockFill.setFill()
        containerPath.fill()
        RichTextStyle.codeBlockBorder.setStroke()
        containerPath.lineWidth = 1
        containerPath.stroke()

        let headerRect = CGRect(
            x: containerRect.minX,
            y: containerRect.minY,
            width: containerRect.width,
            height: headerHeight
        )
        let separatorY = headerRect.maxY
        let separatorPath = UIBezierPath()
        separatorPath.move(to: CGPoint(x: headerRect.minX + 12, y: separatorY))
        separatorPath.addLine(to: CGPoint(x: headerRect.maxX - 12, y: separatorY))
        RichTextStyle.codeBlockBorder.setStroke()
        separatorPath.lineWidth = 1
        separatorPath.stroke()

        let language = block.language.uppercased()
        let languageAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        (language as NSString).draw(
            at: CGPoint(x: headerRect.minX + 14, y: headerRect.minY + 10),
            withAttributes: languageAttributes
        )
    }

    private func layoutCodeBlockCopyButtons() {
        codeBlockCopyButtons.forEach { $0.removeFromSuperview() }
        codeBlockCopyButtons.removeAll()

        guard attributedText != nil else { return }

        let origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)

        for block in cachedCodeBlocks() {
            guard let bodyRect = boundingRect(for: block.range, origin: origin)?.insetBy(dx: -10, dy: -8) else {
                continue
            }

            let headerHeight = RichTextStyle.codeBlockHeaderHeight
            let headerRect = CGRect(
                x: bodyRect.minX,
                y: bodyRect.minY - headerHeight,
                width: bodyRect.width + 20,
                height: headerHeight
            )

            let button = UIButton(type: .system)
            button.setTitle("Copy", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.frame = CGRect(x: headerRect.maxX - 62, y: headerRect.minY + 5, width: 52, height: 24)
            button.addAction(
                UIAction { _ in
                    UIPasteboard.general.string = block.code
                },
                for: .touchUpInside
            )
            addSubview(button)
            codeBlockCopyButtons.append(button)
        }
    }

    private func boundingRect(for range: NSRange, origin: CGPoint) -> CGRect? {
        var unionRect: CGRect?
        enumerateTextRects(for: range, origin: origin) { rect in
            unionRect = unionRect?.union(rect) ?? rect
        }
        return unionRect
    }

    private func drawQuoteAccent(for range: NSRange, origin: CGPoint) {
        guard var blockRect = boundingRect(for: range, origin: origin), blockRect != .zero else { return }

        blockRect.size.width = 3

        let path = UIBezierPath(roundedRect: blockRect, cornerRadius: 1.5)
        UIColor.secondaryLabel.withAlphaComponent(0.55).setFill()
        path.fill()
    }

    private func drawRoundedBackground(
        for range: NSRange,
        fill: UIColor,
        border: UIColor?,
        cornerRadius: CGFloat,
        padding: UIEdgeInsets,
        origin: CGPoint
    ) {
        enumerateTextRects(for: range, origin: origin) { rect in
            var backgroundRect = rect
            backgroundRect.origin.x -= padding.left
            backgroundRect.origin.y -= padding.top
            backgroundRect.size.width += padding.left + padding.right
            backgroundRect.size.height += padding.top + padding.bottom

            let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: cornerRadius)
            fill.setFill()
            path.fill()

            if let border {
                border.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func enumerateTextRects(
        for range: NSRange,
        origin: CGPoint,
        body: (CGRect) -> Void
    ) {
        guard let textLayoutManager,
              let textContentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let textRange = textContentStorage.textRange(for: range) else {
            return
        }

        textLayoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: []
        ) { _, segmentRect, _, _ in
            var adjusted = segmentRect
            adjusted.origin.x += origin.x
            adjusted.origin.y += origin.y
            body(adjusted)
            return true
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === contentTapGesture {
            return otherGestureRecognizer === wordSelectionLongPress
        }
        if gestureRecognizer === wordSelectionLongPress {
            return otherGestureRecognizer === contentTapGesture
        }
        return false
    }
}

private extension NSTextContentStorage {
    func textRange(for nsRange: NSRange) -> NSTextRange? {
        guard nsRange.location != NSNotFound, nsRange.length >= 0 else { return nil }

        let documentLength = offset(from: documentRange.location, to: documentRange.endLocation)
        guard nsRange.location <= documentLength,
              nsRange.location + nsRange.length <= documentLength else {
            return nil
        }

        guard let start = location(documentRange.location, offsetBy: nsRange.location),
              let end = location(start, offsetBy: nsRange.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }
}
