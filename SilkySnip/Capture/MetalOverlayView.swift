import Cocoa
import Metal
import MetalKit
import IOSurface

class MetalOverlayView: MTKView {

    private var commandQueue: MTLCommandQueue?
    private var selectionRect: CGRect = .zero
    // optional texture coming from IOSurface (zero-copy)
    internal var surfaceTexture: MTLTexture?

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        let dev = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: dev)

        framebufferOnly = false
        isPaused = false
        enableSetNeedsDisplay = false

        commandQueue = dev?.makeCommandQueue()

        clearColor = MTLClearColorMake(0, 0, 0, 0)
        
        // Ensure the view and its layer are transparent
        self.wantsLayer = true
        if let layer = self.layer {
            layer.isOpaque = false
            layer.backgroundColor = NSColor.clear.cgColor
        }
    }

    override var isOpaque: Bool {
        return false
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    func updateSelection(rect: CGRect) {
        selectionRect = rect
    }

    /// Provide an MTLTexture backed by an IOSurface for fast blit / crop
    func setSurfaceTexture(_ tex: MTLTexture?) {
        surfaceTexture = tex
    }

    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        // Render selection rectangle overlay (basic)
        // Note: Proper textured preview rendering would use a full render pipeline. For quick result,
        // we leave a transparent pass and rely on PreviewWindowController to show the cropped texture.
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
