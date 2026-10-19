import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Converts clipboard / item-provider images into the same `PostAttachment` shape as PhotosPicker.
enum ComposerPasteAttachments {
    static let maxImages = 10

    static func images(from board: UIPasteboard) -> [UIImage] {
        if let images = board.images, !images.isEmpty {
            return Array(images.prefix(maxImages))
        }
        if let image = board.image {
            return [image]
        }
        return []
    }

    static func loadImages(from providers: [NSItemProvider]) async -> [UIImage] {
        var images: [UIImage] = []
        for provider in providers.prefix(maxImages) {
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            let image: UIImage? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
            if let image {
                images.append(image)
            }
        }
        return images
    }

    static func attachments(
        from images: [UIImage],
        remainingSlots: Int,
        filenamePrefix: String
    ) -> [PostAttachment] {
        guard remainingSlots > 0 else { return [] }
        var loaded: [PostAttachment] = []
        for image in images.prefix(remainingSlots) {
            if let png = image.pngData(), imageHasAlpha(image) {
                loaded.append(
                    PostAttachment(
                        data: png,
                        contentType: "image/png",
                        filename: "\(filenamePrefix)-\(UUID().uuidString).png"
                    )
                )
            } else if let jpeg = image.jpegData(compressionQuality: 0.92) {
                loaded.append(
                    PostAttachment(
                        data: jpeg,
                        contentType: "image/jpeg",
                        filename: "\(filenamePrefix)-\(UUID().uuidString).jpg"
                    )
                )
            }
        }
        return loaded
    }

    private static func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }

    static var pasteboardHasImages: Bool {
        UIPasteboard.general.hasImages
    }

    static var imagePasteConfiguration: UIPasteConfiguration {
        UIPasteConfiguration(acceptableTypeIdentifiers: [
            UTType.image.identifier,
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.gif.identifier,
            UTType.webP.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
        ])
    }
}

/// Multiline draft field that routes pasted images into attachments instead of inline text.
struct ComposerDraftField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var minLines: Int = 1
    var maxLines: Int = 4
    @Binding var isFocused: Bool
    var onPasteImages: ([UIImage]) -> Void
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ComposerDraftTextView {
        let view = ComposerDraftTextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.returnKeyType = onSubmit == nil ? .default : .send
        view.onPasteImages = { images in
            context.coordinator.parent.onPasteImages(images)
        }

        let label = UILabel()
        label.text = placeholder
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
        ])
        context.coordinator.placeholderLabel = label
        context.coordinator.updatePlaceholder(for: view)
        return view
    }

    func updateUIView(_ uiView: ComposerDraftTextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.updatePlaceholder(for: uiView)
        uiView.onPasteImages = { images in
            context.coordinator.parent.onPasteImages(images)
        }

        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerDraftField
        var placeholderLabel: UILabel?

        init(_ parent: ComposerDraftField) {
            self.parent = parent
        }

        func updatePlaceholder(for textView: UITextView) {
            placeholderLabel?.isHidden = !(textView.text ?? "").isEmpty
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textViewDidChange(_ textView: UITextView) {
            let value = textView.text ?? ""
            if parent.text != value {
                parent.text = value
            }
            updatePlaceholder(for: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if text == "\n", let onSubmit = parent.onSubmit {
                onSubmit()
                return false
            }
            return true
        }
    }
}

final class ComposerDraftTextView: UITextView {
    var onPasteImages: (([UIImage]) -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return UIPasteboard.general.hasStrings
                || ComposerPasteAttachments.pasteboardHasImages
                || !(UIPasteboard.general.string ?? "").isEmpty
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if board.hasImages {
            let images = ComposerPasteAttachments.images(from: board)
            if !images.isEmpty {
                onPasteImages?(images)
                return
            }
        }
        super.paste(sender)
    }

    override var pasteConfiguration: UIPasteConfiguration? {
        get { ComposerPasteAttachments.imagePasteConfiguration }
        set {}
    }

    override func paste(itemProviders: [NSItemProvider]) {
        let imageProviders = itemProviders.filter { $0.canLoadObject(ofClass: UIImage.self) }
        let textProviders = itemProviders.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
        }

        if !imageProviders.isEmpty {
            Task { @MainActor in
                let images = await ComposerPasteAttachments.loadImages(from: imageProviders)
                if !images.isEmpty {
                    self.onPasteImages?(images)
                }
            }
            return
        }

        if !textProviders.isEmpty {
            super.paste(itemProviders: textProviders)
        }
    }
}
