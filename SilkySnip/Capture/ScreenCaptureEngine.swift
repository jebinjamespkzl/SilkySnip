import Foundation
import CoreGraphics
import CoreVideo
import IOSurface
import Metal

/// ScreenCaptureEngine
/// - Uses CGDisplayStream (dispatch queue variant) to get IOSurface-backed frames
/// - Calls the `frameHandler` with the IOSurface and display size
/// - Designed to be started/stopped per-display
///
/// Notes:
/// - CGDisplayStream APIs vary slightly between macOS SDK versions (function names).
/// - If your SDK doesn't expose `CGDisplayStreamCreateWithDispatchQueue`, try using the older `CGDisplayStreamCreate`.
///
public class ScreenCaptureEngine {
    public typealias FrameHandler = (_ ioSurface: IOSurfaceRef, _ width: Int, _ height: Int) -> Void

    private let displayID: CGDirectDisplayID
    private let queue: DispatchQueue
    private var stream: CGDisplayStream?
    private var frameHandler: FrameHandler?

    public init(displayID: CGDirectDisplayID, queue: DispatchQueue = DispatchQueue(label: "com.silkysnip.capture")) {
        self.displayID = displayID
        self.queue = queue
    }

    /// Start streaming frames.
    /// width/height can be 0 to use native display resolution.
    public func start(outputWidth: Int = 0, outputHeight: Int = 0, pixelFormat: Int32 = Int32(kCVPixelFormatType_32BGRA), handler: @escaping FrameHandler) {
        stop()
        frameHandler = handler

        let options: CFDictionary? = nil

        // Using CGDisplayStreamCreateWithDispatchQueue if available:
        // Handler signature: (CGDisplayStreamFrameStatus, UInt64, IOSurfaceRef?, CGDisplayStreamUpdate?) -> Void
        stream = CGDisplayStream(
            dispatchQueueDisplay: displayID,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            pixelFormat: pixelFormat,
            properties: options,
            queue: queue
        ) { [weak self] (status, displayTime, frameSurface, updateRef) in
            guard let self = self else { return }
            if status == .stopped || status == .frameIdle {
                return
            }
            guard let surf = frameSurface else {
                // no frame this cycle
                return
            }

            // Call handler on main queue to avoid threading surprises in UI code.
            DispatchQueue.main.async {
                self.frameHandler?(surf, IOSurfaceGetWidth(surf), IOSurfaceGetHeight(surf))
            }
        }

        if let s = stream {
            let startErr = s.start()
            if startErr != .success {
                NSLog("ScreenCaptureEngine: failed to start CGDisplayStream: \(startErr)")
            }
        } else {
            NSLog("ScreenCaptureEngine: failed to create CGDisplayStream")
        }
    }

    public func stop() {
        if let s = stream {
            s.stop()
            stream = nil
        }
        frameHandler = nil
    }

    deinit {
        stop()
    }
}
