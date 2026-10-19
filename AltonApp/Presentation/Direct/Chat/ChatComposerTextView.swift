import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Max DM text length — must match message-service `MAX_BODY_LEN`.
enum ChatComposerLimits {
    static let maxBodyLen = 4000
    static let maxPasteImages = 10
    /// Single-line empty field; grows with content up to ~5 lines.
    /// Matches attach/send control diameter (40pt).
    static let minComposerHeight: CGFloat = 40
    static let maxComposerHeight: CGFloat = 120

    /// Fast UTF-16 length gate; falls back to `Character` count near the limit
    /// so emoji / grapheme clusters still respect `maxBodyLen`.
    static func allowsReplacement(
        currentUTF16Length: Int,
        rangeLength: Int,
        replacement: String
    ) -> Bool {
        let replacementUTF16 = (replacement as NSString).length
        let proposedUTF16 = currentUTF16Length - rangeLength + replacementUTF16
        if proposedUTF16 <= maxBodyLen { return true }
        // Near / over UTF-16 budget — verify Character count (emoji may be shorter).
        // Callers must pass the full current string when this path is needed.
        return false
    }

    /// Exact Character-count check used when the UTF-16 gate is inconclusive.
    static func allowsReplacementExact(current: String, range: NSRange, replacement: String) -> Bool {
        let ns = current as NSString
        guard NSMaxRange(range) <= ns.length else { return false }
        let proposed = ns.replacingCharacters(in: range, with: replacement)
        return proposed.count <= maxBodyLen
    }

    static func hasNonWhitespaceContent(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace }
    }
}

/// UITextView-backed composer that supports paste of text and images from the pasteboard.
/// Text is pushed into the UIView only when `textRevision` changes (programmatic edits).
struct ChatComposerTextView: UIViewRepresentable {
    var text: String
    var textRevision: Int
    var placeholder: String = "Message"
    /// Bump to request keyboard focus (Telegram opens composer after swipe-reply).
    var focusToken: Int = 0
    var onTextChange: (String) -> Void
    var onDraftChange: () -> Void
    var onPasteImages: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ChatPasteTextView {
        let view = ChatPasteTextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.onPasteImages = { images in
            context.coordinator.parent.onPasteImages(images)
        }
        view.onTextChanged = { newText in
            context.coordinator.syncText(newText)
        }
        view.onWidthChange = { [weak view] _ in
            guard let view else { return }
            context.coordinator.refreshHeightIfNeeded(for: view)
        }
        let label = UILabel()
        label.text = placeholder
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 9),
        ])
        context.coordinator.placeholderLabel = label
        context.coordinator.lastPlaceholder = placeholder
        context.coordinator.lastTextRevision = textRevision
        context.coordinator.applyProgrammaticText(text, to: view)
        context.coordinator.lastFocusToken = focusToken
        return view
    }

    func updateUIView(_ uiView: ChatPasteTextView, context: Context) {
        context.coordinator.parent = self
        var needsPlaceholderSync = false
        if textRevision != context.coordinator.lastTextRevision {
            context.coordinator.lastTextRevision = textRevision
            context.coordinator.applyProgrammaticText(text, to: uiView)
            needsPlaceholderSync = true
        }
        if placeholder != context.coordinator.lastPlaceholder {
            context.coordinator.lastPlaceholder = placeholder
            context.coordinator.placeholderLabel?.text = placeholder
            needsPlaceholderSync = true
        }
        if needsPlaceholderSync {
            context.coordinator.updatePlaceholder(for: uiView)
        }
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            if focusToken != 0 {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ChatPasteTextView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let height = uiView.fittingHeight(forWidth: width > 1 ? width : UIScreen.main.bounds.width - 100)
        return CGSize(width: width > 1 ? width : UIView.noIntrinsicMetric, height: height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatComposerTextView
        var placeholderLabel: UILabel?
        var lastFocusToken: Int = 0
        var lastTextRevision: Int = -1
        var lastPlaceholder: String = ""
        var lastHeight: CGFloat = -1

        init(_ parent: ChatComposerTextView) {
            self.parent = parent
        }

        func applyProgrammaticText(_ text: String, to textView: ChatPasteTextView) {
            textView.unmarkText()
            if textView.text != text {
                textView.text = text
                textView.markTextDirty()
            }
            if text.isEmpty {
                textView.selectedRange = NSRange(location: 0, length: 0)
            }
            updatePlaceholder(for: textView)
            refreshHeightIfNeeded(for: textView)
        }

        func syncText(_ newText: String) {
            let clipped: String
            if newText.count > ChatComposerLimits.maxBodyLen {
                clipped = String(newText.prefix(ChatComposerLimits.maxBodyLen))
            } else {
                clipped = newText
            }
            parent.onTextChange(clipped)
            parent.onDraftChange()
            if let view = placeholderLabel?.superview as? ChatPasteTextView {
                if view.text != clipped {
                    view.text = clipped
                    view.markTextDirty()
                }
                updatePlaceholder(for: view)
                refreshHeightIfNeeded(for: view)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            let storageLen = textView.textStorage.length
            var text = textView.text ?? ""
            if storageLen > ChatComposerLimits.maxBodyLen {
                let clipped = String(text.prefix(ChatComposerLimits.maxBodyLen))
                if text != clipped {
                    textView.text = clipped
                    text = clipped
                }
            }
            if let pasteView = textView as? ChatPasteTextView {
                pasteView.markTextDirty()
            }
            parent.onTextChange(text)
            parent.onDraftChange()
            placeholderLabel?.isHidden = textView.hasText
            if let pasteView = textView as? ChatPasteTextView {
                refreshHeightIfNeeded(for: pasteView)
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let currentUTF16 = textView.textStorage.length
            if ChatComposerLimits.allowsReplacement(
                currentUTF16Length: currentUTF16,
                rangeLength: range.length,
                replacement: text
            ) {
                return true
            }
            let current = textView.text ?? ""
            return ChatComposerLimits.allowsReplacementExact(
                current: current,
                range: range,
                replacement: text
            )
        }

        func updatePlaceholder(for textView: UITextView) {
            placeholderLabel?.isHidden = textView.hasText
        }

        func refreshHeightIfNeeded(for textView: ChatPasteTextView) {
            let width = textView.bounds.width > 1
                ? textView.bounds.width
                : UIScreen.main.bounds.width - 100
            let height = textView.fittingHeight(forWidth: width)
            let shouldScroll = height >= ChatComposerLimits.maxComposerHeight - 0.5
            if textView.isScrollEnabled != shouldScroll {
                textView.isScrollEnabled = shouldScroll
            }
            guard abs(height - lastHeight) > 0.5 else { return }
            lastHeight = height
            textView.invalidateIntrinsicContentSize()
        }
    }
}

final class ChatPasteTextView: UITextView {
    var onPasteImages: (([UIImage]) -> Void)?
    var onTextChanged: ((String) -> Void)?
    var onWidthChange: ((CGFloat) -> Void)?
    private var lastMeasuredWidth: CGFloat = 0
    private var cachedWidth: CGFloat = -1
    private var cachedHeight: CGFloat = ChatComposerLimits.minComposerHeight
    private var textDirty = true

    func markTextDirty() {
        textDirty = true
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 1 ? bounds.width : UIScreen.main.bounds.width - 100
        let height = fittingHeight(forWidth: width)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        let measureWidth = width > 1 ? width : UIScreen.main.bounds.width - 100
        if !textDirty, abs(measureWidth - cachedWidth) <= 0.5 {
            return cachedHeight
        }
        let size = sizeThatFits(CGSize(width: measureWidth, height: .greatestFiniteMagnitude))
        let height = min(
            max(ceil(size.height), ChatComposerLimits.minComposerHeight),
            ChatComposerLimits.maxComposerHeight
        )
        cachedWidth = measureWidth
        cachedHeight = height
        textDirty = false
        return height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 1, abs(width - lastMeasuredWidth) > 0.5 else { return }
        lastMeasuredWidth = width
        onWidthChange?(width)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return Self.pasteboardHasTextOrImages
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if board.hasImages {
            let images = Self.imagesFromPasteboard(board)
            if !images.isEmpty {
                onPasteImages?(images)
                return
            }
        }
        super.paste(sender)
        let raw = text ?? ""
        let clipped: String
        if raw.count > ChatComposerLimits.maxBodyLen {
            clipped = String(raw.prefix(ChatComposerLimits.maxBodyLen))
            if text != clipped { text = clipped }
        } else {
            clipped = raw
        }
        markTextDirty()
        onTextChanged?(clipped)
    }

    override var pasteConfiguration: UIPasteConfiguration? {
        get {
            UIPasteConfiguration(acceptableTypeIdentifiers: [
                UTType.image.identifier,
                UTType.jpeg.identifier,
                UTType.png.identifier,
                UTType.gif.identifier,
                UTType.plainText.identifier,
                UTType.utf8PlainText.identifier,
            ])
        }
        set {}
    }

    override func paste(itemProviders: [NSItemProvider]) {
        var images: [UIImage] = []
        let group = DispatchGroup()
        var pastedText = false
        for provider in itemProviders.prefix(ChatComposerLimits.maxPasteImages) {
            if provider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    if let image = object as? UIImage {
                        images.append(image)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
            {
                pastedText = true
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    let snippet: String?
                    if let s = item as? String {
                        snippet = s
                    } else if let data = item as? Data {
                        snippet = String(data: data, encoding: .utf8)
                    } else {
                        snippet = nil
                    }
                    if let snippet {
                        DispatchQueue.main.async {
                            self.insertText(snippet)
                            let raw = self.text ?? ""
                            let clipped: String
                            if raw.count > ChatComposerLimits.maxBodyLen {
                                clipped = String(raw.prefix(ChatComposerLimits.maxBodyLen))
                                if self.text != clipped { self.text = clipped }
                            } else {
                                clipped = raw
                            }
                            self.markTextDirty()
                            self.onTextChanged?(clipped)
                        }
                    }
                }
            }
        }
        group.notify(queue: .main) {
            if !images.isEmpty {
                self.onPasteImages?(Array(images.prefix(ChatComposerLimits.maxPasteImages)))
            } else if !pastedText {
                // Fall back to default paste for unsupported providers.
            }
        }
    }

    private static var pasteboardHasTextOrImages: Bool {
        let board = UIPasteboard.general
        return board.hasStrings || board.hasImages || !(board.string ?? "").isEmpty
    }

    private static func imagesFromPasteboard(_ board: UIPasteboard) -> [UIImage] {
        if let images = board.images, !images.isEmpty {
            return Array(images.prefix(ChatComposerLimits.maxPasteImages))
        }
        if let image = board.image {
            return [image]
        }
        return []
    }
}
