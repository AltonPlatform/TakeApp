import UIKit

enum RichTextCodeBlock {
    struct Block {
        let range: NSRange
        let language: String
        let code: String
    }

    static func mergedBlocks(in attributed: NSAttributedString) -> [Block] {
        let string = attributed.string as NSString
        guard string.length > 0 else { return [] }

        var blocks: [Block] = []
        var location = 0

        while location < string.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let trimmed = string.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                location = NSMaxRange(paragraphRange)
                continue
            }

            guard attributed.attribute(RichTextAttribute.codeBlock, at: paragraphRange.location, effectiveRange: nil) != nil else {
                location = NSMaxRange(paragraphRange)
                continue
            }

            var mergedRange = paragraphRange
            let blockLanguage = resolvedLanguage(
                attributed.attribute(RichTextAttribute.codeLanguage, at: paragraphRange.location, effectiveRange: nil)
            )
            location = NSMaxRange(paragraphRange)

            while location < string.length {
                let nextParagraph = string.paragraphRange(for: NSRange(location: location, length: 0))
                let nextTrimmed = string.substring(with: nextParagraph).trimmingCharacters(in: .whitespacesAndNewlines)

                if nextTrimmed.isEmpty { break }
                guard attributed.attribute(RichTextAttribute.codeBlock, at: nextParagraph.location, effectiveRange: nil) != nil else {
                    break
                }

                let nextLanguage = resolvedLanguage(
                    attributed.attribute(RichTextAttribute.codeLanguage, at: nextParagraph.location, effectiveRange: nil)
                )
                guard nextLanguage == blockLanguage else { break }

                mergedRange = NSRange(
                    location: mergedRange.location,
                    length: NSMaxRange(nextParagraph) - mergedRange.location
                )
                location = NSMaxRange(nextParagraph)
            }

            let code = string.substring(with: mergedRange).trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(Block(range: mergedRange, language: blockLanguage, code: code))
        }

        return blocks
    }

    static func normalizeCodeBlocks(in mutable: NSMutableAttributedString) {
        for block in mergedBlocks(in: mutable).reversed() {
            applyUnifiedCodeBlock(to: mutable, range: block.range, language: block.language)
        }
    }

    static func applyUnifiedCodeBlock(
        to mutable: NSMutableAttributedString,
        range: NSRange,
        language: String
    ) {
        let string = mutable.string as NSString
        let resolvedLanguage = language == "text" ? CodeLanguageDetector.detect(in: string.substring(with: range)) : language

        var location = range.location
        let end = NSMaxRange(range)
        var isFirstParagraph = true

        while location < end {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let clipped = NSIntersectionRange(paragraphRange, range)
            guard clipped.length > 0 else { break }

            mutable.removeAttribute(RichTextAttribute.blockquote, range: clipped)
            mutable.removeAttribute(RichTextAttribute.listMarker, range: clipped)
            mutable.removeAttribute(.paragraphStyle, range: clipped)
            mutable.addAttributes(
                RichTextStyle.codeBlockAttributes(language: resolvedLanguage, isFirstParagraph: isFirstParagraph),
                range: clipped
            )

            isFirstParagraph = false
            location = NSMaxRange(paragraphRange)
        }
    }

    static func expandToParagraphRange(_ range: NSRange, in string: NSString) -> NSRange {
        guard string.length > 0 else { return range }
        let start = string.paragraphRange(for: range).location
        let endLocation = max(range.location + max(range.length, 1) - 1, range.location)
        let end = NSMaxRange(string.paragraphRange(for: NSRange(location: min(endLocation, string.length - 1), length: 0)))
        return NSRange(location: start, length: end - start)
    }

    private static func resolvedLanguage(_ value: Any?) -> String {
        (value as? String) ?? "text"
    }
}
