import SwiftUI

struct TakeMarkdownContent: View {
    let content: String
    var onContentTap: (() -> Void)? = nil
    var onMentionTap: ((String) -> Void)? = nil
    var onHashtagTap: ((String) -> Void)? = nil

    var body: some View {
        RichTextContentView(
            markdown: content,
            onContentTap: onContentTap,
            onMentionTap: onMentionTap,
            onHashtagTap: onHashtagTap
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
