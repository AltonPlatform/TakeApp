import CoreGraphics
import SwiftUI
import UIKit

enum MarkupColorSampler {
    /// Sample a single pixel from an upright CGImage (top-left origin).
    static func sample(image: CGImage, normalizedPoint: CGPoint) -> String? {
        let x = min(max(Int(normalizedPoint.x * CGFloat(image.width)), 0), image.width - 1)
        let y = min(max(Int(normalizedPoint.y * CGFloat(image.height)), 0), image.height - 1)
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let ctx = CPUImageIO.makeBitmapContext(width: 1, height: 1) else {
            return nil
        }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: 4)
        return String(format: "#%02X%02X%02X", ptr[0], ptr[1], ptr[2])
    }
}

/// Hue × brightness strip for long-press color picking.
struct MarkupHueBrightnessStrip: View {
    @Binding var colorHex: String
    var onFinished: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: (0..<12).map { i in
                        Color(hue: Double(i) / 12, saturation: 1, brightness: 1)
                    },
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .overlay {
                    LinearGradient(
                        colors: [.white, .clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(0.55)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let hx = min(max(value.location.x / geo.size.width, 0), 1)
                        let by = min(max(value.location.y / geo.size.height, 0), 1)
                        let hue = hx
                        let brightness = 1 - by
                        let sat: Double = by < 0.15 ? by / 0.15 : 1
                        let ui = UIColor(hue: hue, saturation: sat, brightness: brightness, alpha: 1)
                        colorHex = ui.markupHexString()
                    }
                    .onEnded { _ in onFinished() }
            )
        }
        .frame(height: 44)
    }
}

struct MarkupEyedropperOverlay: View {
    let image: CGImage
    let canvasSize: CGSize
    var onPick: (String) -> Void
    var onCancel: () -> Void

    @State private var finger = CGPoint(x: 0.5, y: 0.5)
    @State private var previewHex = "#FFFFFF"

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            Circle()
                .strokeBorder(.white, lineWidth: 3)
                .background(Circle().fill(Color(markupHex: previewHex) ?? .white))
                .frame(width: 72, height: 72)
                .position(
                    x: finger.x * canvasSize.width,
                    y: max(40, finger.y * canvasSize.height - 56)
                )
                .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            finger = CGPoint(
                                x: min(max(value.location.x / canvasSize.width, 0), 1),
                                y: min(max(value.location.y / canvasSize.height, 0), 1)
                            )
                            if let hex = MarkupColorSampler.sample(image: image, normalizedPoint: finger) {
                                previewHex = hex
                            }
                        }
                        .onEnded { _ in
                            onPick(previewHex)
                        }
                )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
