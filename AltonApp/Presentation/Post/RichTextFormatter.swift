import UIKit

enum RichTextFormatAction: String, CaseIterable, Identifiable {
    case bold
    case italic
    case underline
    case strikethrough
    case spoiler
    case code
    case codeBlock
    case quote
    case bulletList
    case numberedList
    case link

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .spoiler: "eye.slash"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "doc.plaintext"
        case .quote: "text.quote"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .link: "link"
        }
    }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .spoiler: "Spoiler"
        case .code: "Code"
        case .codeBlock: "Code Block"
        case .quote: "Quote"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .link: "Link"
        }
    }

    static var inlineActions: [RichTextFormatAction] {
        [.bold, .italic, .underline, .strikethrough, .spoiler, .code, .link]
    }

    static var blockActions: [RichTextFormatAction] {
        [.quote, .codeBlock, .bulletList, .numberedList]
    }

    var isInline: Bool {
        switch self {
        case .bold, .italic, .underline, .strikethrough, .spoiler, .code, .link:
            true
        case .codeBlock, .quote, .bulletList, .numberedList:
            false
        }
    }
}

struct RichTextFormatState: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var spoiler = false
    var code = false
    var link = false
    var quote = false
    var bulletList = false
    var numberedList = false
    var codeBlock = false

    func isActive(_ action: RichTextFormatAction) -> Bool {
        switch action {
        case .bold: bold
        case .italic: italic
        case .underline: underline
        case .strikethrough: strikethrough
        case .spoiler: spoiler
        case .code: code
        case .link: link
        case .quote: quote
        case .bulletList: bulletList
        case .numberedList: numberedList
        case .codeBlock: codeBlock
        }
    }
}

struct RichTextPasteCodeHint: Equatable {
    let range: NSRange
    let preview: String
}

enum RichTextSelection {
    static func shouldRestorePartialCodeSelection(
        previous: NSRange,
        new: NSRange,
        in attributed: NSAttributedString?
    ) -> Bool {
        guard previous.length > 0, new.length > previous.length else { return false }
        guard let attributed, attributed.length > 0 else { return false }
        guard rangeIsInsideCodeBlock(previous, in: attributed) else { return false }

        let string = attributed.string as NSString
        let paragraphRange = string.paragraphRange(for: new)
        guard NSEqualRanges(new, paragraphRange) else { return false }
        guard !NSEqualRanges(previous, paragraphRange) else { return false }
        guard NSLocationInRange(previous.location, paragraphRange) else { return false }
        return NSMaxRange(previous) <= NSMaxRange(paragraphRange)
    }

    private static func rangeIsInsideCodeBlock(_ range: NSRange, in attributed: NSAttributedString) -> Bool {
        guard range.location < attributed.length else { return false }
        let index = min(max(range.location, 0), attributed.length - 1)
        return attributed.attribute(RichTextAttribute.codeBlock, at: index, effectiveRange: nil) != nil
    }
}

enum RichTextFormatter {
    static func detectPasteCodeCandidate(in textView: UITextView, near range: NSRange) -> RichTextPasteCodeHint? {
        guard let blockRange = codeCandidateRange(in: textView, near: range) else { return nil }

        let text = (textView.attributedText?.string as NSString?)?.substring(with: blockRange) ?? ""
        let preview = text
            .split(whereSeparator: \.isNewline)
            .first
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.count > 48 ? String(trimmed.prefix(48)) + "…" : trimmed
            } ?? ""

        guard !preview.isEmpty else { return nil }
        return RichTextPasteCodeHint(range: blockRange, preview: preview)
    }

    static func applyPasteCodeBlock(_ hint: RichTextPasteCodeHint, to textView: UITextView) {
        let mutable = NSMutableAttributedString(
            attributedString: textView.attributedText ?? RichTextStyle.emptyDocument()
        )
        let text = (mutable.string as NSString).substring(with: hint.range)
        applyCodeBlockAttributes(to: mutable, range: hint.range, text: text)
        replaceContent(of: textView, with: mutable, selectedRange: hint.range)
    }

    static func formatState(in textView: UITextView) -> RichTextFormatState {
        let storage = textView.attributedText ?? RichTextStyle.emptyDocument()
        let selected = textView.selectedRange
        let pinned = (textView as? RichTextTextView)?.pinnedTypingAttributes
        let typing = pinned ?? textView.typingAttributes

        let inlineSource: [NSAttributedString.Key: Any]
        if selected.length == 0 || storage.length == 0 {
            inlineSource = typing.isEmpty ? RichTextStyle.baseAttributes() : typing
        } else {
            let index = min(selected.location, storage.length - 1)
            inlineSource = storage.attributes(at: index, effectiveRange: nil)
        }

        var state = RichTextFormatState()
        if let font = inlineSource[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            state.bold = traits.contains(.traitBold)
            state.italic = traits.contains(.traitItalic)
        }
        state.underline = inlineSource[.underlineStyle] != nil
        state.strikethrough = inlineSource[.strikethroughStyle] != nil
        state.spoiler = inlineSource[RichTextAttribute.spoiler] != nil
        state.code = inlineSource[RichTextAttribute.inlineCode] != nil
        state.link = inlineSource[.link] != nil

        guard storage.length > 0 else {
            state.quote = typing[RichTextAttribute.blockquote] != nil
            if let marker = typing[RichTextAttribute.listMarker] as? String {
                state.bulletList = marker == RichTextListMarker.bullet.rawValue
                state.numberedList = marker == RichTextListMarker.numbered.rawValue
            }
            state.codeBlock = typing[RichTextAttribute.codeBlock] != nil
            return state
        }

        let probe = selected.location >= storage.length
            ? storage.length - 1
            : min(max(selected.location, 0), storage.length - 1)
        state.quote = storage.attribute(RichTextAttribute.blockquote, at: probe, effectiveRange: nil) != nil
        if let marker = storage.attribute(RichTextAttribute.listMarker, at: probe, effectiveRange: nil) as? String {
            state.bulletList = marker == RichTextListMarker.bullet.rawValue
            state.numberedList = marker == RichTextListMarker.numbered.rawValue
        }
        state.codeBlock = storage.attribute(RichTextAttribute.codeBlock, at: probe, effectiveRange: nil) != nil
        return state
    }

    static func shouldExitEmptyBlock(in textView: UITextView, replacing range: NSRange, with text: String) -> Bool {
        guard text == "\n", range.length == 0 else { return false }
        let storage = textView.attributedText ?? RichTextStyle.emptyDocument()
        let string = storage.string as NSString
        guard string.length > 0, range.location <= string.length else { return false }

        let probe = min(range.location, string.length - 1)
        let paragraph = string.paragraphRange(for: NSRange(location: probe, length: 0))
        let body = string.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.isEmpty else { return false }

        let index = min(paragraph.location, string.length - 1)
        if storage.attribute(RichTextAttribute.codeBlock, at: index, effectiveRange: nil) != nil {
            return false
        }
        let isQuote = storage.attribute(RichTextAttribute.blockquote, at: index, effectiveRange: nil) != nil
        let isList = storage.attribute(RichTextAttribute.listMarker, at: index, effectiveRange: nil) != nil
        return isQuote || isList
    }

    /// Attributes for the next line when Return is pressed inside a quote, list, or code block.
    static func continuationAttributes(
        in textView: UITextView,
        at range: NSRange
    ) -> [NSAttributedString.Key: Any]? {
        guard range.length == 0 else { return nil }
        let storage = textView.attributedText ?? RichTextStyle.emptyDocument()
        let string = storage.string as NSString
        guard string.length > 0, range.location <= string.length else { return nil }

        let probe = min(range.location, string.length - 1)
        let paragraph = string.paragraphRange(for: NSRange(location: probe, length: 0))
        guard paragraph.location < string.length else { return nil }

        var attributes = storage.attributes(at: paragraph.location, effectiveRange: nil)
        let isCode = attributes[RichTextAttribute.codeBlock] != nil
        let isQuote = attributes[RichTextAttribute.blockquote] != nil
        let isList = attributes[RichTextAttribute.listMarker] != nil
        guard isCode || isQuote || isList else { return nil }

        if !isCode {
            let body = string.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
        }

        attributes.removeValue(forKey: .backgroundColor)
        return attributes
    }

    static func exitBlock(in textView: UITextView) {
        mutate(textView: textView, range: textView.selectedRange, byParagraph: true) { mutable, paragraphRange in
            clearBlockStyles(in: paragraphRange, mutable: mutable)
        }
    }

    static func apply(_ action: RichTextFormatAction, to textView: UITextView) {
        let selectedRange = textView.selectedRange
        guard selectedRange.location != NSNotFound else { return }

        if selectedRange.length == 0, action.isInline, action != .link {
            toggleTyping(action, textView: textView)
            return
        }

        if selectedRange.length == 0, !action.isInline, (textView.attributedText?.length ?? 0) == 0 {
            pinEmptyBlock(action, textView: textView)
            return
        }

        switch action {
        case .bold:
            toggleTrait(.traitBold, in: selectedRange, textView: textView)
        case .italic:
            toggleTrait(.traitItalic, in: selectedRange, textView: textView)
        case .underline:
            toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: selectedRange, textView: textView)
        case .strikethrough:
            toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: selectedRange, textView: textView)
        case .spoiler:
            toggleCustomAttribute(RichTextAttribute.spoiler, in: selectedRange, textView: textView) { range, mutable in
                let enabled = mutable.attribute(RichTextAttribute.spoiler, at: range.location, effectiveRange: nil) != nil
                if enabled {
                    mutable.removeAttribute(RichTextAttribute.spoiler, range: range)
                } else {
                    mutable.addAttribute(RichTextAttribute.spoiler, value: true, range: range)
                }
            }
        case .code:
            toggleInlineCode(in: selectedRange, textView: textView)
        case .codeBlock:
            applyCodeBlock(in: selectedRange, textView: textView)
        case .quote:
            toggleBlock(.quote, in: selectedRange, textView: textView)
        case .bulletList:
            toggleBlock(.bullet, in: selectedRange, textView: textView)
        case .numberedList:
            toggleBlock(.numbered, in: selectedRange, textView: textView)
        case .link:
            promptForLink(in: selectedRange, textView: textView)
        }
    }

    private static func codeCandidateRange(in textView: UITextView, near range: NSRange) -> NSRange? {
        let mutable = NSMutableAttributedString(
            attributedString: textView.attributedText ?? RichTextStyle.emptyDocument()
        )
        let string = mutable.string as NSString
        guard string.length > 0 else { return nil }

        let safeLocation = min(max(range.location, 0), string.length - 1)
        let paragraphRange = string.paragraphRange(for: NSRange(location: safeLocation, length: 0))
        guard mutable.attribute(RichTextAttribute.codeBlock, at: paragraphRange.location, effectiveRange: nil) == nil else {
            return nil
        }

        var start = paragraphRange.location
        var end = NSMaxRange(paragraphRange)

        while start > 0 {
            let previous = string.paragraphRange(for: NSRange(location: start - 1, length: 0))
            let previousText = string.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines)
            if previousText.isEmpty { break }
            if mutable.attribute(RichTextAttribute.codeBlock, at: previous.location, effectiveRange: nil) != nil { break }
            guard looksLikeCode(previousText) else { break }
            start = previous.location
        }

        while end < string.length {
            let next = string.paragraphRange(for: NSRange(location: end, length: 0))
            let nextText = string.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines)
            if nextText.isEmpty { break }
            if mutable.attribute(RichTextAttribute.codeBlock, at: next.location, effectiveRange: nil) != nil { break }
            guard looksLikeCode(nextText) else { break }
            end = NSMaxRange(next)
        }

        let blockRange = NSRange(location: start, length: end - start)
        let blockText = string.substring(with: blockRange)
        guard blockText.contains("\n") || looksLikeCode(blockText) else { return nil }
        return blockRange
    }

    private enum BlockKind {
        case quote
        case bullet
        case numbered
    }

    private static func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits, in range: NSRange, textView: UITextView) {
        mutate(textView: textView, range: range) { mutable, effectiveRange in
            mutable.enumerateAttribute(.font, in: effectiveRange) { value, subrange, _ in
                let current = (value as? UIFont) ?? RichTextStyle.bodyFont
                var traits = current.fontDescriptor.symbolicTraits
                if traits.contains(trait) {
                    traits.remove(trait)
                } else {
                    traits.insert(trait)
                }
                let updated = current.withTraits(traits)
                mutable.addAttribute(.font, value: updated, range: subrange)
            }
        }
    }

    private static func toggleAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        in range: NSRange,
        textView: UITextView
    ) {
        mutate(textView: textView, range: range) { mutable, effectiveRange in
            let enabled = mutable.attribute(key, at: effectiveRange.location, effectiveRange: nil) != nil
            if enabled {
                mutable.removeAttribute(key, range: effectiveRange)
            } else {
                mutable.addAttribute(key, value: value, range: effectiveRange)
            }
        }
    }

    private static func toggleCustomAttribute(
        _ key: NSAttributedString.Key,
        in range: NSRange,
        textView: UITextView,
        update: (NSRange, NSMutableAttributedString) -> Void
    ) {
        mutate(textView: textView, range: range) { mutable, effectiveRange in
            update(effectiveRange, mutable)
        }
    }

    private static func toggleInlineCode(in range: NSRange, textView: UITextView) {
        mutate(textView: textView, range: range) { mutable, effectiveRange in
            let enabled = mutable.attribute(RichTextAttribute.inlineCode, at: effectiveRange.location, effectiveRange: nil) != nil
            if enabled {
                mutable.removeAttribute(RichTextAttribute.inlineCode, range: effectiveRange)
                mutable.addAttribute(.font, value: RichTextStyle.bodyFont, range: effectiveRange)
                mutable.addAttribute(.foregroundColor, value: UIColor.label, range: effectiveRange)
            } else {
                clearInlineStyles(in: effectiveRange, mutable: mutable)
                RichTextStyle.applyInlineCode(to: mutable, range: effectiveRange)
            }
        }
    }

    private static func applyCodeBlock(in range: NSRange, textView: UITextView) {
        mutate(textView: textView, range: range) { mutable, effectiveRange in
            let string = mutable.string as NSString
            guard string.length > 0 else { return }
            let expanded = RichTextCodeBlock.expandToParagraphRange(effectiveRange, in: string)
            let probe = min(max(expanded.location, 0), string.length - 1)
            let enabled = mutable.attribute(RichTextAttribute.codeBlock, at: probe, effectiveRange: nil) != nil
            if enabled {
                let block = RichTextCodeBlock.mergedBlocks(in: mutable).first { candidate in
                    NSIntersectionRange(candidate.range, expanded).length > 0
                        || NSLocationInRange(probe, candidate.range)
                }
                clearBlockStyles(in: block?.range ?? expanded, mutable: mutable)
            } else {
                let text = string.substring(with: expanded)
                applyCodeBlockAttributes(to: mutable, range: expanded, text: text)
            }
        }
    }

    private static func toggleTyping(_ action: RichTextFormatAction, textView: UITextView) {
        var attrs = (textView as? RichTextTextView)?.pinnedTypingAttributes ?? textView.typingAttributes
        if attrs[.font] == nil {
            attrs[.font] = RichTextStyle.bodyFont
        }
        if attrs[.foregroundColor] == nil {
            attrs[.foregroundColor] = UIColor.label
        }

        switch action {
        case .bold:
            attrs[.font] = fontByToggling(.traitBold, on: attrs[.font] as? UIFont)
        case .italic:
            attrs[.font] = fontByToggling(.traitItalic, on: attrs[.font] as? UIFont)
        case .underline:
            if attrs[.underlineStyle] != nil {
                attrs.removeValue(forKey: .underlineStyle)
            } else {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
        case .strikethrough:
            if attrs[.strikethroughStyle] != nil {
                attrs.removeValue(forKey: .strikethroughStyle)
            } else {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
        case .spoiler:
            if attrs[RichTextAttribute.spoiler] != nil {
                attrs.removeValue(forKey: RichTextAttribute.spoiler)
            } else {
                attrs[RichTextAttribute.spoiler] = true
            }
        case .code:
            if attrs[RichTextAttribute.inlineCode] != nil {
                attrs.removeValue(forKey: RichTextAttribute.inlineCode)
                attrs[.font] = RichTextStyle.bodyFont
                attrs[.foregroundColor] = UIColor.label
            } else {
                attrs.removeValue(forKey: .underlineStyle)
                attrs.removeValue(forKey: .strikethroughStyle)
                attrs.removeValue(forKey: RichTextAttribute.spoiler)
                attrs.merge(RichTextStyle.inlineCodeAttributes()) { _, new in new }
            }
        default:
            break
        }

        pinTypingAttributes(attrs, on: textView)
    }

    private static func pinEmptyBlock(_ action: RichTextFormatAction, textView: UITextView) {
        let current = (textView as? RichTextTextView)?.pinnedTypingAttributes ?? textView.typingAttributes
        switch action {
        case .quote:
            if current[RichTextAttribute.blockquote] != nil {
                pinTypingAttributes(RichTextStyle.baseAttributes(), on: textView)
            } else {
                pinTypingAttributes(quoteTypingAttributes(), on: textView)
            }
        case .bulletList:
            pinListTyping(.bullet, current: current, textView: textView)
        case .numberedList:
            pinListTyping(.numbered, current: current, textView: textView)
        case .codeBlock:
            if current[RichTextAttribute.codeBlock] != nil {
                pinTypingAttributes(RichTextStyle.baseAttributes(), on: textView)
            } else {
                pinTypingAttributes(
                    RichTextStyle.codeBlockAttributes(language: "text", isFirstParagraph: true),
                    on: textView
                )
            }
        default:
            break
        }
    }

    private static func pinListTyping(
        _ marker: RichTextListMarker,
        current: [NSAttributedString.Key: Any],
        textView: UITextView
    ) {
        let active = (current[RichTextAttribute.listMarker] as? String) == marker.rawValue
        if active {
            pinTypingAttributes(RichTextStyle.baseAttributes(), on: textView)
            return
        }
        let textList = NSTextList(
            markerFormat: marker == .bullet ? .disc : .decimal,
            options: 0
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.textLists = [textList]
        paragraph.headIndent = 24
        paragraph.firstLineHeadIndent = 24
        var attrs = RichTextStyle.baseAttributes()
        attrs[.paragraphStyle] = paragraph
        attrs[RichTextAttribute.listMarker] = marker.rawValue
        pinTypingAttributes(attrs, on: textView)
    }

    private static func quoteTypingAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        var attrs = RichTextStyle.baseAttributes()
        attrs[.foregroundColor] = RichTextStyle.quoteColor
        attrs[.paragraphStyle] = paragraph
        attrs[RichTextAttribute.blockquote] = true
        return attrs
    }

    private static func pinTypingAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        on textView: UITextView
    ) {
        textView.typingAttributes = attributes
        guard let richTextView = textView as? RichTextTextView else { return }
        richTextView.pinnedTypingAttributes = attributes
        richTextView.pinnedTypingAnchor = textView.selectedRange
        richTextView.pinGraceUntil = CACurrentMediaTime() + 0.2
    }

    private static func fontByToggling(_ trait: UIFontDescriptor.SymbolicTraits, on font: UIFont?) -> UIFont {
        let current = font ?? RichTextStyle.bodyFont
        var traits = current.fontDescriptor.symbolicTraits
        if traits.contains(trait) {
            traits.remove(trait)
        } else {
            traits.insert(trait)
        }
        return current.withTraits(traits)
    }

    private static func applyCodeBlockAttributes(
        to mutable: NSMutableAttributedString,
        range: NSRange,
        text: String
    ) {
        clearBlockStyles(in: range, mutable: mutable)
        RichTextStyle.applyCodeBlock(to: mutable, range: range, text: text)
    }

    private static func toggleBlock(_ kind: BlockKind, in range: NSRange, textView: UITextView) {
        mutate(textView: textView, range: range, byParagraph: true) { mutable, paragraphRange in
            switch kind {
            case .quote:
                let enabled = mutable.attribute(RichTextAttribute.blockquote, at: paragraphRange.location, effectiveRange: nil) != nil
                clearBlockStyles(in: paragraphRange, mutable: mutable)
                guard !enabled else { return }

                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = 12
                paragraph.headIndent = 12
                paragraph.paragraphSpacing = 4
                mutable.addAttribute(RichTextAttribute.blockquote, value: true, range: paragraphRange)
                mutable.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
                mutable.addAttribute(.foregroundColor, value: RichTextStyle.quoteColor, range: paragraphRange)

            case .bullet:
                let enabled = (mutable.attribute(RichTextAttribute.listMarker, at: paragraphRange.location, effectiveRange: nil) as? String) == RichTextListMarker.bullet.rawValue
                clearBlockStyles(in: paragraphRange, mutable: mutable)
                guard !enabled else { return }
                applyList(marker: .bullet, to: paragraphRange, mutable: mutable)

            case .numbered:
                let enabled = (mutable.attribute(RichTextAttribute.listMarker, at: paragraphRange.location, effectiveRange: nil) as? String) == RichTextListMarker.numbered.rawValue
                clearBlockStyles(in: paragraphRange, mutable: mutable)
                guard !enabled else { return }
                applyList(marker: .numbered, to: paragraphRange, mutable: mutable)
            }
        }
    }

    private static func applyList(marker: RichTextListMarker, to range: NSRange, mutable: NSMutableAttributedString) {
        let textList = NSTextList(
            markerFormat: marker == .bullet ? .disc : .decimal,
            options: 0
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.textLists = [textList]
        paragraph.headIndent = 24
        paragraph.firstLineHeadIndent = 24
        paragraph.paragraphSpacing = 4
        mutable.addAttribute(.paragraphStyle, value: paragraph, range: range)
        mutable.addAttribute(RichTextAttribute.listMarker, value: marker.rawValue, range: range)
    }

    private static func promptForLink(in range: NSRange, textView: UITextView) {
        guard let presenter = textView.window?.rootViewController?.topMostViewController else { return }

        let alert = UIAlertController(title: "Add Link", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { _ in
            let url = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let link = url.isEmpty ? "https://" : url
            if range.length == 0 {
                let mutable = NSMutableAttributedString(
                    attributedString: textView.attributedText ?? RichTextStyle.emptyDocument()
                )
                var attributes = RichTextStyle.baseAttributes()
                attributes[.link] = link
                attributes[.foregroundColor] = UIColor.link
                let insertAt = min(range.location, mutable.length)
                mutable.insert(NSAttributedString(string: link, attributes: attributes), at: insertAt)
                let inserted = (link as NSString).length
                replaceContent(
                    of: textView,
                    with: mutable,
                    selectedRange: NSRange(location: insertAt + inserted, length: 0)
                )
            } else {
                mutate(textView: textView, range: range) { mutable, effectiveRange in
                    clearInlineStyles(in: effectiveRange, mutable: mutable)
                    mutable.addAttribute(.link, value: link, range: effectiveRange)
                    mutable.addAttribute(.foregroundColor, value: UIColor.link, range: effectiveRange)
                }
            }
        })

        presenter.present(alert, animated: true)
    }

    private static func mutate(
        textView: UITextView,
        range: NSRange,
        byParagraph: Bool = false,
        update: (NSMutableAttributedString, NSRange) -> Void
    ) {
        (textView as? RichTextTextView)?.pinnedTypingAttributes = nil
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? RichTextStyle.emptyDocument())
        let effectiveRange: NSRange

        if byParagraph {
            effectiveRange = (mutable.string as NSString).paragraphRange(for: range)
        } else if range.length == 0 {
            effectiveRange = range
        } else {
            effectiveRange = range
        }

        update(mutable, effectiveRange)
        replaceContent(of: textView, with: mutable, selectedRange: effectiveRange)
    }

    private static func replaceContent(
        of textView: UITextView,
        with mutable: NSMutableAttributedString,
        selectedRange: NSRange
    ) {
        let preserved = NSRange(
            location: selectedRange.location,
            length: min(selectedRange.length, mutable.length - selectedRange.location)
        )
        textView.attributedText = mutable
        textView.selectedRange = preserved
        textView.delegate?.textViewDidChange?(textView)
        (textView as? RichTextTextView)?.setNeedsDisplay()
    }

    private static func clearInlineStyles(in range: NSRange, mutable: NSMutableAttributedString) {
        mutable.removeAttribute(RichTextAttribute.inlineCode, range: range)
        mutable.removeAttribute(RichTextAttribute.spoiler, range: range)
        mutable.removeAttribute(.link, range: range)
        mutable.removeAttribute(.underlineStyle, range: range)
        mutable.removeAttribute(.strikethroughStyle, range: range)
        mutable.addAttribute(.font, value: RichTextStyle.bodyFont, range: range)
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: range)
    }

    private static func clearBlockStyles(in range: NSRange, mutable: NSMutableAttributedString) {
        mutable.removeAttribute(RichTextAttribute.codeBlock, range: range)
        mutable.removeAttribute(RichTextAttribute.codeLanguage, range: range)
        mutable.removeAttribute(RichTextAttribute.blockquote, range: range)
        mutable.removeAttribute(RichTextAttribute.listMarker, range: range)
        mutable.removeAttribute(.paragraphStyle, range: range)
        mutable.addAttribute(.font, value: RichTextStyle.bodyFont, range: range)
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: range)
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let indicators = ["{", "}", ";", "func ", "def ", "class ", "import ", "const ", "=>", "#include", "SELECT "]
        return indicators.contains { text.contains($0) }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostViewController
        }
        if let navigationController {
            return navigationController.visibleViewController?.topMostViewController ?? navigationController
        }
        if let tabBarController {
            return tabBarController.selectedViewController?.topMostViewController ?? tabBarController
        }
        return self
    }
}
