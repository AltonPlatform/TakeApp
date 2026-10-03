import Foundation
import UIKit

enum CodeLanguageDetector {
    static func detect(in code: String) -> String {
        let sample = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return "text" }

        let lower = sample.lowercased()

        if sample.contains("import Swift") || sample.contains("struct ") && sample.contains("var ") {
            return "swift"
        }
        if lower.contains("func main(") || sample.contains("package main") || sample.contains("fmt.") {
            return "go"
        }
        if lower.contains("def ") || lower.contains("import numpy") || lower.contains("print(") {
            return "python"
        }
        if lower.contains("function ") || lower.contains("const ") || lower.contains("=>") || lower.contains("console.log") {
            return "javascript"
        }
        if lower.contains("public class ") || lower.contains("system.out.println") {
            return "java"
        }
        if lower.contains("#include") || lower.contains("std::") {
            return "cpp"
        }
        if lower.contains("select ") && lower.contains(" from ") {
            return "sql"
        }
        if sample.hasPrefix("{") && sample.contains(":") && sample.contains("\"") {
            return "json"
        }
        if lower.contains("<!doctype html") || lower.contains("<html") {
            return "html"
        }
        if lower.contains("<?php") {
            return "php"
        }
        if lower.contains("#!/bin/bash") || lower.contains("echo ") && sample.contains("$") {
            return "bash"
        }
        if lower.contains("fn ") && sample.contains("->") {
            return "rust"
        }
        if lower.contains("val ") || lower.contains("fun ") {
            return "kotlin"
        }

        return "text"
    }
}

/// Shared plain-text metrics for composer limits (visible characters, not markdown markup).
enum PostContentMetrics {
    /// Length of rendered plain text — no trim (matches the rich-text editor counter).
    static func plainTextLength(of markdown: String) -> Int {
        RichTextMarkdownConverter.attributedString(from: markdown).string.count
    }

    /// Whether the post would appear empty to the reader (ignoring markdown syntax).
    static func isPlainTextEmpty(_ markdown: String) -> Bool {
        RichTextMarkdownConverter
            .attributedString(from: markdown)
            .string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

enum RichTextMarkdownConverter {
    private static let attributedCache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 200
        cache.totalCostLimit = 10 * 1024 * 1024
        return cache
    }()

    private static let inlineMarkdownRegex: NSRegularExpression? = {
        let pattern = #"(\*\*[^*]+\*\*|\*[^*]+\*|__[^_]+__|~~[^~]+~~|\|\|[^|]+\|\||`[^`]+`|\[[^\]]+\]\([^\)]+\))"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    static func clearCache() {
        attributedCache.removeAllObjects()
    }

    private static func sanitizedLinkURL(_ urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("#") {
            return trimmed
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        guard ["http", "https", "mailto"].contains(scheme) else {
            return nil
        }
        return trimmed
    }

    static func attributedString(from markdown: String, interfaceStyle: UIUserInterfaceStyle = .unspecified) -> NSAttributedString {
        guard !markdown.isEmpty else {
            return RichTextStyle.emptyDocument()
        }

        let cacheKey = "\(interfaceStyle.rawValue)::\(markdown)" as NSString
        if let cached = attributedCache.object(forKey: cacheKey) {
            return cached
        }

        let result = NSMutableAttributedString()
        let blocks = coalesceCodeBlocks(splitBlocks(from: markdown))
        var listCounter = 1

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: RichTextStyle.baseAttributes()))
            }

            switch block.kind {
            case .codeBlock(let language, let code):
                appendCodeBlock(code, language: language, to: result)
            case .blockquote(let text):
                appendBlockquote(text, to: result)
            case .bulletItem(let text):
                appendListItem(text, marker: .bullet, index: 1, to: result)
            case .numberedItem(let text):
                appendListItem(text, marker: .numbered, index: listCounter, to: result)
                listCounter += 1
            case .paragraph(let text):
                appendInlineMarkdown(text, to: result)
                listCounter = 1
            }
        }

        RichTextCodeBlock.normalizeCodeBlocks(in: result)
        guard let immutable = result.copy() as? NSAttributedString else {
            return result
        }
        attributedCache.setObject(immutable, forKey: cacheKey, cost: markdown.utf8.count)
        return immutable
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        RichTextCodeBlock.normalizeCodeBlocks(in: mutable)

        let string = mutable.string as NSString
        guard string.length > 0 else { return "" }

        let codeBlocks = RichTextCodeBlock.mergedBlocks(in: mutable)
        var markdown = ""
        var location = 0
        var numberedIndex = 1
        var previousWasList = false

        while location < string.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let paragraph = string.substring(with: paragraphRange)
            let trimmedParagraph = paragraph.trimmingCharacters(in: .newlines)

            if trimmedParagraph.isEmpty {
                if !markdown.isEmpty {
                    markdown += "\n"
                }
                location = NSMaxRange(paragraphRange)
                numberedIndex = 1
                previousWasList = false
                continue
            }

            if let codeBlock = codeBlocks.first(where: { $0.range.location == paragraphRange.location }) {
                if !markdown.isEmpty {
                    markdown += "\n"
                }
                markdown += "```\(codeBlock.language)\n\(codeBlock.code)\n```"
                location = NSMaxRange(codeBlock.range)
                numberedIndex = 1
                previousWasList = false
                continue
            }

            if codeBlocks.contains(where: { NSLocationInRange(paragraphRange.location, $0.range) }) {
                location = NSMaxRange(paragraphRange)
                continue
            }

            if !markdown.isEmpty, !previousWasList || !isListParagraph(mutable, range: paragraphRange) {
                markdown += "\n"
            }

            if mutable.attribute(RichTextAttribute.blockquote, at: paragraphRange.location, effectiveRange: nil) != nil {
                markdown += "> \(inlineMarkdown(from: mutable, range: paragraphRange))"
                numberedIndex = 1
                previousWasList = false
            } else if let marker = mutable.attribute(
                RichTextAttribute.listMarker,
                at: paragraphRange.location,
                effectiveRange: nil
            ) as? String,
                      let listKind = RichTextListMarker(rawValue: marker) {
                switch listKind {
                case .bullet:
                    markdown += "- \(inlineMarkdown(from: mutable, range: paragraphRange))"
                case .numbered:
                    markdown += "\(numberedIndex). \(inlineMarkdown(from: mutable, range: paragraphRange))"
                    numberedIndex += 1
                }
                previousWasList = true
            } else {
                markdown += inlineMarkdown(from: mutable, range: paragraphRange)
                numberedIndex = 1
                previousWasList = false
            }

            location = NSMaxRange(paragraphRange)
        }

        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum BlockKind {
        case paragraph(String)
        case codeBlock(language: String, code: String)
        case blockquote(String)
        case bulletItem(String)
        case numberedItem(String)
    }

    private struct MarkdownBlock {
        let kind: BlockKind
    }

    private static func coalesceCodeBlocks(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []

        for block in blocks {
            if case .codeBlock(let language, let code) = block.kind,
               case .codeBlock(let previousLanguage, let previousCode)? = result.last?.kind,
               previousLanguage == language {
                result[result.count - 1] = MarkdownBlock(
                    kind: .codeBlock(language: language, code: previousCode + "\n" + code)
                )
            } else {
                result.append(block)
            }
        }

        return result
    }

    private static func splitBlocks(from markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = markdown.startIndex

        while index < markdown.endIndex {
            if markdown[index] == "\n" {
                index = markdown.index(after: index)
                continue
            }

            if markdown[index...].hasPrefix("```") {
                let start = markdown.index(index, offsetBy: 3)
                var language = "text"
                var codeStart = start

                if let lineEnd = markdown[start...].firstIndex(of: "\n") {
                    language = String(markdown[start..<lineEnd]).trimmingCharacters(in: .whitespaces)
                    if language.isEmpty { language = "text" }
                    codeStart = markdown.index(after: lineEnd)
                }

                if let closingRange = markdown[codeStart...].range(of: "\n```") {
                    let code = String(markdown[codeStart..<closingRange.lowerBound])
                    blocks.append(.init(kind: .codeBlock(language: language, code: code)))
                    index = closingRange.upperBound
                    continue
                }
            }

            let lineEnd = markdown[index...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = String(markdown[index..<lineEnd])

            if line.hasPrefix("> ") {
                blocks.append(.init(kind: .blockquote(String(line.dropFirst(2)))))
            } else if line.hasPrefix("- ") {
                blocks.append(.init(kind: .bulletItem(String(line.dropFirst(2)))))
            } else if let numbered = numberedPrefix(in: line) {
                blocks.append(.init(kind: .numberedItem(numbered)))
            } else {
                blocks.append(.init(kind: .paragraph(line)))
            }

            index = lineEnd
        }

        return blocks
    }

    private static func numberedPrefix(in line: String) -> String? {
        guard let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) else {
            return nil
        }
        return String(line[match.upperBound...])
    }

    private static func appendCodeBlock(_ code: String, language: String, to result: NSMutableAttributedString) {
        let start = result.length
        result.append(NSAttributedString(string: code, attributes: RichTextStyle.baseAttributes()))
        let range = NSRange(location: start, length: (code as NSString).length)
        let resolvedLanguage = language == "text" ? CodeLanguageDetector.detect(in: code) : language
        RichTextCodeBlock.applyUnifiedCodeBlock(to: result, range: range, language: resolvedLanguage)
    }

    private static func appendBlockquote(_ text: String, to result: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        paragraph.paragraphSpacing = 4

        var attrs = RichTextStyle.baseAttributes()
        attrs[.foregroundColor] = RichTextStyle.quoteColor
        attrs[.paragraphStyle] = paragraph
        attrs[RichTextAttribute.blockquote] = true

        appendInlineMarkdown(text, baseAttributes: attrs, to: result)
    }

    private static func appendListItem(
        _ text: String,
        marker: RichTextListMarker,
        index: Int,
        to result: NSMutableAttributedString
    ) {
        let textList = NSTextList(
            markerFormat: marker == .bullet ? .disc : .decimal,
            options: 0
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.textLists = [textList]
        paragraph.headIndent = 24
        paragraph.firstLineHeadIndent = 24
        paragraph.paragraphSpacing = 4

        var attrs = RichTextStyle.baseAttributes()
        attrs[.paragraphStyle] = paragraph
        attrs[RichTextAttribute.listMarker] = marker.rawValue

        appendInlineMarkdown(text, baseAttributes: attrs, to: result)
    }

    private static func appendInlineMarkdown(
        _ text: String,
        baseAttributes: [NSAttributedString.Key: Any]? = nil,
        to result: NSMutableAttributedString
    ) {
        let start = result.length
        guard let regex = inlineMarkdownRegex else {
            result.append(NSAttributedString(string: text, attributes: baseAttributes ?? RichTextStyle.baseAttributes()))
            applyMentionsAndHashtags(in: result, range: NSRange(location: start, length: result.length - start))
            return
        }

        let nsText = text as NSString
        var cursor = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        if matches.isEmpty {
            result.append(NSAttributedString(string: text, attributes: baseAttributes ?? RichTextStyle.baseAttributes()))
            applyMentionsAndHashtags(in: result, range: NSRange(location: start, length: result.length - start))
            return
        }

        for match in matches {
            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(NSAttributedString(
                    string: nsText.substring(with: plainRange),
                    attributes: baseAttributes ?? RichTextStyle.baseAttributes()
                ))
            }

            let token = nsText.substring(with: match.range)
            result.append(styledInlineToken(token, baseAttributes: baseAttributes))
            cursor = NSMaxRange(match.range)
        }

        if cursor < nsText.length {
            let trailing = nsText.substring(from: cursor)
            result.append(NSAttributedString(string: trailing, attributes: baseAttributes ?? RichTextStyle.baseAttributes()))
        }

        applyMentionsAndHashtags(in: result, range: NSRange(location: start, length: result.length - start))
    }

    /// Styles `@mentions` and `#hashtags` as tappable blue links (`mention://` / `hashtag://`).
    private static func applyMentionsAndHashtags(in attributed: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0,
              let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])(@[A-Za-z0-9_]{1,64}|#[A-Za-z0-9_]{1,64})"#)
        else { return }

        let matches = regex.matches(in: attributed.string, range: range)
        for match in matches.reversed() {
            let token = (attributed.string as NSString).substring(with: match.range)
            let link: String
            if token.hasPrefix("@") {
                link = "mention://\(String(token.dropFirst()))"
            } else {
                link = "hashtag://\(String(token.dropFirst()))"
            }
            attributed.addAttributes(
                [
                    .foregroundColor: UIColor.link,
                    .link: link
                ],
                range: match.range
            )
        }
    }

    private static func styledInlineToken(
        _ token: String,
        baseAttributes: [NSAttributedString.Key: Any]?
    ) -> NSAttributedString {
        var attrs = baseAttributes ?? RichTextStyle.baseAttributes()

        if token.hasPrefix("**"), token.hasSuffix("**") {
            let content = String(token.dropFirst(2).dropLast(2))
            attrs[.font] = RichTextStyle.bodyFont.withTraits(.traitBold)
            return NSAttributedString(string: content, attributes: attrs)
        }
        if token.hasPrefix("*"), token.hasSuffix("*") {
            let content = String(token.dropFirst().dropLast())
            attrs[.font] = RichTextStyle.bodyFont.withTraits(.traitItalic)
            return NSAttributedString(string: content, attributes: attrs)
        }
        if token.hasPrefix("__"), token.hasSuffix("__") {
            let content = String(token.dropFirst(2).dropLast(2))
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            return NSAttributedString(string: content, attributes: attrs)
        }
        if token.hasPrefix("~~"), token.hasSuffix("~~") {
            let content = String(token.dropFirst(2).dropLast(2))
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            return NSAttributedString(string: content, attributes: attrs)
        }
        if token.hasPrefix("||"), token.hasSuffix("||") {
            let content = String(token.dropFirst(2).dropLast(2))
            attrs[RichTextAttribute.spoiler] = true
            return NSAttributedString(string: content, attributes: attrs)
        }
        if token.hasPrefix("`"), token.hasSuffix("`") {
            let content = String(token.dropFirst().dropLast())
            var attrs = baseAttributes ?? RichTextStyle.baseAttributes()
            attrs.merge(RichTextStyle.inlineCodeAttributes()) { _, new in new }
            return NSAttributedString(string: content, attributes: attrs)
        }
        if token.hasPrefix("["), token.contains("]("), token.hasSuffix(")") {
            if let closingBracket = token.firstIndex(of: "]"),
               let urlStart = token[closingBracket...].firstIndex(of: "("),
               let urlEnd = token.lastIndex(of: ")") {
                let label = String(token[token.index(after: token.startIndex)..<closingBracket])
                let urlString = String(token[token.index(after: urlStart)..<urlEnd])
                if let safeURL = sanitizedLinkURL(urlString) {
                    attrs[.link] = safeURL
                    attrs[.foregroundColor] = UIColor.link
                    return NSAttributedString(string: label, attributes: attrs)
                }
                return NSAttributedString(string: label, attributes: attrs)
            }
        }

        return NSAttributedString(string: token, attributes: attrs)
    }

    private static func inlineMarkdown(from attributed: NSAttributedString, range: NSRange) -> String {
        let string = attributed.string as NSString
        guard range.length > 0 else { return "" }

        var segments: [(NSRange, InlineStyle)] = []
        var index = range.location
        let end = NSMaxRange(range)

        while index < end {
            var effective = NSRange(location: 0, length: 0)
            let subrange = NSRange(location: index, length: end - index)
            let style = inlineStyle(in: attributed, range: subrange, effectiveRange: &effective)
            let clipped = NSRange(
                location: effective.location,
                length: min(effective.length, end - effective.location)
            )
            segments.append((clipped, style))
            index = NSMaxRange(clipped)
        }

        return segments.map { segmentRange, style in
            let raw = string.substring(with: segmentRange)
            return style.wrap(raw)
        }.joined()
    }

    private struct InlineStyle: Equatable {
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var spoiler = false
        var inlineCode = false
        var link: String?

        func wrap(_ text: String) -> String {
            var value = text
            if inlineCode { return "`\(value)`" }
            if let link {
                return "[\(value)](\(link))"
            }
            if spoiler { value = "||\(value)||" }
            if strikethrough { value = "~~\(value)~~" }
            if underline { value = "__\(value)__" }
            if italic { value = "*\(value)*" }
            if bold { value = "**\(value)**" }
            return value
        }
    }

    private static func inlineStyle(
        in attributed: NSAttributedString,
        range: NSRange,
        effectiveRange: inout NSRange
    ) -> InlineStyle {
        var style = InlineStyle()
        let location = range.location

        if attributed.attribute(RichTextAttribute.inlineCode, at: location, effectiveRange: &effectiveRange) != nil {
            style.inlineCode = true
            return style
        }
        if attributed.attribute(RichTextAttribute.spoiler, at: location, effectiveRange: &effectiveRange) != nil {
            style.spoiler = true
        }
        if let link = attributed.attribute(.link, at: location, effectiveRange: &effectiveRange) as? URL {
            style.link = link.absoluteString
            return style
        }
        if let link = attributed.attribute(.link, at: location, effectiveRange: &effectiveRange) as? String {
            style.link = link
            return style
        }
        if attributed.attribute(.strikethroughStyle, at: location, effectiveRange: &effectiveRange) != nil {
            style.strikethrough = true
        }
        if attributed.attribute(.underlineStyle, at: location, effectiveRange: &effectiveRange) != nil {
            style.underline = true
        }
        if let font = attributed.attribute(.font, at: location, effectiveRange: &effectiveRange) as? UIFont {
            style.bold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            style.italic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        }

        return style
    }

    private static func isListParagraph(_ attributed: NSAttributedString, range: NSRange) -> Bool {
        attributed.attribute(RichTextAttribute.listMarker, at: range.location, effectiveRange: nil) != nil
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
