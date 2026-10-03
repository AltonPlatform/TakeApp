import SwiftUI

struct RichTextContentView: View {
    let markdown: String
    var isEditable = false
    var onContentTap: (() -> Void)? = nil
    var onMentionTap: ((String) -> Void)? = nil
    var onHashtagTap: ((String) -> Void)? = nil

    var body: some View {
        RichTextContentRepresentable(
            markdown: markdown,
            isEditable: isEditable,
            onContentTap: onContentTap,
            onMentionTap: onMentionTap,
            onHashtagTap: onHashtagTap
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RichTextContentRepresentable: UIViewRepresentable {
    let markdown: String
    let isEditable: Bool
    let onContentTap: (() -> Void)?
    let onMentionTap: ((String) -> Void)?
    let onHashtagTap: ((String) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onContentTap: onContentTap,
            onMentionTap: onMentionTap,
            onHashtagTap: onHashtagTap
        )
    }

    func makeUIView(context: Context) -> RichTextTextView {
        let textView = RichTextTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isScrollEnabled = isEditable
        textView.backgroundColor = .clear
        textView.displayMode = isEditable ? .editor : .feed
        textView.delegate = context.coordinator
        let coordinator = context.coordinator
        textView.onContentTap = { coordinator.onContentTap?() }
        textView.onLinkTap = { url in
            coordinator.handleLink(url)
        }
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: RichTextTextView, context: Context) {
        context.coordinator.onContentTap = onContentTap
        context.coordinator.onMentionTap = onMentionTap
        context.coordinator.onHashtagTap = onHashtagTap
        let coordinator = context.coordinator
        textView.delegate = coordinator
        textView.onContentTap = { coordinator.onContentTap?() }
        textView.onLinkTap = { url in
            coordinator.handleLink(url)
        }

        let interfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let cacheKey = "\(interfaceStyle.rawValue)::\(markdown)"
        guard context.coordinator.lastCacheKey != cacheKey else { return }
        context.coordinator.lastCacheKey = cacheKey

        textView.attributedText = RichTextMarkdownConverter.attributedString(
            from: markdown,
            interfaceStyle: interfaceStyle
        )
        textView.setNeedsDisplay()
        textView.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var lastCacheKey = ""
        var onContentTap: (() -> Void)?
        var onMentionTap: ((String) -> Void)?
        var onHashtagTap: ((String) -> Void)?

        init(
            onContentTap: (() -> Void)?,
            onMentionTap: ((String) -> Void)?,
            onHashtagTap: ((String) -> Void)?
        ) {
            self.onContentTap = onContentTap
            self.onMentionTap = onMentionTap
            self.onHashtagTap = onHashtagTap
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content else {
                return defaultAction
            }
            switch url.scheme?.lowercased() {
            case "mention", "hashtag":
                return UIAction { [weak self] _ in
                    _ = self?.handleLink(url)
                }
            default:
                return defaultAction
            }
        }

        @discardableResult
        func handleLink(_ url: URL) -> Bool {
            switch url.scheme?.lowercased() {
            case "mention":
                let username = mentionUsername(from: url)
                if !username.isEmpty {
                    onMentionTap?(username)
                }
                return false
            case "hashtag":
                let tag = hashtagValue(from: url)
                if !tag.isEmpty {
                    onHashtagTap?(tag)
                }
                return false
            default:
                return true
            }
        }

        private func mentionUsername(from url: URL) -> String {
            if let host = url.host, !host.isEmpty { return host }
            return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        private func hashtagValue(from url: URL) -> String {
            if let host = url.host, !host.isEmpty { return host }
            return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }
}
