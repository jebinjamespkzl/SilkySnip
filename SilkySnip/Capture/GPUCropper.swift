import Foundation
import Metal
import CoreImage
import AppKit

/// GPUCropper
/// - Provides GPU-based crop of a source MTLTexture (full-screen / IOSurface-backed)
/// - Returns either an MTLTexture (fast, stays on GPU) or an NSImage (via CIContext) for CPU-side use
public class GPUCropper {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext

    public init(device: MTLDevice) {
        self.device = device
        guard let cq = device.makeCommandQueue() else {
            fatalError("GPUCropper: failed to create command queue")
        }
        self.commandQueue = cq
        // CIContext backed by Metal for zero-copy conversions
        self.ciContext = CIContext(mtlDevice: device)
    }

    /// Crop sourceTexture to pixel rect (x,y,width,height) where coordinates are in texture pixel space (origin = lower-left).
    /// Returns a new MTLTexture containing the cropped region. Caller owns a reference.
    public func cropToTexture(sourceTexture: MTLTexture, pixelRect: MTLRegion) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat,
                                                            width: pixelRect.size.width,
                                                            height: pixelRect.size.height,
                                                            mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let target = device.makeTexture(descriptor: desc) else { return nil }

        guard let cmd = commandQueue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else {
            return nil
        }

        // Copy region from source to target (fast GPU blit)
        blit.copy(from: sourceTexture,
                  sourceSlice: 0,
                  sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: pixelRect.origin.x, y: pixelRect.origin.y, z: 0),
                  sourceSize: MTLSize(width: pixelRect.size.width, height: pixelRect.size.height, depth: 1),
                  to: target,
                  destinationSlice: 0,
                  destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))

        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        return target
    }

    /// Crop and return an NSImage (via CoreImage). This uses CIContext(createCGImage:) which will copy GPU -> CPU.
    /// Use this for exporting or clipboard operations.
    public func cropToNSImage(sourceTexture: MTLTexture, pixelRect: MTLRegion) -> NSImage? {
        guard let croppedTex = cropToTexture(sourceTexture: sourceTexture, pixelRect: pixelRect) else { return nil }

        // Create CIImage from MTLTexture
        guard let ciImage = CIImage(mtlTexture: croppedTex, options: [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            return nil
        }

        // Render CIImage to CGImage
        guard let cgImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: croppedTex.width, height: croppedTex.height)) else {
            return nil
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return nsImage
    }
}
