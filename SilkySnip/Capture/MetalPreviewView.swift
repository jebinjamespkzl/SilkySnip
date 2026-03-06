import Cocoa
import Metal
import MetalKit

/// A simple MTKView wrapper that renders a provided MTLTexture full-viewport.
final class MetalPreviewView: MTKView {
    private var commandQueue: MTLCommandQueue?
    private var currentTexture: MTLTexture?

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        let dev = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: dev)
        framebufferOnly = false
        isPaused = true // we'll drive draws when texture updates
        enableSetNeedsDisplay = true
        commandQueue = dev?.makeCommandQueue()
        clearColor = MTLClearColorMake(0, 0, 0, 0)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Set/update the preview texture (thread: main)
    func setPreviewTexture(_ tex: MTLTexture?) {
        currentTexture = tex
        // trigger draw
        self.setNeedsDisplay(self.bounds)
    }

    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let cmdBuf = commandQueue?.makeCommandBuffer(),
              let rpd = currentRenderPassDescriptor else { return }

        // Simple pass: if we have a texture, blit it to drawable using a blit encoder.
        if let src = currentTexture,
           let blit = cmdBuf.makeBlitCommandEncoder() {
            // If sizes differ, we do a scaled blit via a render pass in production.
            // Here we blit the entire src into the drawable texture (may clip/scale).
            blit.copy(from: src,
                      sourceSlice: 0,
                      sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: src.width, height: src.height, depth: 1),
                      to: drawable.texture,
                      destinationSlice: 0,
                      destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        } else {
            // nothing to preview — clear transparent
        }

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}
