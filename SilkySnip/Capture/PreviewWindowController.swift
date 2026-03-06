import Cocoa
import Metal

/// Floating preview window that shows a live texture using MetalPreviewView
final class PreviewWindowController: NSWindowController {
    private var previewView: MetalPreviewView!
    private let device: MTLDevice

    init(device: MTLDevice, initialSize: NSSize = NSSize(width: 320, height: 200)) {
        self.device = device
        let style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView, .utilityWindow]
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                           styleMask: style,
                           backing: .buffered,
                           defer: false)
        win.level = .floating
        win.collectionBehavior = [.transient, .ignoresCycle]
        win.isOpaque = false
        win.backgroundColor = .clear
        super.init(window: win)

        previewView = MetalPreviewView(frame: win.contentView!.bounds, device: device)
        previewView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(previewView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func setPreviewTexture(_ tex: MTLTexture?) {
        previewView.setPreviewTexture(tex)
    }

    func show(at point: NSPoint) {
        if let win = window {
            win.setFrameTopLeftPoint(point)
            win.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }
}
