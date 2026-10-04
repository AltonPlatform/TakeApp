import SwiftUI
import UIKit

/// A format action staged by the composer chrome. The monotonic `id` lets the editor
/// de-duplicate it (like `PendingComposerEdit.id`) when the binding is still set on a
/// re-entrant `updateUIView` pass before the deferred binding clear has landed.
struct PendingFormatAction: Equatable {
    var id: UInt64
    var action: RichTextFormatAction
}

struct MarkdownEditorView: View {
    @Binding var text: String
    @Binding var isPreviewMode: Bool
    let characterLimit: Int
    var editorMinHeight: CGFloat = 180
    var showsCharacterCount = true
    var style: MarkdownEditorStyle = .boxed
    var placeholder: String = ""
    var autoFocus = false
    var expandsToFitContent = false
    var focusRequestID = 0
    var onFormatStateChange: (RichTextFormatState) -> Void = { _ in }
    var onSelectionLengthChange: (Int) -> Void = { _ in }
    var onPlainCaretChange: (String, Int) -> Void = { _, _ in }
    @Binding var pendingEdit: PendingComposerEdit?
    @Binding var pendingFormatAction: PendingFormatAction?

    enum MarkdownEditorStyle {
        case boxed
        case composer
    }

    @State private var richContent = RichTextStyle.emptyDocument()
    @State private var fittedHeight: CGFloat = 0
    @State private var pasteCodeHint: RichTextPasteCodeHint?
    @State private var applyPasteCodeHint = false

    init(
        text: Binding<String>,
        isPreviewMode: Binding<Bool>,
        characterLimit: Int,
        editorMinHeight: CGFloat = 180,
        showsCharacterCount: Bool = true,
        style: MarkdownEditorStyle = .boxed,
        placeholder: String = "",
        autoFocus: Bool = false,
        expandsToFitContent: Bool = false,
        focusRequestID: Int = 0,
        onFormatStateChange: @escaping (RichTextFormatState) -> Void = { _ in },
        onSelectionLengthChange: @escaping (Int) -> Void = { _ in },
        onPlainCaretChange: @escaping (String, Int) -> Void = { _, _ in },
        pendingEdit: Binding<PendingComposerEdit?> = .constant(nil),
        pendingFormatAction: Binding<PendingFormatAction?> = .constant(nil)
    ) {
        _text = text
        _isPreviewMode = isPreviewMode
        self.characterLimit = characterLimit
        self.editorMinHeight = editorMinHeight
        self.showsCharacterCount = showsCharacterCount
        self.style = style
        self.placeholder = placeholder
        self.autoFocus = autoFocus
        self.expandsToFitContent = expandsToFitContent
        self.focusRequestID = focusRequestID
        self.onFormatStateChange = onFormatStateChange
        self.onSelectionLengthChange = onSelectionLengthChange
        self.onPlainCaretChange = onPlainCaretChange
        _pendingEdit = pendingEdit
        _pendingFormatAction = pendingFormatAction
    }

    private var resolvedEditorHeight: CGFloat {
        max(editorMinHeight, fittedHeight)
    }

    private var showsPlaceholder: Bool {
        !placeholder.isEmpty
            && !isPreviewMode
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .composer ? 8 : 12) {
            if isPreviewMode {
                RichTextContentView(markdown: text)
                    .frame(minHeight: editorMinHeight)
                    .padding(style == .composer ? 0 : 8)
                    .background(
                        style == .composer ? Color.clear : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: style == .composer ? 0 : 12)
                    )
            } else {
                editorStack

                if let pasteCodeHint {
                    PasteCodeHintBanner(
                        preview: pasteCodeHint.preview,
                        onConvert: { applyPasteCodeHint = true },
                        onDismiss: { self.pasteCodeHint = nil }
                    )
                }
            }

            if showsCharacterCount {
                HStack {
                    Text("\(remainingCharacters) characters left")
                        .font(.caption)
                        .foregroundStyle(remainingCharacters < 0 ? .red : .secondary)
                    Spacer()
                    Text("\(plainTextCount)/\(characterLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: text) { _, newValue in
            guard newValue.isEmpty else { return }
            pasteCodeHint = nil
        }
    }

    private var editorStack: some View {
        let stack = ZStack(alignment: .topLeading) {
            RichTextEditorView(
                content: $richContent,
                markdownSource: text,
                pasteCodeHint: $pasteCodeHint,
                applyPasteCodeHint: $applyPasteCodeHint,
                pendingFormatAction: $pendingFormatAction,
                style: style,
                autoFocus: autoFocus,
                expandsToFitContent: expandsToFitContent,
                focusRequestID: focusRequestID,
                characterLimit: characterLimit,
                onFormatStateChange: onFormatStateChange,
                onSelectionLengthChange: onSelectionLengthChange,
                onPlainCaretChange: onPlainCaretChange,
                pendingEdit: $pendingEdit,
                onHeightChange: { height in
                    guard expandsToFitContent else { return }
                    if abs(fittedHeight - height) > 1 {
                        fittedHeight = height
                    }
                },
                onMarkdownChange: { markdown in
                    if text != markdown {
                        text = markdown
                    }
                }
            )

            if showsPlaceholder {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .padding(.top, 1)
            }
        }

        return Group {
            if expandsToFitContent {
                stack.frame(height: resolvedEditorHeight, alignment: .top)
            } else {
                stack.frame(minHeight: editorMinHeight, alignment: .top)
            }
        }
    }

    private var plainTextCount: Int {
        // Prefer live editor buffer; fall back to shared metrics when previewing.
        if isPreviewMode {
            return PostContentMetrics.plainTextLength(of: text)
        }
        return richContent.string.count
    }

    private var remainingCharacters: Int {
        characterLimit - plainTextCount
    }
}

private struct PasteCodeHintBanner: View {
    let preview: String
    let onConvert: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.plaintext")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Looks like code")
                    .font(.subheadline.weight(.semibold))
                Text("Convert pasted text to a code block for better formatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button("Convert", action: onConvert)
                .font(.subheadline.weight(.semibold))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// Internal (not private) so @testable tests can reach `Coordinator`.
struct RichTextEditorView: UIViewRepresentable {
    @Binding var content: NSAttributedString
    var markdownSource: String
    @Binding var pasteCodeHint: RichTextPasteCodeHint?
    @Binding var applyPasteCodeHint: Bool
    @Binding var pendingFormatAction: PendingFormatAction?
    var style: MarkdownEditorView.MarkdownEditorStyle = .boxed
    var autoFocus = false
    var expandsToFitContent = false
    var focusRequestID = 0
    var characterLimit: Int
    var onFormatStateChange: (RichTextFormatState) -> Void
    var onSelectionLengthChange: (Int) -> Void
    var onPlainCaretChange: (String, Int) -> Void
    @Binding var pendingEdit: PendingComposerEdit?
    var onHeightChange: (CGFloat) -> Void
    let onMarkdownChange: (String) -> Void

    func makeUIView(context: Context) -> RichTextTextView {
        let textView = RichTextTextView()
        textView.delegate = context.coordinator
        applyStyle(to: textView)
        textView.expandsToFitContent = expandsToFitContent
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.allowsEditingTextAttributes = true
        let initial = RichTextMarkdownConverter.attributedString(from: markdownSource)
        textView.attributedText = initial
        textView.typingAttributes = RichTextStyle.baseAttributes()
        context.coordinator.lastExportedMarkdown = RichTextMarkdownConverter.markdown(from: initial)
        context.coordinator.textView = textView
        context.coordinator.characterLimit = characterLimit
        textView.onFittedHeightChange = { [weak coordinator = context.coordinator] height in
            coordinator?.reportHeight(height)
        }
        if autoFocus {
            context.coordinator.scheduleFocus(on: textView)
        }
        return textView
    }

    func dismantleUIView(_ textView: RichTextTextView, coordinator: Coordinator) {
        coordinator.cancelFocus()
        textView.resignFirstResponder()
    }

    private func applyStyle(to textView: RichTextTextView) {
        switch style {
        case .boxed:
            textView.backgroundColor = UIColor.secondarySystemBackground
            textView.layer.cornerRadius = 12
            textView.layer.masksToBounds = true
            textView.displayMode = .editor
            textView.textContainerInset = UIEdgeInsets(top: 12, left: 2, bottom: 12, right: 2)
        case .composer:
            textView.backgroundColor = .clear
            textView.layer.cornerRadius = 0
            textView.layer.masksToBounds = false
            textView.displayMode = .composer
            textView.textContainerInset = .zero
        }
    }

    func updateUIView(_ textView: RichTextTextView, context: Context) {
        applyStyle(to: textView)
        textView.expandsToFitContent = expandsToFitContent
        context.coordinator.characterLimit = characterLimit
        context.coordinator.onMarkdownChange = onMarkdownChange
        context.coordinator.onFormatStateChange = onFormatStateChange
        context.coordinator.onSelectionLengthChange = onSelectionLengthChange
        context.coordinator.onPlainCaretChange = onPlainCaretChange
        context.coordinator.onHeightChange = onHeightChange
        textView.onFittedHeightChange = { [weak coordinator = context.coordinator] height in
            coordinator?.reportHeight(height)
        }

        if focusRequestID != context.coordinator.lastFocusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            if focusRequestID > 0 {
                textView.becomeFirstResponder()
            }
        }

        // Every pass gets a fresh token; anything staged in an earlier pass is stale.
        context.coordinator.bumpToken()
        context.coordinator.importExternalMarkdownIfNeeded(markdownSource, into: textView)
        if let edit = pendingEdit {
            // Stage + apply in this pass. Re-application in a re-entrant pass (binding not yet
            // cleared) is prevented by the id guard (`consumedEditID`), NOT by clearing the
            // binding here: writing @State during updateUIView is illegal ("modifying state
            // during view update"), so the binding clear is deferred. Only clear if the binding
            // still holds *this* edit - a newer edit staged in the meantime must survive.
            context.coordinator.stagePendingEdit(edit)
            context.coordinator.applyPendingEditIfNeeded(to: textView)
            DispatchQueue.main.async {
                if pendingEdit?.id == edit.id {
                    pendingEdit = nil
                }
            }
        }

        if applyPasteCodeHint {
            context.coordinator.applyPasteCodeHint()
            DispatchQueue.main.async {
                applyPasteCodeHint = false
            }
        }

        if let action = pendingFormatAction {
            // Same stage -> apply -> deferred-clear sequence as pendingEdit; the id guard
            // (`consumedFormatActionID`) is what prevents double-application.
            context.coordinator.stagePendingFormatAction(action)
            context.coordinator.applyPendingFormatActionIfNeeded(to: textView)
            DispatchQueue.main.async {
                if pendingFormatAction?.id == action.id {
                    pendingFormatAction = nil
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            content: $content,
            pasteCodeHint: $pasteCodeHint,
            onMarkdownChange: onMarkdownChange,
            onFormatStateChange: onFormatStateChange,
            onSelectionLengthChange: onSelectionLengthChange,
            onPlainCaretChange: onPlainCaretChange,
            onHeightChange: onHeightChange
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var content: NSAttributedString
        @Binding var pasteCodeHint: RichTextPasteCodeHint?
        var onMarkdownChange: (String) -> Void
        var onFormatStateChange: (RichTextFormatState) -> Void
        var onSelectionLengthChange: (Int) -> Void
        var onPlainCaretChange: (String, Int) -> Void
        var onHeightChange: (CGFloat) -> Void
        var consumedEditID = 0
        /// Highest format-action id already applied; anything `<=` is a duplicate (the binding
        /// clear is deferred, so a re-entrant pass can still see the same action).
        private(set) var consumedFormatActionID: UInt64 = 0
        var lastExportedMarkdown = ""
        var characterLimit = 0
        var lastFocusRequestID = 0
        weak var textView: RichTextTextView?
        var isApplyingFormat = false
        var isImporting = false
        var isExporting = false

        // Binding-loop race guards (see updateUIView).
        /// Bumped once per updateUIView pass; anything staged in an older pass is stale.
        private(set) var currentToken: UInt64 = 0
        private(set) var pendingEditToken: UInt64 = 0
        private(set) var pendingFormatToken: UInt64 = 0
        /// True while local (typed / applied) mutations have not yet been echoed to the binding.
        /// While true the editor's text is the source of truth and external imports are skipped.
        ///
        /// NOTE: currently this duplicates `isExporting` exactly (set together, cleared together,
        /// zero behavioral difference). The spec intended it to detect *external* `string`
        /// changes via the token gate; that is deferred to the final whole-branch review, which
        /// decides whether to make it meaningful or collapse it into `isExporting`.
        private(set) var isAuthoritative = false
        private(set) var pendingEdit: PendingComposerEdit?
        private(set) var pendingFormatAction: PendingFormatAction?
        /// Number of exports queued to the binding that have not landed yet.
        private var inFlightExports = 0

        private var previousSelection = NSRange(location: 0, length: 0)
        private var isRestoringSelection = false
        private var lastEditedRange = NSRange(location: 0, length: 0)
        private var lastEditWasPaste = false
        private var didTypeSincePin = false
        private var focusTask: Task<Void, Never>?
        private var lastReportedHeight: CGFloat = -1
        private var lastFormatState = RichTextFormatState()
        private var lastSelectionLength = -1

        init(
            content: Binding<NSAttributedString>,
            pasteCodeHint: Binding<RichTextPasteCodeHint?>,
            onMarkdownChange: @escaping (String) -> Void,
            onFormatStateChange: @escaping (RichTextFormatState) -> Void,
            onSelectionLengthChange: @escaping (Int) -> Void,
            onPlainCaretChange: @escaping (String, Int) -> Void,
            onHeightChange: @escaping (CGFloat) -> Void
        ) {
            _content = content
            _pasteCodeHint = pasteCodeHint
            self.onMarkdownChange = onMarkdownChange
            self.onFormatStateChange = onFormatStateChange
            self.onSelectionLengthChange = onSelectionLengthChange
            self.onPlainCaretChange = onPlainCaretChange
            self.onHeightChange = onHeightChange
        }

        func bumpToken() {
            currentToken &+= 1
        }

        /// Test-only hook: forces the ownership flag. Not called from production code; prod sets
        /// it in `textViewDidChange` / the begin/end editing delegate callbacks.
        func setAuthoritative(_ value: Bool) {
            isAuthoritative = value
        }

        func stagePendingEdit(_ edit: PendingComposerEdit?) {
            pendingEdit = edit
            pendingEditToken = currentToken
        }

        /// Consumes the staged edit. The local mirror is always cleared (benign: a Coordinator
        /// property, not SwiftUI state). Applies only when it is fresh and its id has not been
        /// applied before. The id guard (`consumedEditID`) is the real defense against
        /// re-application when the `@Binding` clear is deferred; the token gate is a second
        /// layer that discards an edit staged in an earlier `updateUIView` pass.
        @discardableResult
        func applyPendingEditIfNeeded(to textView: UITextView) -> Bool {
            guard let edit = pendingEdit else { return false }
            pendingEdit = nil
            guard pendingEditToken >= currentToken else { return false }
            guard edit.id != consumedEditID else { return false }
            consumedEditID = edit.id
            apply(edit, to: textView)
            return true
        }

        func stagePendingFormatAction(_ action: PendingFormatAction?) {
            pendingFormatAction = action
            pendingFormatToken = currentToken
        }

        /// Consumes the staged format action. Same contract as `applyPendingEditIfNeeded`:
        /// the id guard (`consumedFormatActionID`) makes a re-delivered action a no-op.
        @discardableResult
        func applyPendingFormatActionIfNeeded(to textView: RichTextTextView) -> Bool {
            guard let pending = pendingFormatAction else { return false }
            pendingFormatAction = nil
            guard pendingFormatToken >= currentToken else { return false }
            guard pending.id > consumedFormatActionID else { return false }
            consumedFormatActionID = pending.id
            let action = pending.action
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            isApplyingFormat = true
            RichTextFormatter.apply(action, to: textView)
            isApplyingFormat = false
            if textView.pinnedTypingAttributes == nil {
                textViewDidChange(textView)
            }
            publishChromeState(from: textView)
            return true
        }

        func apply(_ edit: PendingComposerEdit, to textView: UITextView) {
            if let insertion = edit.insert {
                insertPlainText(insertion, into: textView, smartMention: true)
            }
            if let replacement = edit.replacement {
                replacePlainText(replacement, in: textView)
            }
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        private func insertPlainText(_ raw: String, into textView: UITextView, smartMention: Bool) {
            let mutable = NSMutableAttributedString(
                attributedString: textView.attributedText ?? RichTextStyle.emptyDocument()
            )
            let selected = textView.selectedRange
            let location = min(max(selected.location, 0), mutable.length)
            let length = min(selected.length, mutable.length - location)
            var insertion = raw
            if smartMention, raw == "@", length == 0, location > 0 {
                let previous = (mutable.string as NSString).substring(
                    with: NSRange(location: location - 1, length: 1)
                )
                if previous != " " && previous != "\n" {
                    insertion = " @"
                }
            }
            let attributes = textView.typingAttributes.isEmpty
                ? RichTextStyle.baseAttributes()
                : textView.typingAttributes
            mutable.replaceCharacters(
                in: NSRange(location: location, length: length),
                with: NSAttributedString(string: insertion, attributes: attributes)
            )
            commit(mutable, caret: location + (insertion as NSString).length, in: textView)
        }

        private func replacePlainText(_ replacement: ComposerTextReplacement, in textView: UITextView) {
            let mutable = NSMutableAttributedString(
                attributedString: textView.attributedText ?? RichTextStyle.emptyDocument()
            )
            let location = min(max(replacement.location, 0), mutable.length)
            let length = min(max(replacement.length, 0), mutable.length - location)
            var attributes = RichTextStyle.baseAttributes()
            // Monochrome ink (not `UIColor.link`). Deliberately NOT bold: a bold font
            // would serialize the mention as `**@name**` in the markdown converter.
            attributes[.foregroundColor] = ComposerMentionStyle.uiColor
            mutable.replaceCharacters(
                in: NSRange(location: location, length: length),
                with: NSAttributedString(string: replacement.text, attributes: attributes)
            )
            (textView as? RichTextTextView)?.pinnedTypingAttributes = nil
            textView.typingAttributes = RichTextStyle.baseAttributes()
            commit(mutable, caret: location + (replacement.text as NSString).length, in: textView)
        }

        private func commit(_ mutable: NSMutableAttributedString, caret: Int, in textView: UITextView) {
            textView.attributedText = mutable
            textView.selectedRange = NSRange(location: min(max(caret, 0), mutable.length), length: 0)
            textViewDidChange(textView)
            publishChromeState(from: textView)
            (textView as? RichTextTextView)?.scrollComposerCaretToVisible()
            reportCaret(from: textView)
        }

        private var lastReportedCaret: (String, Int)?

        func reportCaret(from textView: UITextView) {
            guard !isImporting else { return }
            let plain = textView.attributedText?.string ?? ""
            let caret = textView.selectedRange.length == 0 ? textView.selectedRange.location : -1
            if lastReportedCaret?.0 == plain, lastReportedCaret?.1 == caret { return }
            lastReportedCaret = (plain, caret)
            let callback = onPlainCaretChange
            DispatchQueue.main.async {
                callback(plain, caret)
            }
        }

        func reportHeight(_ height: CGFloat) {
            let next = ceil(height)
            guard abs(next - lastReportedHeight) > 1 else { return }
            lastReportedHeight = next
            DispatchQueue.main.async { [onHeightChange] in
                onHeightChange(next)
            }
        }

        func importExternalMarkdownIfNeeded(_ markdown: String, into textView: RichTextTextView) {
            // `live` is a full attributed-string -> markdown traversal; it is lazy so the early
            // return below (every keystroke during an export burst) never pays for it.
            performImport(
                markdown,
                live: RichTextMarkdownConverter.markdown(
                    from: textView.attributedText ?? RichTextStyle.emptyDocument()
                ),
                into: textView
            )
        }

        /// Testable core: `current` is the editor's live markdown.
        func importExternalMarkdownIfNeeded(newMarkdown: String, current: String) {
            guard let textView else { return }
            performImport(newMarkdown, live: current, into: textView)
        }

        private func performImport(
            _ markdown: String,
            live liveProvider: @autoclosure () -> String,
            into textView: RichTextTextView
        ) {
            if isExporting || isImporting || isAuthoritative { return }
            let live = liveProvider()

            if live == markdown || markdown == lastExportedMarkdown {
                lastExportedMarkdown = live
                return
            }
            // Editor is ahead of the binding (export has not landed yet). Don't wipe typed text.
            if textView.isFirstResponder, live == lastExportedMarkdown, !markdown.isEmpty {
                return
            }

            let imported = RichTextMarkdownConverter.attributedString(from: markdown)
            let oldLength = textView.attributedText?.length ?? 0
            let caret = textView.selectedRange
            let caretAtEnd = caret.length == 0 && caret.location >= oldLength
            isImporting = true
            textView.attributedText = imported
            textView.pinnedTypingAttributes = nil
            let location = caretAtEnd ? imported.length : min(caret.location, imported.length)
            textView.selectedRange = NSRange(location: max(location, 0), length: 0)
            textView.typingAttributes = typingAttributes(near: textView.selectedRange.location, in: imported)
            isImporting = false

            let normalized = RichTextMarkdownConverter.markdown(from: imported)
            lastExportedMarkdown = normalized
            textView.setNeedsDisplay()
            guard normalized != markdown else { return }
            let publish = onMarkdownChange
            DispatchQueue.main.async {
                publish(normalized)
            }
        }

        func publishChromeState(from textView: UITextView) {
            let state = RichTextFormatter.formatState(in: textView)
            if state != lastFormatState {
                lastFormatState = state
                let publish = onFormatStateChange
                DispatchQueue.main.async {
                    publish(state)
                }
            }
            let length = textView.selectedRange.length
            if length != lastSelectionLength {
                lastSelectionLength = length
                let publish = onSelectionLengthChange
                DispatchQueue.main.async {
                    publish(length)
                }
            }
        }

        func scheduleFocus(on textView: RichTextTextView) {
            cancelFocus()
            focusTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                textView.becomeFirstResponder()
                if !textView.isFirstResponder {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    textView.becomeFirstResponder()
                }
            }
        }

        func cancelFocus() {
            focusTask?.cancel()
            focusTask = nil
        }

        func applyPasteCodeHint() {
            guard let hint = pasteCodeHint, let textView else { return }
            RichTextFormatter.applyPasteCodeBlock(hint, to: textView)
            pasteCodeHint = nil
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if RichTextFormatter.shouldExitEmptyBlock(in: textView, replacing: range, with: text) {
                RichTextFormatter.exitBlock(in: textView)
                return false
            }

            if text == "\n", let attributes = RichTextFormatter.continuationAttributes(in: textView, at: range) {
                let currentCount = textView.attributedText?.string.count ?? 0
                if characterLimit > 0, currentCount >= characterLimit {
                    return false
                }
                textView.typingAttributes = attributes
                if let richTextView = textView as? RichTextTextView {
                    richTextView.pinnedTypingAttributes = attributes
                    richTextView.pinnedTypingAnchor = NSRange(location: range.location + 1, length: 0)
                    richTextView.pinGraceUntil = CACurrentMediaTime() + 0.2
                }
                didTypeSincePin = true
                insertClipped("\n", replacing: range, in: textView)
                return false
            }

            let current = textView.attributedText?.string ?? ""
            let ns = current as NSString
            let removed = range.location < ns.length
                ? ns.substring(with: NSIntersectionRange(range, NSRange(location: 0, length: ns.length))).count
                : 0
            let nextCount = current.count - removed + text.count
            if characterLimit > 0, nextCount > characterLimit {
                let allowed = characterLimit - (current.count - removed)
                guard allowed > 0 else { return false }
                insertClipped(String(text.prefix(allowed)), replacing: range, in: textView)
                return false
            }

            if (textView as? RichTextTextView)?.pinnedTypingAttributes != nil, !text.isEmpty {
                didTypeSincePin = true
            }
            lastEditedRange = NSRange(location: range.location, length: (text as NSString).length)
            lastEditWasPaste = text.count > 1
            if lastEditWasPaste {
                pasteCodeHint = nil
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isImporting else { return }
            let attributed = textView.attributedText ?? RichTextStyle.emptyDocument()
            let markdown = RichTextMarkdownConverter.markdown(from: attributed)
            lastExportedMarkdown = markdown
            textView.setNeedsDisplay()
            (textView as? RichTextTextView)?.scrollComposerCaretToVisible()
            if let richTextView = textView as? RichTextTextView, richTextView.expandsToFitContent {
                reportHeight(richTextView.measuredContentHeight())
            }

            let wasPaste = lastEditWasPaste
            lastEditWasPaste = false
            let hint = wasPaste
                ? RichTextFormatter.detectPasteCodeCandidate(in: textView, near: lastEditedRange)
                : nil
            let publish = onMarkdownChange
            // Count in-flight exports: with rapid edits an earlier export landing must not
            // release ownership while later ones are still queued.
            inFlightExports += 1
            isAuthoritative = true
            isExporting = true
            DispatchQueue.main.async {
                self.content = attributed
                publish(markdown)
                if wasPaste {
                    self.pasteCodeHint = hint
                }
                self.inFlightExports = max(self.inFlightExports - 1, 0)
                if self.inFlightExports == 0 {
                    self.isExporting = false
                    self.isAuthoritative = false
                }
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isAuthoritative = inFlightExports > 0
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isAuthoritative = inFlightExports > 0
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            defer { reportCaret(from: textView) }
            var newRange = textView.selectedRange

            if !isRestoringSelection,
               RichTextSelection.shouldRestorePartialCodeSelection(
                   previous: previousSelection,
                   new: newRange,
                   in: textView.attributedText
               ) {
                isRestoringSelection = true
                textView.selectedRange = previousSelection
                isRestoringSelection = false
                newRange = previousSelection
            } else {
                previousSelection = newRange
            }

            if let richTextView = textView as? RichTextTextView,
               let pinned = richTextView.pinnedTypingAttributes {
                let withinGrace = CACurrentMediaTime() < richTextView.pinGraceUntil
                let sameAnchor = NSEqualRanges(newRange, richTextView.pinnedTypingAnchor)
                if isApplyingFormat || didTypeSincePin || withinGrace || sameAnchor {
                    textView.typingAttributes = pinned
                    if didTypeSincePin {
                        richTextView.pinnedTypingAnchor = newRange
                        didTypeSincePin = false
                    }
                    publishChromeState(from: textView)
                    return
                }
                richTextView.pinnedTypingAttributes = nil
            }

            textView.typingAttributes = typingAttributes(
                near: textView.selectedRange.location,
                in: textView.attributedText ?? RichTextStyle.emptyDocument()
            )
            publishChromeState(from: textView)
        }

        private func insertClipped(_ text: String, replacing range: NSRange, in textView: UITextView) {
            let mutable = NSMutableAttributedString(
                attributedString: textView.attributedText ?? RichTextStyle.emptyDocument()
            )
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: mutable.length))
            mutable.replaceCharacters(
                in: safe,
                with: NSAttributedString(string: text, attributes: textView.typingAttributes)
            )
            let inserted = (text as NSString).length
            textView.attributedText = mutable
            textView.selectedRange = NSRange(location: safe.location + inserted, length: 0)
            lastEditedRange = NSRange(location: safe.location, length: inserted)
            lastEditWasPaste = text.count > 1
            textViewDidChange(textView)
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let inlineMenu = UIMenu(
                title: "Text",
                options: .displayInline,
                children: RichTextFormatAction.inlineActions.map { action in
                    makeAction(action, textView: textView)
                }
            )

            let blockMenu = UIMenu(
                title: "Block",
                options: .displayInline,
                children: RichTextFormatAction.blockActions.map { action in
                    makeAction(action, textView: textView)
                }
            )

            let formatMenu = UIMenu(title: "Format", children: [inlineMenu, blockMenu])
            return UIMenu(children: [formatMenu] + suggestedActions)
        }

        private func makeAction(_ action: RichTextFormatAction, textView: UITextView) -> UIAction {
            UIAction(
                title: action.title,
                image: UIImage(systemName: action.icon)
            ) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.isApplyingFormat = true
                RichTextFormatter.apply(action, to: textView)
                self.isApplyingFormat = false
                if (textView as? RichTextTextView)?.pinnedTypingAttributes == nil {
                    self.textViewDidChange(textView)
                }
                self.publishChromeState(from: textView)
                textView.setNeedsDisplay()
            }
        }

        private func typingAttributes(
            near location: Int,
            in attributed: NSAttributedString
        ) -> [NSAttributedString.Key: Any] {
            guard attributed.length > 0 else {
                return RichTextStyle.baseAttributes()
            }

            let index = location <= 0
                ? 0
                : min(location - 1, attributed.length - 1)
            var effective = NSRange(location: 0, length: 0)
            var attributes = attributed.attributes(at: index, effectiveRange: &effective)

            if attributes[RichTextAttribute.codeBlock] != nil {
                attributes[.font] = RichTextStyle.codeBlockFont
                attributes[.foregroundColor] = UIColor.label
            } else if attributes[RichTextAttribute.inlineCode] != nil {
                attributes.merge(RichTextStyle.inlineCodeAttributes()) { _, new in new }
            } else if attributes[.font] == nil {
                attributes[.font] = RichTextStyle.bodyFont
            }

            if attributes[.foregroundColor] == nil {
                attributes[.foregroundColor] = UIColor.label
            }

            attributes.removeValue(forKey: .backgroundColor)
            return attributes
        }
    }
}
