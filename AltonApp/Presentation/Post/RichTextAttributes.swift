import UIKit

enum RichTextAttribute {
    static let inlineCode = NSAttributedString.Key("richText.inlineCode")
    static let codeBlock = NSAttributedString.Key("richText.codeBlock")
    static let codeLanguage = NSAttributedString.Key("richText.codeLanguage")
    static let spoiler = NSAttributedString.Key("richText.spoiler")
    static let blockquote = NSAttributedString.Key("richText.blockquote")
    static let listMarker = NSAttributedString.Key("richText.listMarker")
}

enum RichTextListMarker: String {
    case bullet
    case numbered
}

enum RichTextStyle {
    static var bodyFont: UIFont {
        PostTypography.uiBodyFont
    }

    static var codeFont: UIFont {
        if let menlo = UIFont(name: "Menlo-Regular", size: bodyFont.pointSize * 0.92) {
            return menlo
        }
        return UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize * 0.92, weight: .regular)
    }

    static var codeBlockFont: UIFont {
        if let menlo = UIFont(name: "Menlo-Regular", size: bodyFont.pointSize * 0.88) {
            return menlo
        }
        return UIFont.monospacedSystemFont(ofSize: bodyFont.pointSize * 0.88, weight: .regular)
    }

    static var quoteColor: UIColor {
        UIColor.secondaryLabel
    }

    static var inlineCodeForeground: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.98, green: 0.62, blue: 0.72, alpha: 1)
                : UIColor(red: 0.78, green: 0.12, blue: 0.36, alpha: 1)
        }
    }

    static var inlineCodeFill: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.1)
                : UIColor.black.withAlphaComponent(0.06)
        }
    }

    static var codeBlockFill: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
                : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        }
    }

    static var codeBlockBorder: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.08)
        }
    }

    static var spoilerBackground: UIColor {
        UIColor.secondaryLabel.withAlphaComponent(0.28)
    }

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: PostColor.uiLabelPrimary,
        ]
    }

    static func emptyDocument() -> NSAttributedString {
        NSAttributedString(string: "", attributes: baseAttributes())
    }

    static let codeBlockHeaderHeight: CGFloat = 34

    static func codeBlockParagraphStyle(isFirstParagraph: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.tailIndent = -12
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = isFirstParagraph ? codeBlockHeaderHeight + 6 : 0
        return style
    }

    static func inlineCodeAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: inlineCodeForeground,
            RichTextAttribute.inlineCode: true,
        ]
    }

    static func codeBlockAttributes(language: String, isFirstParagraph: Bool = true) -> [NSAttributedString.Key: Any] {
        [
            .font: codeBlockFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: codeBlockParagraphStyle(isFirstParagraph: isFirstParagraph),
            RichTextAttribute.codeBlock: true,
            RichTextAttribute.codeLanguage: language,
        ]
    }

    static func applyCodeBlock(to mutable: NSMutableAttributedString, range: NSRange, text: String) {
        let language = CodeLanguageDetector.detect(in: text)
        RichTextCodeBlock.applyUnifiedCodeBlock(to: mutable, range: range, language: language)
    }

    static func applyInlineCode(to mutable: NSMutableAttributedString, range: NSRange) {
        mutable.addAttributes(inlineCodeAttributes(), range: range)
    }
}
