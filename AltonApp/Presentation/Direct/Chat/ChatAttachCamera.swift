import AVFoundation
import SwiftUI
import UIKit

struct ChatCapturedPhoto: Identifiable, Equatable {
    let id: String
    let fileURL: URL
    let preview: UIImage

    static func == (lhs: ChatCapturedPhoto, rhs: ChatCapturedPhoto) -> Bool {
        lhs.id == rhs.id && lhs.fileURL == rhs.fileURL
    }

    func loadFullImage() throws -> UIImage {
        try PhotoFinisher.loadFullImage(at: fileURL)
    }
}

enum ChatCaptureID {
    static let prefix = "capture:"

    static func make() -> String {
        prefix + UUID().uuidString
    }

    static func isCapture(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }
}

struct AttachCameraCell: View {
    var showsPreview: Bool
    var session: AVCaptureSession?
    var onTap: () -> Void
    var onVisibilityChange: (Bool) -> Void = { _ in }
    var onDetachPreview: (AVCaptureVideoPreviewLayer) -> Void = { _ in }

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // Static fill under the live layer so the tile fades in instead of popping.
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), Color.black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    if showsPreview, let session {
                        // Preview layer, not Metal. A tiny MTKView in the grid crashes
                        // on A13 (`AGXA13FamilyFunctionHandle resourceIndex`).
                        ChatSessionPreview(session: session, onDetach: onDetachPreview)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    Image(systemName: "camera.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                }
                .clipped()
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.22), value: showsPreview)
        }
        .buttonStyle(.plain)
        .onScrollVisibilityChange(threshold: 0.15) { visible in
            onVisibilityChange(visible)
        }
    }
}

/// Live preview on an `AVCaptureSession` without Metal/CI (safe on A13).
struct ChatSessionPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onDetach: (AVCaptureVideoPreviewLayer) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetach: onDetach)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        let layer = uiView.previewLayer
        guard layer.session != nil else { return }
        // Keep the layer alive until the session queue has finished start/stop.
        // Nilling `session` on the main thread before that returns blocks the chat.
        coordinator.onDetach(layer)
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onDetach = onDetach
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class Coordinator {
        var onDetach: (AVCaptureVideoPreviewLayer) -> Void

        init(onDetach: @escaping (AVCaptureVideoPreviewLayer) -> Void) {
            self.onDetach = onDetach
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

struct AttachCapturedCell: View {
    let photo: ChatCapturedPhoto
    let number: Int?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(uiImage: photo.preview)
                        .resizable()
                        .scaledToFill()
                }
                .overlay(alignment: .topTrailing) {
                    AttachSelectionBadge(number: number)
                        .padding(6)
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AttachSelectionBadge: View {
    let number: Int?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .background {
                    Circle().fill(number == nil ? Color.black.opacity(0.25) : Color.primary)
                }
            if let number {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
            }
        }
        .frame(width: 22, height: 22)
    }
}
