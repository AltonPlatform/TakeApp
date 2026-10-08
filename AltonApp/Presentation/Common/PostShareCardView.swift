import CoreImage.CIFilterBuiltins
import SwiftUI

/// Branded share card rendered via `ImageRenderer` for the system share sheet / Stories sticker.
struct PostShareCardView: View {
    let payload: PostSharePayload
    var posterImage: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Take")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if let qr = qrImage {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 56, height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                if let excerpt = payload.textExcerpt?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                }

                Text(payload.linkTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text(payload.url.host.map { "\($0)\(payload.url.path)" } ?? payload.url.absoluteString)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            .padding(28)
        }
        .frame(width: 1080, height: 1920)
    }

    @ViewBuilder
    private var background: some View {
        if let posterImage {
            Image(uiImage: posterImage)
                .resizable()
                .scaledToFill()
                .frame(width: 1080, height: 1920)
                .clipped()
                .overlay(Color.black.opacity(0.45))
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.16),
                    Color(red: 0.18, green: 0.08, blue: 0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var qrImage: UIImage? {
        PostShareCardRenderer.qrCode(for: payload.url.absoluteString, dimension: 220)
    }
}

enum PostShareCardRenderer {
    @MainActor
    static func render(payload: PostSharePayload, posterImage: UIImage? = nil) -> UIImage? {
        let view = PostShareCardView(payload: payload, posterImage: posterImage)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage
    }

    static func qrCode(for string: String, dimension: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
