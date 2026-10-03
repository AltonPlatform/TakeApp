import XCTest
import UIKit
@testable import AltonApp

final class RichTextMarkdownConverterTests: XCTestCase {
    func testCodeLanguageDetection() {
        XCTAssertEqual(CodeLanguageDetector.detect(in: "import SwiftUI\nstruct Demo {}"), "swift")
        XCTAssertEqual(CodeLanguageDetector.detect(in: "def main():\n    print('hi')"), "python")
        XCTAssertEqual(CodeLanguageDetector.detect(in: "function run() { console.log('x') }"), "javascript")
        XCTAssertEqual(CodeLanguageDetector.detect(in: "plain text"), "text")
    }

    func testMarkdownRoundtripPreservesBold() {
        let source = "Hello **world**"
        let attributed = RichTextMarkdownConverter.attributedString(from: source)
        let roundtrip = RichTextMarkdownConverter.markdown(from: attributed)
        XCTAssertTrue(roundtrip.contains("**world**"))
    }

    func testMarkdownRoundtripPreservesCodeBlock() {
        let source = "```swift\nlet x = 1\n```"
        let attributed = RichTextMarkdownConverter.attributedString(from: source)
        let roundtrip = RichTextMarkdownConverter.markdown(from: attributed)
        XCTAssertTrue(roundtrip.contains("```swift"))
        XCTAssertTrue(roundtrip.contains("let x = 1"))
    }

    func testPlainTextLengthIgnoresMarkdownMarkup() {
        let markdown = "Hello **world**"
        let plain = PostContentMetrics.plainTextLength(of: markdown)
        XCTAssertLessThan(plain, markdown.count)
        XCTAssertEqual(plain, RichTextMarkdownConverter.attributedString(from: markdown).string.count)
    }

    func testPlainTextLimitGateAllowsMarkupHeavyMarkdown() {
        // Many bold markers: markdown string exceeds 4000, plain text stays under.
        let word = "hi"
        var markdown = ""
        while markdown.count < 4100 {
            markdown += "**\(word)** "
        }
        let plain = PostContentMetrics.plainTextLength(of: markdown)
        XCTAssertGreaterThan(markdown.count, PostUseCase.characterLimit)
        XCTAssertLessThanOrEqual(plain, PostUseCase.characterLimit)
    }

    func testActiveMentionUsesCaretNotDocumentEnd() {
        let text = "hi @ann and @jo"
        let caret = (text as NSString).length
        let mention = MentionTyping.activeMention(in: text, utf16Caret: caret)
        XCTAssertEqual(mention?.query, "jo")
        XCTAssertEqual(mention?.range.location, ("hi @ann and " as NSString).length)
    }

    func testCollapsedBoldPinsTypingAttributes() {
        let textView = RichTextTextView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        textView.attributedText = NSAttributedString(string: "Hello", attributes: RichTextStyle.baseAttributes())
        textView.selectedRange = NSRange(location: 5, length: 0)
        textView.typingAttributes = RichTextStyle.baseAttributes()

        RichTextFormatter.apply(.bold, to: textView)

        let font = textView.typingAttributes[.font] as? UIFont
        XCTAssertEqual(font?.fontDescriptor.symbolicTraits.contains(.traitBold), true)
        XCTAssertNotNil(textView.pinnedTypingAttributes)
        XCTAssertEqual(textView.attributedText.string, "Hello")
    }

    func testCodeBlockTogglesOff() {
        let textView = RichTextTextView(frame: CGRect(x: 0, y: 0, width: 240, height: 120))
        textView.attributedText = NSAttributedString(string: "let x = 1", attributes: RichTextStyle.baseAttributes())
        textView.selectedRange = NSRange(location: 0, length: 9)

        RichTextFormatter.apply(.codeBlock, to: textView)
        XCTAssertNotNil(
            textView.attributedText.attribute(RichTextAttribute.codeBlock, at: 0, effectiveRange: nil)
        )

        textView.selectedRange = NSRange(location: 0, length: 9)
        RichTextFormatter.apply(.codeBlock, to: textView)
        XCTAssertNil(
            textView.attributedText.attribute(RichTextAttribute.codeBlock, at: 0, effectiveRange: nil)
        )
    }

    func testEmptyQuoteExitOnReturn() {
        let textView = RichTextTextView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 12
        var attributes = RichTextStyle.baseAttributes()
        attributes[.paragraphStyle] = paragraph
        attributes[RichTextAttribute.blockquote] = true
        textView.attributedText = NSAttributedString(string: "\n", attributes: attributes)
        textView.selectedRange = NSRange(location: 0, length: 0)

        XCTAssertTrue(
            RichTextFormatter.shouldExitEmptyBlock(
                in: textView,
                replacing: NSRange(location: 0, length: 0),
                with: "\n"
            )
        )
    }

    func testIsPlainTextEmptyForWhitespaceOnlyMarkup() {
        XCTAssertTrue(PostContentMetrics.isPlainTextEmpty("   "))
        XCTAssertFalse(PostContentMetrics.isPlainTextEmpty("a"))
    }

    func testHasAlphaDetectsPNGWithTransparency() {
        let opaque = makePNG(alpha: 1.0)
        let transparent = makePNG(alpha: 0.5)
        XCTAssertFalse(DownsampledImage.hasAlpha(data: opaque), "opaque PNG should report no alpha")
        XCTAssertTrue(DownsampledImage.hasAlpha(data: transparent), "semi-transparent PNG should report alpha")
    }

    func testAlphaInfoImpliesAlpha() {
        XCTAssertTrue(DownsampledImage.alphaInfoImpliesAlpha(.premultipliedLast))
        XCTAssertTrue(DownsampledImage.alphaInfoImpliesAlpha(.first))
        XCTAssertFalse(DownsampledImage.alphaInfoImpliesAlpha(.none))
        XCTAssertFalse(DownsampledImage.alphaInfoImpliesAlpha(.noneSkipLast))
    }

    private func makePNG(alpha: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = alpha >= 1
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format)
        let image = renderer.image { ctx in
            UIColor.red.withAlphaComponent(alpha).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.pngData()!
    }
}
