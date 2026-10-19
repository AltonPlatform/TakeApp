import CoreImage
import Metal
import MetalKit
import SwiftUI

final class MetalPreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private static let deviceRGB = CGColorSpaceCreateDeviceRGB()
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let lock = NSLock()
    private var latestImage: CIImage?
    private var consumerCount = 0

    init(device: MTLDevice, ciContext: CIContext) {
        self.device = device
        self.ciContext = ciContext
        guard let queue = device.makeCommandQueue() else {
            fatalError("Unable to create Metal command queue.")
        }
        commandQueue = queue
        super.init()
    }

    var hasConsumers: Bool {
        lock.lock()
        defer { lock.unlock() }
        return consumerCount > 0
    }

    func beginConsuming() {
        lock.lock()
        consumerCount += 1
        lock.unlock()
    }

    func endConsuming() {
        lock.lock()
        consumerCount = max(0, consumerCount - 1)
        if consumerCount == 0 {
            latestImage = nil
        }
        lock.unlock()
    }

    func submit(_ image: CIImage) {
        guard hasConsumers else { return }

        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1, extent.isInfinite == false else { return }
        // Camera CVPixelBuffers are recycled immediately. Rendering that CIImage later
        // on the MTKView thread crashes A13 (`AGXA13FamilyFunctionHandle resourceIndex`).
        // Snapshot into a CGImage while we still own the buffer, and keep CIContext
        // use on one lock so it never overlaps draw().
        let maxEdge: CGFloat = 1280
        let scale = min(1, maxEdge / max(extent.width, extent.height))
        let scaled = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image
        let scaledExtent = scaled.extent.integral
        lock.lock()
        let snapshot = ciContext.createCGImage(scaled, from: scaledExtent)
        if let snapshot {
            latestImage = CIImage(cgImage: snapshot)
        }
        lock.unlock()
    }

    func clearLatestFrame() {
        lock.lock()
        latestImage = nil
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let drawableSize = view.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        lock.lock()
        let image = latestImage
        if let image {
            let sourceExtent = image.extent
            if sourceExtent.width > 0, sourceExtent.height > 0, sourceExtent.isInfinite == false {
                let target = CGRect(origin: .zero, size: drawableSize)
                let scale = max(
                    drawableSize.width / sourceExtent.width,
                    drawableSize.height / sourceExtent.height
                )
                let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let originX = (drawableSize.width - scaled.extent.width) / 2 - scaled.extent.origin.x
                let originY = (drawableSize.height - scaled.extent.height) / 2 - scaled.extent.origin.y
                let positioned = scaled.transformed(by: CGAffineTransform(translationX: originX, y: originY))
                ciContext.render(
                    positioned,
                    to: drawable.texture,
                    commandBuffer: commandBuffer,
                    bounds: target,
                    colorSpace: Self.deviceRGB
                )
            }
        }
        lock.unlock()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalPreviewView: UIViewRepresentable {
    let renderer: MetalPreviewRenderer
    var isActive: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    final class Coordinator {
        var renderer: MetalPreviewRenderer

        init(renderer: MetalPreviewRenderer) {
            self.renderer = renderer
            renderer.beginConsuming()
        }

        func retarget(_ renderer: MetalPreviewRenderer) {
            guard renderer !== self.renderer else { return }
            self.renderer.endConsuming()
            renderer.beginConsuming()
            self.renderer = renderer
        }

        deinit {
            renderer.endConsuming()
        }
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate = renderer
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.isPaused = !isActive
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.contentMode = .scaleAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.retarget(renderer)
        uiView.delegate = renderer
        uiView.preferredFramesPerSecond = 30
        uiView.isPaused = !isActive
        // Do not clearLatestFrame here — clearing on every isActive flip caused a black flash
        // that looked like the camera freezing when the gallery opened.
    }
}
