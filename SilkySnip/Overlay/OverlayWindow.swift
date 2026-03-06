//
//  OverlayWindow.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import CoreImage
import QuartzCore

protocol OverlayWindowDelegate: AnyObject {
    func overlayWindowDidRequestClose(_ overlay: OverlayWindow)
    func overlayWindowDidRequestNewCapture(_ overlay: OverlayWindow)
    func overlayWindowDidMove(_ overlay: OverlayWindow, delta: CGPoint)
    func overlayWindowDidStartDrag(_ overlay: OverlayWindow)
}

// MARK: - OverlayWindow

class OverlayWindow: NSPanel, NSTextDelegate {
    
    // MARK: - Properties
    
    weak var overlayDelegate: OverlayWindowDelegate?
    
    private(set) var capturedImage: CGImage {
        didSet {
            if overlayView != nil {
                updateDisplayImage()
            }
        }
    }
    private(set) var metadata: CaptureMetadata
    
    var overlayView: OverlayContentView!
    private var annotationLayer: AnnotationLayer!
    var toolManager: ToolManager { ToolManager.shared }  // Uses shared instance for color/size sync
    
    // Event Monitor
    private var localMonitor: Any?
    
    private(set) var sourceDisplayID: CGDirectDisplayID = CGMainDisplayID()
    
    // Display lock feature
    var lockToDisplay: Bool = false {
        didSet {
            // CRITICAL FIX: Aggressively enforce Space tracking rules via collectionBehavior
            // This guarantees that windows properly flow across full screen apps or are pinned 
            // exclusively to a single physical screen.
            if lockToDisplay {
                self.collectionBehavior = [.fullScreenAuxiliary]
                showDisplayLockedIndicator()
            } else {
                self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
                hideDisplayLockedIndicator()
            }
        }
    }
    
    // Drag state
    private var initialMouseLocation: CGPoint? // Screen coordinates
    var initialWindowOrigin: CGPoint?
    
    // Crop selection visual
    private var cropSelectionLayer: CAShapeLayer?
    
    // Crop handles (edge buttons)
    private var cropHandles: [CropHandle] = []
    private var preExpandedFrame: CGRect?  // Store frame before crop expansion
    
    // Original image for reverse crop
    private var originalImage: CGImage?
    // Track crop amounts for each edge (to allow undo)
    private var cropTop: CGFloat = 0
    private var cropBottom: CGFloat = 0
    private var cropLeft: CGFloat = 0
    private var cropRight: CGFloat = 0
    
    // Original annotations for remapping
    private var originalAnnotations: [Stroke]?
    
    // Stacking support
    var originalFrame: CGRect?
    var stackOffset: CGPoint?
    
    // Text Entry
    private var activeTextField: NSTextField?
    
    // MARK: - Crop State Anchor
    
    private struct CropAnchorState {
        let initialFrame: CGRect
        let startMouseLocation: CGPoint
        let initialCropTop: CGFloat
        let initialCropBottom: CGFloat
        let initialCropLeft: CGFloat
        let initialCropRight: CGFloat
        let initialScale: CGFloat
    }
    
    private var cropAnchor: CropAnchorState?
    
    // MARK: - Advanced Features (Restored)
    
    // Properties for Color Picker HUD (internal for OverlayWindow+Loupe.swift extension)
    var colorPickerHUD: NSTextField?
    var colorPickerHUDWindow: NSPanel?  // Phase 30: Floating HUD panel
    var colorPickerTimer: Timer?
    var lastColorSampleTime: Date = .distantPast
    var colorPickerBitmapRep: NSBitmapImageRep? // H5: Cached to avoid per-tick allocation
    var activeToastWindow: NSWindow? // Strong reference to prevent deallocation
    var colorPickerClickMonitor: Any?  // Phase 31: Global click monitor for color picker
    var colorPickerLocalMonitor: Any?  // Phase 31: Local click monitor for color picker
    var loupeRightClickMonitor: Any?   // Phase 34: Global right-click to deactivate magnifier
    var isGhostMode: Bool = false {
        didSet {
            self.ignoresMouseEvents = isGhostMode
            self.alphaValue = isGhostMode ? 0.3 : 1.0
            
            if isGhostMode {
                // Disable all active tools and modes for full mouse transparency
                if isColorPickerMode { toggleColorPicker(nil) }
                if isLoupeActive { toggleLoupe(nil) }
                if isRulerActive { toggleRuler(nil) }
                currentTool = nil
                NSCursor.arrow.set()
            }
            
            // Notify menu to update
            NotificationCenter.default.post(name: Notification.Name("GhostModeToggled"), object: nil)
        }
    }
    
    // MARK: - Global Ghost Mode
    
    static var isGlobalGhostMode: Bool = false
    
    static func setGlobalGhostMode(_ enabled: Bool) {
        isGlobalGhostMode = enabled
        
        let overlays = NSApp.windows.compactMap { $0 as? OverlayWindow }
        for overlay in overlays {
            overlay.isGhostMode = enabled
        }
    }
    
    var hasAnnotations: Bool {
        return !annotationLayer.getAllStrokes().isEmpty
    }
    
    func updateMetadataAnnotations() {
        // Sync annotations from layer to metadata
        self.metadata.annotations = annotationLayer.getAllStrokes()
        DebugLogger.shared.log("Metadata Annotations Updated: \(metadata.annotations.count) strokes")
    }
    
    var rulerOverlay: RulerOverlay?
    var loupeWindow: LoupeWindow?
    
    var isRulerActive: Bool { return rulerOverlay?.superview != nil }
    var isLoupeActive: Bool { return loupeWindow?.isVisible == true }
    var magnificationLevel: CGFloat = 3.0
    var loupeTimer: Timer?
    var isGrayscale: Bool = false
    var isColorPickerMode: Bool = false
    
    // MARK: - Initialization
    
    init(image: CGImage, metadata: CaptureMetadata) {
        self.capturedImage = image
        self.metadata = metadata
        
        // Calculate window size based on image and zoom
        let imageSize = CGSize(width: image.width, height: image.height)
        
        // Find the screen containing the capture rect center
        let captureCenter = CGPoint(x: metadata.captureRect.midX, y: metadata.captureRect.midY)
        var targetScreen: NSScreen? = nil
        for screen in NSScreen.screens {
            if screen.frame.contains(captureCenter) {
                targetScreen = screen
                break
            }
        }
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first
        let scaleFactor = screen?.backingScaleFactor ?? 1.0
        
        // Override the default metadata scale factor with the real physical screen scale factor
        self.metadata.scaleFactor = scaleFactor
        
        // Store the source display ID
        if let targetScreen = targetScreen,
           let screenID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            self.sourceDisplayID = screenID
        } else {
            self.sourceDisplayID = metadata.displayID
        }
        
        let scaledSize = CGSize(
            width: imageSize.width * metadata.zoom / scaleFactor,
            height: imageSize.height * metadata.zoom / scaleFactor
        )
        
        // Position window near the capture location on the SAME screen
        let screenFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        
        // Try to position at capture location, but ensure it fits within screen bounds
        var windowOriginX = metadata.captureRect.origin.x
        var windowOriginY = metadata.captureRect.origin.y
        
        // Clamp to screen bounds
        windowOriginX = max(screenFrame.minX, min(windowOriginX, screenFrame.maxX - scaledSize.width))
        windowOriginY = max(screenFrame.minY, min(windowOriginY, screenFrame.maxY - scaledSize.height))
        
        let windowOrigin = CGPoint(x: windowOriginX, y: windowOriginY)
        let contentRect = CGRect(origin: windowOrigin, size: scaledSize)
        
        // CRITICAL DECODE: Changing from NSWindow to NSPanel with .nonactivatingPanel 
        // to bypass macOS LSUIElement full-screen space routing restrictions.
        // We add .hudWindow to enforce overlay semantics.
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        DebugLogger.shared.log("OverlayWindow init started")
        
        setupWindow()
        setupContentView()
        setupAnnotationLayer()
        
        // Restore annotations if any
        // Restore annotations if any
        restoreAnnotations()
        DebugLogger.shared.log("OverlayWindow init completed. Image Size: \(image.width)x\(image.height). Window Frame: \(self.frame)")
    }
    
    deinit {
        // C6: Invalidate timers to break retain cycles
        colorPickerTimer?.invalidate()
        colorPickerTimer = nil
        loupeTimer?.invalidate()
        loupeTimer = nil
        // Clean up loupe window
        loupeWindow?.orderOut(nil)
        loupeWindow = nil
        // Clean up cached bitmap
        colorPickerBitmapRep = nil
        DebugLogger.shared.log("OverlayWindow deinit")
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        DebugLogger.shared.log("Configuring Overlay Window")
        // Allow window to move freely between screens
        self.isMovableByWindowBackground = false // We handle dragging manually
        self.isMovable = true // Allow standard window movement
        self.acceptsMouseMovedEvents = true
        
        // Apply Global Ghost Mode if active
        if OverlayWindow.isGlobalGhostMode {
             self.isGhostMode = true
        }
        
        // Ensure NSPanel becomes key when text is being edited
        self.becomesKeyOnlyIfNeeded = true
        
        // Ensure critical behaviors
        self.level = .floating
        // By default, show on ALL spaces including fullscreen apps
        // User can enable "Lock to Display" to restrict movement
        self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        let defaultOpacity = UserDefaults.standard.object(forKey: "DefaultOpacity") as? Double ?? 1.0
        self.alphaValue = CGFloat(defaultOpacity)
        hasShadow = true
        isMovableByWindowBackground = false  // We handle drag ourselves
        
        // Enable layer backing for GPU acceleration
        contentView?.wantsLayer = true
        
        // Force shadow invalidation effectively
        self.hasShadow = true
        self.invalidateShadow()
        
        // Add Local Monitor for Hotkeys (Robust interception)
        // This ensures hotkeys work even if focus is weird, as long as app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains([.control, .option]) {
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    var handled = false
                    switch chars {
                    case "p":
                        self.currentTool = .pen
                        DebugLogger.shared.log("Global Monitor: Switched to Pen")
                        handled = true
                    case "h":
                        self.currentTool = .highlighter
                        DebugLogger.shared.log("Global Monitor: Switched to Highlighter")
                        handled = true
                    case "e":
                        self.currentTool = .eraser
                        DebugLogger.shared.log("Global Monitor: Switched to Eraser")
                        handled = true
                    case "m":
                        self.currentTool = nil
                        DebugLogger.shared.log("Global Monitor: Switched to Move")
                        handled = true
                    case "t":
                        self.currentTool = .text
                        DebugLogger.shared.log("Global Monitor: Switched to Text")
                        handled = true
                    default:
                        break
                    }
                    
                    if handled {
                        return nil // Consume event
                    }
                }
            }
            return event
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSmartRestoreVisibility(_:)), name: .smartRestoreCheckVisibility, object: nil)
    }
    
    @objc private func handleSmartRestoreVisibility(_ notification: Notification) {
        // If Smart Restore is disabled or this overlay is NOT pinned to anything, ignore.
        // It stays visible based on user's manual actions.
        guard SmartRestoreManager.shared.isEnabled,
              SmartRestoreManager.shared.isPinned(metadata.id) else {
            // Note: If an overlay is unpinned while hidden, it won't automatically reappear here.
            // The unpin action in ContextMenu should probably orderFront if needed, but for now this is safe.
            return
        }
        
        guard let activeBundleID = notification.userInfo?["activeBundleID"] as? String else { return }
        let pinnedApps = SmartRestoreManager.shared.getPinnedApps(for: metadata.id)
        
        if pinnedApps.contains(activeBundleID) {
            // The app we are pinned to is now active -> SHOW
            if !self.isVisible {
                self.orderFront(nil)
            }
        } else {
            // A different app is active -> HIDE
            if self.isVisible {
                self.orderOut(nil)
            }
        }
    }
    
    @objc func windowWillClose(_ notification: Notification) {
        // C7: Break retain cycles caused by Timer(target: self)
        colorPickerTimer?.invalidate()
        colorPickerTimer = nil
        loupeTimer?.invalidate()
        loupeTimer = nil
        
        if isLoupeActive {
            toggleLoupe(nil)
        }
    }
    
    private func updateDisplayImage() {
        let creationScale = metadata.scaleFactor 
        let imageSize = NSSize(width: CGFloat(capturedImage.width) / creationScale, height: CGFloat(capturedImage.height) / creationScale)
        
        var displayCGImage = capturedImage
        
        if isGrayscale {
            let ciImage = CIImage(cgImage: capturedImage)
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(0.0, forKey: kCIInputSaturationKey)
                if let output = filter.outputImage {
                    let context = CIContext(options: nil)
                    if let cgOutput = context.createCGImage(output, from: output.extent) {
                        displayCGImage = cgOutput
                    }
                }
            }
        }
        
        // Fix for blurriness: Create retina-aware NSImage directly from CGImage with explicit logical size
        let nsImage = NSImage(cgImage: displayCGImage, size: imageSize)
        
        if overlayView == nil {
            overlayView = OverlayContentView(frame: CGRect(origin: .zero, size: frame.size))
            overlayView.imageScaling = .scaleProportionallyUpOrDown
            overlayView.wantsLayer = true
            overlayView.layerUsesCoreImageFilters = true
        }
        
        overlayView.image = nsImage
    }
    
    private func setupContentView() {
        updateDisplayImage()
        
        // IMPORTANT: Disable color matching for accurate color display
        // This prevents AppKit from applying ICC profile conversions
        overlayView.layer?.contentsFormat = .RGBA8Uint
        
        overlayView.layer?.cornerRadius = 8
        
        if UserDefaults.standard.bool(forKey: "NeonBorderEnabled") {
            overlayView.layer?.masksToBounds = true
            
            // Theme-aware neon color: Cyberpunk=cyan, Matrix=green, Solar=orange
            let themeIndex = UserDefaults.standard.integer(forKey: "SelectedTheme")
            let neonColor: NSColor
            switch themeIndex {
            case 1: neonColor = NSColor.systemGreen   // Matrix
            case 2: neonColor = NSColor.systemOrange   // Solar
            default: neonColor = NSColor.cyan           // Cyberpunk (default)
            }
            
            // Inner neon border instead of an outer shadow, so it shows on all 4 sides without clipping
            overlayView.layer?.borderWidth = 4
            overlayView.layer?.borderColor = neonColor.cgColor
            
            // Remove any old shadow configuration
            overlayView.layer?.shadowColor = nil
            overlayView.layer?.shadowOpacity = 0
            overlayView.layer?.shadowRadius = 0
        } else {
            overlayView.layer?.masksToBounds = true
            // FORCE Borderless to prevent "ant like border" on final screenshot
            overlayView.layer?.borderWidth = 0 
            overlayView.layer?.borderColor = nil
        }
        // REMOVED border per user request - "no ant like border... borderless"
        // overlayView.layer?.borderWidth = 1
        // overlayView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        
        // CRITICAL: Force clipping of sublayers (annotations) that extend beyond the cropped view
        overlayView.clipsToBounds = true
        overlayView.autoresizingMask = [.width, .height]
        
        overlayView.delegate = self
        
        overlayView.delegate = self
        
        contentView = overlayView
        
        // Invalidate shadow after content is set to ensure it matches the shape
        self.invalidateShadow()
        
        // Suspect crash in AnnotationLayer - disabling for debug
        setupAnnotationLayer()
    }
    
    private func setupAnnotationLayer() {
        annotationLayer = AnnotationLayer()
        annotationLayer.frame = overlayView.bounds
        annotationLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        annotationLayer.zPosition = 1000  // Ensure above image layer
        annotationLayer.isHidden = false
        annotationLayer.opacity = 1.0
        
        annotationLayer.currentZoom = metadata.zoom // Sync initial zoom
        
        overlayView.layer?.addSublayer(annotationLayer)
        DebugLogger.shared.log("AnnotationLayer added with frame: \(annotationLayer.frame)")
    }
    
    private func restoreAnnotations() {
        DebugLogger.shared.log("Restoring \(metadata.annotations.count) annotations for screenshot \(metadata.id)")
        for stroke in metadata.annotations {
            annotationLayer.addStroke(stroke)
        }
    }
    
    // MARK: - Window Behavior
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    // MARK: - Actions
    
    func setZoom(_ zoom: CGFloat) {
        guard Constants.zoomLevels.contains(zoom) else { return }
        
        let imageSize = CGSize(
            width: CGFloat(capturedImage.width),
            height: CGFloat(capturedImage.height)
        )
        
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        let newSize = CGSize(
            width: imageSize.width * zoom / scaleFactor,
            height: imageSize.height * zoom / scaleFactor
        )
        
        // Calculate new origin to zoom from center
        let currentCenter = CGPoint(
            x: frame.midX,
            y: frame.midY
        )
        
        let newOrigin = CGPoint(
            x: currentCenter.x - newSize.width / 2,
            y: currentCenter.y - newSize.height / 2
        )
        
        setFrame(CGRect(origin: newOrigin, size: newSize), display: true, animate: false)
        
        // Update annotation layer with instant GPU-accelerated scaling
        let oldBounds = annotationLayer.bounds
        annotationLayer.frame = overlayView.bounds
        
        // Use transform scaling for instant real-time sync (no lag)
        annotationLayer.scaleToFit(oldBounds: oldBounds, newBounds: overlayView.bounds)
        
        // Update metadata
        metadata.zoom = zoom
        
        // Rebuild paths after a short delay for crisp rendering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.annotationLayer.currentZoom = zoom // Update zoom level for line widths
            self.annotationLayer.rebuildStrokesForCurrentBounds()
        }
        
        // Sync crop handles if active
        if isCropMode {
            updateCropHandlePositions()
        }
        
        // Update lock icon position
        updateLockIndicatorPosition()
        updateDisplayLockIndicatorPosition()
    }
    
    func toggleZoom() {
        let currentIndex = Constants.zoomLevels.firstIndex(of: metadata.zoom) ?? 0
        let nextIndex = (currentIndex + 1) % Constants.zoomLevels.count
        setZoom(Constants.zoomLevels[nextIndex])
    }
    
    // MARK: - Export
    
    /// Renders the captured image with annotations flattened onto it
    func renderFlattenedImage() -> CGImage {
        var baseImage = capturedImage
        
        if isGrayscale {
            let ciImage = CIImage(cgImage: baseImage)
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(0.0, forKey: kCIInputSaturationKey)
                if let output = filter.outputImage {
                    let context = CIContext(options: nil)
                    if let cgOutput = context.createCGImage(output, from: output.extent) {
                        baseImage = cgOutput
                    }
                }
            }
        }
        
        // If no annotations, return base
        guard !metadata.annotations.isEmpty else {
            return baseImage
        }
        
        let width = capturedImage.width
        let height = capturedImage.height
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return capturedImage
        }
        
        // Draw base image
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw annotations on top
        if let annotationsImage = annotationLayer.renderToImage() {
            context.draw(annotationsImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        return context.makeImage() ?? baseImage
    }
    
    // MARK: - Tool Management
    
    var currentTool: ToolType? {
        get { toolManager.currentTool }
        set {
            // Strict Exclusivity: ALWAYS disable Color Picker when tool changes
            // This ensures switching to Move Mode (nil) or any Tool (Pen, etc.) turns it off.
            if isColorPickerMode {
                toggleColorPicker(nil)
            }

            if newValue != nil {
                endCropMode()
                // Disable Magnifier when entering a drawing tool (optional, but keeps UI clean)
                if isLoupeActive { toggleLoupe(nil) }
            }
            
            toolManager.currentTool = newValue
            // Update cursor
            overlayView?.window?.invalidateCursorRects(for: overlayView)
        }
    }
    
    func addStroke(_ stroke: Stroke) {
        annotationLayer.addStroke(stroke)
        metadata.annotations.append(stroke)
    }
    
    func eraseStroke(at point: CGPoint) {
        if let removedStroke = annotationLayer.removeStroke(at: point) {
            metadata.annotations.removeAll { $0.id == removedStroke.id }
        }
    }
    
    // MARK: - Crop Mode
    
    var isCropMode = false
    var isLocked: Bool = false {
        didSet {
            // Visual feedback when locked/unlocked
            if isLocked {
                showLockedIndicator()
            } else {
                hideLockedIndicator()
            }
        }
    }
    
    func toggleLock() {
        isLocked.toggle()
    }
    private var cropSelectionView: NSView?
    private var cropStartPoint: CGPoint?
    private var cropClickMonitor: Any?
    
    // Text Dragging
    private var draggedAnnotation: Stroke?
    private var dragStartLocation: CGPoint? // Text location at start
    private var dragStartMouse: CGPoint?    // Mouse location at start
    
    // Cached highlight color for performance
    private var _cachedHighlightColor: NSColor?
    
    func startCropMode() {
        isCropMode = true
        toolManager.currentTool = nil  // Disable annotation tools
        
        // Show crop handles on all edges
        showCropHandles()
        
        // Add global click monitor to detect clicks outside this window
        cropClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            // Click was outside our window - end crop mode
            self?.endCropMode()
        }
        
        DebugLogger.shared.log("Crop mode started - use edge handles to crop")
    }
    
    func endCropMode() {
        isCropMode = false
        hideCropHandles()
        NSCursor.arrow.set()
        
        // Remove the global monitor
        if let monitor = cropClickMonitor {
            NSEvent.removeMonitor(monitor)
            cropClickMonitor = nil
        }
        
        // NON-DESTRUCTIVE: We do NOT remap or filter here.
        // We keep 'originalImage' and 'originalAnnotations' alive.
        // We leave 'annotationLayer' shifted (Viewport logic).
        // This allows the user to re-enter crop mode and expand back to the original size.
        // The final filtering will happen only during Export/Copy.
        
        DebugLogger.shared.log("Crop mode ended (Non-Destructive)")
    }
    
    func applyCrop(to rect: CGRect) {
        guard rect.width > 10 && rect.height > 10 else { return }
        
        // Convert rect to image coordinates
        let scale = CGFloat(capturedImage.width) / overlayView.bounds.width
        let imageRect = CGRect(
            x: rect.origin.x * scale,
            y: CGFloat(capturedImage.height) - (rect.origin.y + rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        // Crop the image
        // Crop the image
        if let croppedImage = capturedImage.cropping(to: imageRect) {
            // Capture old size before updating
            let oldSize = CGSize(width: capturedImage.width, height: capturedImage.height)
            
            // Create new metadata with cropped image
            capturedImage = croppedImage
            
            // Update window size to match cropped image
            let newWidth = min(CGFloat(croppedImage.width) / 2, NSScreen.main?.frame.width ?? 800 * 0.8)
            let newHeight = newWidth * CGFloat(croppedImage.height) / CGFloat(croppedImage.width)
            
            setContentSize(NSSize(width: newWidth, height: newHeight))
            
            // Update image view
            updateDisplayImage()
            overlayView.frame = CGRect(origin: .zero, size: NSSize(width: newWidth, height: newHeight))
            
            // Update annotation layer frame
            annotationLayer.frame = overlayView.bounds
            
            // Remap annotations
            // Calculate scale from capturedImage (which was the source for crop)
            // Wait, applyCrop is used for rectangular selection crop, which is destructive and usually starts from CURRENT capturedImage.
            // So we treat 'capturedImage' (before reassignment) as the "Original".
            // Bake the crop into annotations (Coordinate Remapping)
            if let originalStrokes = originalAnnotations {
                 var remappedStrokes: [Stroke] = []
                 
                 // Reuse simplified logic: New = Old - CropOffset
                 for stroke in originalStrokes {
                     var newPoints: [CGPoint] = []
                     for pNorm in stroke.points {
                         let pX = pNorm.x * oldSize.width
                         let pY = pNorm.y * oldSize.height
                         
                         let newPX = pX - cropLeft
                         let newPY = pY - cropBottom
                         
                         let newPNormX = newPX / overlayView.bounds.width
                         let newPNormY = newPY / overlayView.bounds.height
                         
                         // Crop bounds check
                         if newPNormX >= -0.05 && newPNormX <= 1.05 && newPNormY >= -0.05 && newPNormY <= 1.05 {
                              newPoints.append(CGPoint(x: newPNormX, y: newPNormY))
                         }
                     }
                     if !newPoints.isEmpty {
                         var newStroke = stroke
                         newStroke.points = newPoints
                         remappedStrokes.append(newStroke)
                     }
                 }
                 metadata.annotations = remappedStrokes
            }
            
            // Reset AnnotationLayer to normal coordinate system (0,0 relative to new view)
            annotationLayer.frame = overlayView.bounds // (0, 0, newW, newH)
            annotationLayer.clearAll()
            restoreAnnotations() // Redraw with new baked coordinates

            // CRITICAL FIX: Reset "Original" state to this new cropped version
            // This ensures subsequent edge dragging starts fresh from this new image
            originalImage = croppedImage
            
            updateLockIndicatorPosition()
            updateDisplayLockIndicatorPosition()
            originalAnnotations = metadata.annotations
            
            // Reset crop offsets since we burned the crop into the image
            cropTop = 0
            cropBottom = 0
            cropLeft = 0
            cropRight = 0
        }
        
        isCropMode = false
        NSCursor.arrow.set()
    }
    
    // MARK: - Crop Selection Visual
    
    private func setupCropSelectionLayer() {
        cropSelectionLayer?.removeFromSuperlayer()
        
        let layer = CAShapeLayer()
        layer.fillColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
        layer.strokeColor = NSColor.systemBlue.cgColor
        layer.lineWidth = 2
        layer.lineDashPattern = [5, 3]
        layer.zPosition = 2000
        
        overlayView.layer?.addSublayer(layer)
        cropSelectionLayer = layer
    }
    
    private func updateCropSelectionLayer(from startPoint: CGPoint, to currentPoint: CGPoint) {
        guard let layer = cropSelectionLayer else { return }
        
        let rect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        
        layer.path = CGPath(rect: rect, transform: nil)
    }
    
    private func removeCropSelectionLayer() {
        cropSelectionLayer?.removeFromSuperlayer()
        cropSelectionLayer = nil
    }
    
    // MARK: - Display Constraint
    
    private func constrainToSourceDisplay(_ origin: CGPoint) -> CGPoint {
        // Find the source screen
        for screen in NSScreen.screens {
            if let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenID == sourceDisplayID {
                let screenFrame = screen.visibleFrame
                let windowSize = frame.size
                
                var newX = origin.x
                var newY = origin.y
                
                // Clamp to screen bounds
                newX = max(screenFrame.minX, min(newX, screenFrame.maxX - windowSize.width))
                newY = max(screenFrame.minY, min(newY, screenFrame.maxY - windowSize.height))
                
                return CGPoint(x: newX, y: newY)
            }
        }
        return origin
    }
    
    // MARK: - Crop Handles
    
    func setupCropHandles() {
        removeCropHandles()
        
        let edges: [CropEdge] = [.top, .bottom, .left, .right]
        
        // Add handles directly to overlayView - they will be at the edges
        for edge in edges {
            let handle = CropHandle(edge: edge, overlayWindow: self)
            handle.wantsLayer = true
            handle.layer?.zPosition = 2000 // Ensure handles are on top
            overlayView.addSubview(handle)
            cropHandles.append(handle)
        }
        
        updateCropHandlePositions()
        // Note: handles are hidden by default since setupCropHandles is only called from showCropHandles now
    }
    
    func updateCropHandlePositions() {
        // Position handles on the edges of the overlayView (inside bounds)
        let bounds = overlayView.bounds
        let handleThickness: CGFloat = 8
        let handleLength: CGFloat = 40
        
        for handle in cropHandles {
            switch handle.edge {
            case .top:
                handle.frame = CGRect(
                    x: (bounds.width - handleLength) / 2,
                    y: bounds.height - handleThickness - 2,
                    width: handleLength,
                    height: handleThickness
                )
            case .bottom:
                handle.frame = CGRect(
                    x: (bounds.width - handleLength) / 2,
                    y: 2,
                    width: handleLength,
                    height: handleThickness
                )
            case .left:
                handle.frame = CGRect(
                    x: 2,
                    y: (bounds.height - handleLength) / 2,
                    width: handleThickness,
                    height: handleLength
                )
            case .right:
                handle.frame = CGRect(
                    x: bounds.width - handleThickness - 2,
                    y: (bounds.height - handleLength) / 2,
                    width: handleThickness,
                    height: handleLength
                )
            }
            // NOTE: Removed scale transform - handles stay a fixed UI size
            // but reposition correctly with layout changes
        }
    }
    
    func removeCropHandles() {
        for handle in cropHandles {
            handle.removeFromSuperview()
        }
        cropHandles.removeAll()
    }
    
    func performCropFromHandles() {
        // No longer needed - cropping happens in realtime
        annotationLayer.frame = overlayView.bounds
        annotationLayer.setNeedsDisplay()
        updateCropHandlePositions()
    }
    
    // MARK: - Anchor-Based Crop Logic (Stable)
    
    func startCrop(edge: CropEdge) {
        // Commit any active text
        if activeTextField != nil {
            commitTextEntry()
        }
        
        // Ensure original image is set
        if originalImage == nil {
            originalImage = capturedImage
            originalAnnotations = metadata.annotations
        }
        
        let scale = CGFloat(capturedImage.width) / overlayView.bounds.width
        
        cropAnchor = CropAnchorState(
            initialFrame: self.frame,
            startMouseLocation: NSEvent.mouseLocation,
            initialCropTop: cropTop,
            initialCropBottom: cropBottom,
            initialCropLeft: cropLeft,
            initialCropRight: cropRight,
            initialScale: scale
        )
        
        DebugLogger.shared.log("Started Crop: \(edge) | Frame: \(self.frame)")
    }
    
    func updateCrop(edge: CropEdge) {
        guard let anchor = cropAnchor, let original = originalImage else { return }
        
        let currentLocation = NSEvent.mouseLocation
        let totalDeltaX = currentLocation.x - anchor.startMouseLocation.x
        let totalDeltaY = currentLocation.y - anchor.startMouseLocation.y
        
        let originalWidth = CGFloat(original.width)
        let originalHeight = CGFloat(original.height)
        
        // Calculate pixel change based on INITIAL scale (stable)
        var pixelDeltaX = totalDeltaX * anchor.initialScale
        var pixelDeltaY = totalDeltaY * anchor.initialScale
        
        // Calculate TARGET crop values based on initial + delta
        var targetCropTop = anchor.initialCropTop
        var targetCropBottom = anchor.initialCropBottom
        var targetCropLeft = anchor.initialCropLeft
        var targetCropRight = anchor.initialCropRight
        
        switch edge {
        case .top:
            // Mouse Drag Down (neg Y) -> Crop Increases
            let pDelta = -pixelDeltaY
            targetCropTop = max(0, anchor.initialCropTop + pDelta)
            
        case .bottom:
            // Mouse Drag Up (pos Y) -> Crop Increases
            let pDelta = pixelDeltaY
            targetCropBottom = max(0, anchor.initialCropBottom + pDelta)
            
        case .left:
            // Mouse Drag Right (pos X) -> Crop Increases
            let pDelta = pixelDeltaX
            targetCropLeft = max(0, anchor.initialCropLeft + pDelta)
            
        case .right:
            // Mouse Drag Left (neg X) -> Crop Increases
            let pDelta = -pixelDeltaX
            targetCropRight = max(0, anchor.initialCropRight + pDelta)
        }
        
        // Round for pixel snapping
        targetCropTop = round(targetCropTop)
        targetCropBottom = round(targetCropBottom)
        targetCropLeft = round(targetCropLeft)
        targetCropRight = round(targetCropRight)
        
        // Determine NEW Image Dimensions (Pixels)
        let newW = originalWidth - targetCropLeft - targetCropRight
        let newH = originalHeight - targetCropTop - targetCropBottom
        
        // Min Size Check (50px to prevent collapse)
        guard newW > 50 && newH > 50 else { return }
        
        // Apply Crop State
        cropTop = targetCropTop
        cropBottom = targetCropBottom
        cropLeft = targetCropLeft
        cropRight = targetCropRight
        
        // Calculate NEW Window Frame (Points)
        // We defer to the ANCHOR frame to ensure stability.
        // Screen Size = Image Size / Scale
        let newScreenW = newW / anchor.initialScale
        let newScreenH = newH / anchor.initialScale
        
        var targetFrame = anchor.initialFrame
        targetFrame.size = CGSize(width: newScreenW, height: newScreenH)
        
        // Adjust Origin based on Edge Anchor
        switch edge {
        case .top:
            // Drag Top: Bottom is fixed. Origin Y is bottom.
            // Origin Y stays anchor.initialFrame.origin.y
            targetFrame.origin.y = anchor.initialFrame.origin.y
            
        case .bottom:
            // Drag Bottom: Top is fixed. Origin Y moves.
            // New Origin Y = Old Top (MaxY) - New Height
            targetFrame.origin.y = anchor.initialFrame.maxY - newScreenH
            
        case .left:
            // Drag Left: Right is fixed. Origin X moves.
            // New Origin X = Old Right (MaxX) - New Width
            targetFrame.origin.x = anchor.initialFrame.maxX - newScreenW
            
        case .right:
            // Drag Right: Left is fixed. Origin X stays anchor.
            targetFrame.origin.x = anchor.initialFrame.origin.x
        }
        
        // Apply Frame
        setFrame(targetFrame, display: true, animate: false)
        
        // Perform Crop (Image Update)
        // Note: Y is from TOP in CGImage
        let cropRect = CGRect(x: cropLeft, y: cropTop, width: newW, height: newH)
        if let croppedImage = original.cropping(to: cropRect) {
            capturedImage = croppedImage
        }
        
        updateCropHandlePositions()
        
        // Viewport Update (Layer Translation)
        // CRITICAL FIX: Layer.frame uses POINTS, not pixels. Convert using scale.
        // Also, CGImage Y=0 is TOP, NSView Y=0 is BOTTOM.
        // 
        // For LEFT crop: Layer shifts LEFT so cropLeft pixels appear at view edge.
        //   layer.origin.x = -cropLeft / scale (negative = shift left)
        //
        // For TOP crop (CGImage removes from top): The BOTTOM of the image is now at window bottom.
        //   layer.origin.y = 0 (no shift needed, bottom stays aligned)
        //
        // For BOTTOM crop (CGImage removes from bottom): The TOP of the image stays at window top.
        //   In NSView coords, top = maxY. With smaller window, layer.origin.y should be negative
        //   to push the layer DOWN so its top aligns with window top.
        //   layer.origin.y = -(cropBottom / scale)
        //
        // Combined: layer origin = (-cropLeft/scale, -cropBottom/scale)
        //   Wait, that's what I had. Let me think again...
        //
        // Actually, the issue is SIZE. Layer size was using PIXELS, should be POINTS.
        
        let scale = anchor.initialScale
        let layerPointW = originalWidth / scale
        let layerPointH = originalHeight / scale
        
        // For X: shifting left to account for cropLeft
        let layerOriginX = -cropLeft / scale
        
        // For Y: In NSView, Y=0 is bottom. CGImage Y=0 is top.
        // When we crop TOP (CGImage), we're removing from view's TOP (high Y).
        // When we crop BOTTOM (CGImage), we're removing from view's BOTTOM (low Y).
        // If cropTop > 0: window's top is now at originalHeight - cropTop (in image pixels).
        //   Layer's top content (image Y=0) should appear at window's NEW top.
        //   But window shrunk from top, so layer shifts UP.
        // If cropBottom > 0: window's bottom is now at cropBottom (in image pixels).
        //   Layer's bottom content (image Y=originalHeight) should appear at window's NEW bottom.
        //   Layer shifts DOWN by cropBottom.
        //
        // In NSView layer.origin:
        //   - Positive Y = layer moves UP relative to superlayer
        //   - Negative Y = layer moves DOWN
        //
        // For cropTop: layer needs to shift UP? No wait...
        //   View is now shorter. Layer (full size) extends beyond view.
        //   We want image pixels [cropTop...originalHeight-cropBottom] to show.
        //   In view coords (Y=0 at bottom), these pixels map to [0...newH] in view.
        //   Layer's pixel range is [0...originalHeight].
        //   We need layer's [cropTop] to appear at view's [0]... no that's top crop.
        //
        // Let me think differently:
        //   Layer renders from its origin. Layer's (0,0) is its bottom-left in pixels.
        //   But wait, CGImage Y=0 is TOP, so layer's internal Y=0 is TOP of image.
        //   When CALayer renders CGImage, it FLIPS by default? Actually no.
        //
        // The AnnotationLayer draws in normalized coords [0,1].
        //   (0,0) = bottom-left of the layer's bounds
        //   (1,1) = top-right of the layer's bounds
        // When it draws, it denormalizes to layer.bounds.
        //
        // So if I shift layer.frame.origin:
        //   - origin.y = -100: layer moves DOWN 100 points. Content that was at layer.bounds Y=100 
        //     now appears at view Y=0 (view's bottom).
        //
        // For BOTTOM crop (removing from CGImage bottom, which is VIEW bottom):
        //   Window shrinks from bottom. Window's origin.y increases (moves up).
        //   We want layer's TOP to stay at window's TOP.
        //   Layer's top = layer.origin.y + layer.bounds.height
        //   Window's top = window.frame.maxY (fixed during bottom crop)
        //   So layer.origin.y = window.height - layer.height = -cropBottom/scale
        //   This is what I had!
        //
        // The issue might be that I'm not updating layer SIZE correctly in points.
        // Let me make sure size is in points:
        
        let layerOriginY = -cropBottom / scale
        
        let newLayerOrigin = CGPoint(x: layerOriginX, y: layerOriginY)
        let newLayerSize = CGSize(width: layerPointW, height: layerPointH)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        annotationLayer.frame = CGRect(origin: newLayerOrigin, size: newLayerSize)
        CATransaction.commit()
    }

    
    // Legacy func kept if needed, but overridden by above
    func cropFromEdge(_ edge: CropEdge, by amount: CGFloat) {
         // Should not be called by handles anymore
    }


    
    func showCropHandles() {
        // Always recreate handles to ensure they're in the correct view hierarchy
        // This fixes issues where handles become orphaned after zoom/crop operations
        setupCropHandles()
        
        for handle in cropHandles {
            handle.isHidden = false
        }
    }
    
    func hideCropHandles() {
        for handle in cropHandles {
            handle.isHidden = true
        }
    }
    
    func prepareForGroupDrag() {
        initialWindowOrigin = frame.origin
    }
}

// MARK: - OverlayContentViewDelegate

extension OverlayWindow: OverlayContentViewDelegate {
    
    func overlayViewDidReceiveClick(_ view: OverlayContentView) {
        // 1. Color Picker Click -> Handled by mouseDown to prevent closing/hiding
        // Just return to avoid double processing or closing.
        if isColorPickerMode {
            return
        }
    
        // If in crop mode, clicking on the image ends crop mode (saves the crop)
        if isCropMode {
            endCropMode()
            DebugLogger.shared.log("Crop mode ended - handles hidden")
            return
        }
        
        // If no tool active, handle close based on settings
        if toolManager.currentTool == nil {
            // Check Lock State First
            if isLocked {
                // Do nothing if locked
                return
            }
            
            // Check User Preference
            let behavior = UserDefaults.standard.string(forKey: "CloseClickBehavior") ?? "single"
            
            if behavior == "single" {
                overlayDelegate?.overlayWindowDidRequestClose(self)
            }
            // If "double", do nothing on single click (wait for double click)
        }
    }
    
    func overlayViewDidLayout(_ view: OverlayContentView) {
        if isCropMode {
            updateCropHandlePositions()
        }
    }
    
    func overlayViewDidReceiveDoubleClick(_ view: OverlayContentView) {
        if toolManager.currentTool == nil {
            // Check for double click on text
            // View gives us point in view coordinates
            let mousePoint = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? NSPoint.zero, from: nil)
            let normalized = normalizedPoint(mousePoint)
            
            // Priority 1: Text Editing (Always takes precedence)
            if let textStroke = hitTestTextAnnotation(at: normalized) {
                // Edit this text
                eraseStroke(at: normalized) // Remove existing from layer and metadata
                startTextEntry(at: annotationLayer.denormalizedPoint(textStroke.points.first ?? normalized), existingStroke: textStroke)
                return
            } 
            
            // Priority 2: Check User Preference for Close Behavior
            let behavior = UserDefaults.standard.string(forKey: "CloseClickBehavior") ?? "single"
            
            if behavior == "double" {
                // Check Lock State
                if !isLocked {
                    overlayDelegate?.overlayWindowDidRequestClose(self)
                }
            } else {
                // Default behavior (Single Click closes, Double Click zooms)
                // Note: If single click is enabled, the window likely closed on the first click anyway.
                // But if it didn't (e.g. race condition or prevented), we Zoom.
                toggleZoom()
            }
        }
    }
    
    func overlayViewDidReceiveRightClick(_ view: OverlayContentView, at point: CGPoint) {
        let menu = ContextMenuBuilder.buildMenu(for: self)
        menu.popUp(positioning: nil, at: point, in: view)
    }
    
    func overlayViewMouseDown(_ view: OverlayContentView, at point: CGPoint, event: NSEvent) {
        // CRITICAL: Commit any active text entry BEFORE starting a new action
        // This ensures the text becomes a stroke and gets remapped correctly during crop/drag
        if activeTextField != nil {
            commitTextEntry()
        }
        
        DebugLogger.shared.log("MouseDown at \(point), currentTool: \(String(describing: toolManager.currentTool)), cropMode: \(isCropMode)")
        
        // Correctly check for Spacebar using Carbon Event Source
        // 0x31 is 49 (Space)
        let isSpaceDown = CGEventSource.keyState(.combinedSessionState, key: 0x31)
        
        if isCropMode {
            // Start crop selection
            cropStartPoint = point
            setupCropSelectionLayer()
            return
        }
        
        // Dragging behavior (Move)
        // Active if Space is held OR no tool is active
        if isSpaceDown || toolManager.currentTool == nil {
            // Initialize manual drag state using SCREEN coordinates to avoid local coord vibration
            initialMouseLocation = NSEvent.mouseLocation
            initialWindowOrigin = frame.origin
            overlayDelegate?.overlayWindowDidStartDrag(self)
            DebugLogger.shared.log("Started manual drag at screen pos: \(NSEvent.mouseLocation)")
        } else if let tool = toolManager.currentTool {
            if tool == .text {
                startTextEntry(at: point)
            } else if tool != .eraser {
                // Start drawing for pen/highlighter
                DebugLogger.shared.log("Starting stroke at normalized: \(normalizedPoint(point))")
                toolManager.beginStroke(at: normalizedPoint(point))
            }
            // Eraser doesn't start strokes - it removes on mouseUp
        } else {
             // Move Mode (No tool)
             // Check if we hit a text annotation to drag
             let normPoint = normalizedPoint(point)
             if let stroke = hitTestTextAnnotation(at: normPoint) {
                 draggedAnnotation = stroke
                 dragStartLocation = annotationLayer.denormalizedPoint(stroke.points.first ?? .zero)
                 dragStartMouse = point
                 DebugLogger.shared.log("Started dragging text: \(stroke.id)")
             } else {
                 // Manual window drag fallback
                 // Initialize manual drag state using SCREEN coordinates to avoid local coord vibration
                 initialMouseLocation = NSEvent.mouseLocation
                 initialWindowOrigin = frame.origin
                 overlayDelegate?.overlayWindowDidStartDrag(self)
                 DebugLogger.shared.log("Started manual drag at screen pos: \(NSEvent.mouseLocation)")
             }
        }
    }
    
    // MARK: - Text Entry
    

    
    private func startTextEntry(at point: CGPoint, existingStroke: Stroke? = nil) {
        // If already editing, commit existing
        if let _ = activeTextField {
            commitTextEntry()
        }
        
        let textField = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 200, height: 40))
        textField.isBordered = false
        textField.isBezeled = false
        textField.focusRingType = .none
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        
        // Font settings
        // Always use standard font, ignore previous/tool formatting as requested "remove those"
        let fontSize = existingStroke?.fontSize ?? toolManager.textSize
        let fontName = "Helvetica" // Standardize
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        
        // Enforce Italic Default
        font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        
        let color = existingStroke?.color ?? toolManager.textColor

        
        textField.font = font
        textField.textColor = color.nsColor
        textField.alignment = .left
        
        if let text = existingStroke?.text {
            textField.stringValue = text
        }
        
        // Configure wrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.lineBreakMode = .byCharWrapping // Allow splitting long words
        // (Garbage removed)
        textField.usesSingleLineMode = false
        textField.lineBreakMode = .byCharWrapping
        textField.maximumNumberOfLines = 0
        
        // Calculate constrained width
        // User requested 2mm margin (approx 6 points).
        let maxAvailableWidth = overlayView.bounds.width - point.x - 6
        
        // Start with a small width that grows, but constrained by max available
        var targetWidth: CGFloat = min(max(50.0, 100.0), maxAvailableWidth)
        
        // If editing, use existing stroke width initially
        if let strokeWidth = existingStroke?.width {
            targetWidth = min(strokeWidth * metadata.zoom, maxAvailableWidth)
        }
        
        // Initial Frame Logic (Non-Flipped Coordinates)
        // Click point `point` should be the TOP-Left of the text field.
        // Since Y grows UP, Top = Y + Height.
        // So Origin.y = Click.y - Height.
        
        var frame = CGRect(origin: .zero, size: CGSize(width: targetWidth, height: 40)) // Initial guess height
        
        // Refine height based on content or default
        let testSize = textField.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: targetWidth, height: .greatestFiniteMagnitude)) ?? CGSize(width: targetWidth, height: 40)
        let initialHeight = max(40.0, testSize.height)
        
        frame.size.height = initialHeight
        frame.origin = CGPoint(x: point.x, y: point.y - initialHeight) // Align Top to Click
        
        textField.frame = frame
        
        textField.delegate = self
        
        overlayView.addSubview(textField)
        textField.becomeFirstResponder()
        
        activeTextField = textField
        
        // Sync ToolManager to this text's properties if editing
        if existingStroke != nil {
            ToolManager.shared.textColor = color
            ToolManager.shared.textSize = fontSize
            // Formatting properties removed from ToolManager sync
        }
        
        DebugLogger.shared.log("Started text entry at \(point)")
    }
    
    func updateActiveTextAttributes() {
        guard let textField = activeTextField else { return }
        
        // Update font if size changed (formatting removed)
        let fontSize = toolManager.textSize
        let fontName = "Helvetica"
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        // Enforce Italic
        font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)

        
        textField.font = font
        textField.textColor = toolManager.textColor.nsColor
        textField.sizeToFit() // Resize if font changed
    }
    
    private func hitTestTextAnnotation(at normalizedPoint: CGPoint) -> Stroke? {
        // We need to check strokes in reverse order
        // Problem: Stroke only has points, not a frame. Text frame is calculated in AnnotationLayer.
        // We should ask AnnotationLayer for hit testing.
        // But AnnotationLayer uses denormalized points.
        
        // Let's implement basic hit test here or delegate to AnnotationLayer?
        // AnnotationLayer has `removeStroke(at:)` which does hit testing.
        // But we just want to peek, not remove yet.
        // Let's add `hitTest(at:)` to AnnotationLayer.
        return annotationLayer.hitTestStroke(at: normalizedPoint)
    }
        

    
    func commitTextEntry() {
        guard let textField = activeTextField else { return }
        
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !text.isEmpty {
            // Calculate normalized position from the text field's origin
            let point = normalizedPoint(textField.frame.origin)
            
            // Calculate width and height normalized for zoom
            // AnnotationLayer multiplies stroke.width/height by currentZoom
            // So we store unzoomed values: value / zoom
            let width = textField.frame.width / metadata.zoom
            let height = textField.frame.height / metadata.zoom
            
            let stroke = toolManager.createTextAnnotation(at: point, text: text, width: width, height: height)
            addStroke(stroke)
            DebugLogger.shared.log("Committed text annotation: \(text)")
        }
        
        textField.removeFromSuperview()
        activeTextField = nil
        
        // Keep text tool active so user can add more text annotations (like Pen)
        // User must explicitly select Move Mode or another tool to deselect
        
        // Re-focus window
        self.makeKey()
    }
    
    func overlayViewMouseDragged(_ view: OverlayContentView, at point: CGPoint, event: NSEvent) {
        if isCropMode, let startPoint = cropStartPoint {
            // Update crop selection visual
            updateCropSelectionLayer(from: startPoint, to: point)
            return
        }
        
        // Text Dragging
        if let stroke = draggedAnnotation, let startMouse = dragStartMouse, let startLoc = dragStartLocation {
            let deltaX = point.x - startMouse.x
            let deltaY = point.y - startMouse.y
            
            // Calculate new position
            let newX = startLoc.x + deltaX
            let newY = startLoc.y + deltaY
            
            // Constrain to bounds (optional, but good for "not going out")
            // Allow some overhang but keep it vaguely on screen
            
            let newPoint = CGPoint(x: newX, y: newY)
            
            // Update Stroke
            // Since Stroke is struct, we must replace it.
            // Remove old
            eraseStroke(at: normalizedPoint(startLoc)) // This removes by checking stroke at point. ID check better.
            // Actually eraseStroke takes a point and hits test.
            // We should use ID based removal or just remove the specific object from arrays.
            // OverlayWindow doesn't have direct access to removeById easily without logic.
            // `metadata.annotations` has it. `AnnotationLayer` needs it.
            
            // Safer: Modify annotationLayer to update position?
            // "Instant" update during drag:
            // removing and adding every frame is expensive (recreates CALayer).
            // Better: Just update the CALayer position directly for now?
            // But we need to update model eventually.
            // Let's UPDATE model on UP, but update VISUAL on Drag.
            // But `AnnotationLayer` abstracts layers.
            // Let's try simple remove/add. It might be fast enough for text.
            
            var newStroke = stroke
            newStroke.points = [normalizedPoint(newPoint)]
            
            // Remove old specific stroke
            metadata.annotations.removeAll { $0.id == stroke.id }
            annotationLayer.removeStroke(stroke) // We need public removeStroke(stroke)
            
            // Add new
            addStroke(newStroke)
            draggedAnnotation = newStroke // Update reference
            dragStartLocation = newPoint // Reset start to current? Or keep cumulative?
            // If we replace, we reset.
            // Actually simpler: `dragStartMouse` is fixed. `dragStartLocation` is fixed.
            // New position is calculated from specific delta.
            // So we DON'T update start vars each frame.
            
            return
        }
        
        // Check "is dragging window" state via initialMouseLocation existence (for manual drag)
        if let initialMouse = initialMouseLocation, let initialOrigin = initialWindowOrigin {
            // Manual window dragging logic using SCREEN coordinates
            let currentMouse = NSEvent.mouseLocation
            
            // Calculate delta
            let deltaX = currentMouse.x - initialMouse.x
            let deltaY = currentMouse.y - initialMouse.y
            
            let newOrigin = CGPoint(
                x: initialOrigin.x + deltaX,
                y: initialOrigin.y + deltaY
            )
            
            // NOTE: User requested ability to drag to ANY monitor even if "Locked".
            // "Lock to Display" now mainly controls Space behavior (collectionBehavior).
            // We do NOT call constrainToSourceDisplay(newOrigin) here anymore.
            
            setFrameOrigin(newOrigin)
            overlayDelegate?.overlayWindowDidMove(self, delta: CGPoint(x: deltaX, y: deltaY))
            return
        }
        
        if let tool = toolManager.currentTool, tool != .eraser {
            // Continue drawing for pen/highlighter
            // Ensure we are inside bounds? normalizedPoint handles division.
            toolManager.continueStroke(at: normalizedPoint(point))
            
            if let stroke = toolManager.currentStroke {
                annotationLayer.updateCurrentStroke(stroke)
            }
        }
    }
    
    func overlayViewMouseUp(_ view: OverlayContentView, at point: CGPoint) {
        if isCropMode, let startPoint = cropStartPoint {
            // Remove crop selection visual
            removeCropSelectionLayer()
            
            // Apply crop if dragged enough
            let dragDistance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            if dragDistance > 10 {
                let cropRect = CGRect(
                    x: min(startPoint.x, point.x),
                    y: min(startPoint.y, point.y),
                    width: abs(point.x - startPoint.x),
                    height: abs(point.y - startPoint.y)
                )
                applyCrop(to: cropRect)
            } else {
                 // Too small, treat as click to clear selection
                 DebugLogger.shared.log("Crop selection too small, ignoring")
            }
            cropStartPoint = nil
            return
        }
        
        if draggedAnnotation != nil {
            draggedAnnotation = nil
            dragStartLocation = nil
            dragStartMouse = nil
            return
        }
        
        // Handle Click-to-Close or Click Action
        // If we were in "drag mode" keys (space or no tool)...
        if initialMouseLocation != nil {
            // It was a potential drag. Check if we moved significantly?
            // Actually, if we just clicked, delta would be 0 or small.
            // But OverlayWindow handles drag in real-time.
            // If we are here, drag is finished.
            
            // IMPORTANT: If 'no tool' is active, single click should CLOSE.
            // We can detect "click" if mouse didn't move much?
            // Or rely on `overlayViewDidReceiveClick` from `OverlayContentView`?
            // `OverlayContentView.mouseUp` calls `delegate.overlayViewMouseUp` AND then `delegate.overlayViewDidReceiveClick`.
            // So we don't need to close here. We just cleanup drag state.
            // The `overlayViewDidReceiveClick` will fire next.
            
            initialMouseLocation = nil
            initialWindowOrigin = nil
            return
        }
        
        if let tool = toolManager.currentTool {
            if tool == .eraser {
                // Eraser removes strokes at the click location
                let normalPoint = normalizedPoint(point)
                if let removedStroke = annotationLayer.removeStroke(at: normalPoint) {
                    // Also remove from metadata
                    metadata.annotations.removeAll { $0.id == removedStroke.id }
                    // DebugLogger.shared.log("Eraser removed stroke: \(removedStroke.id)")
                }
            } else {
                // Finish stroke for pen/highlighter
                if let stroke = toolManager.endStroke() {
                    addStroke(stroke)
                }
            }
        }
        
        initialMouseLocation = nil
        initialWindowOrigin = nil
    }
    
    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        // CORRECTION: Normalize relative to the Annotation Layer (Original Image Space)
        // If we are cropped, 'overlayView' is small, but 'annotationLayer' is full size and shifted.
        // We must map the view point to the layer's coordinate space first.
        
        // 1. Convert point from View to Layer
        // Since annotationLayer is a sublayer of overlayView.layer:
        // Layer Point = View Point - Layer Origin
        // (Layer Origin is typically negative if cropped, e.g., -50, -50)
        let layerOrigin = annotationLayer.frame.origin
        let pointInLayer = CGPoint(x: point.x - layerOrigin.x, y: point.y - layerOrigin.y)
        
        // 2. Normalize relative to Layer Size (Original Full Size)
        let layerSize = annotationLayer.bounds.size
        
        // Avoid div by zero
        guard layerSize.width > 0, layerSize.height > 0 else { return .zero }
        
        return CGPoint(
            x: pointInLayer.x / layerSize.width,
            y: pointInLayer.y / layerSize.height
        )
    }
    
    // MARK: - OCR Text Selection
    
    func showTextSelection() {
        // Remove existing if any
        overlayView.subviews.removeAll { $0 is TextSelectionOverlay }
        
        let textOverlay = TextSelectionOverlay(
            frame: overlayView.bounds,
            image: capturedImage,
            onComplete: { [weak self] text in
                self?.handleTextSelectionComplete(text)
            },
            onCancel: { [weak self] in
                self?.hideTextSelection()
            }
        )
        
        textOverlay.autoresizingMask = [.width, .height]
        overlayView.addSubview(textOverlay)
    }
    
    private func handleTextSelectionComplete(_ text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Audit log
        AuditLogger.shared.log(.copy, details: "Text copied via selection", screenshotID: metadata.id, userInfo: [
            "textLength": "\(text.count)"
        ])
        
        // Sound and feedback (muted per user request)
        // NSSound(named: "Tink")?.play()
        hideTextSelection()
    }
    
    func hideTextSelection() {
        overlayView.subviews.removeAll { $0 is TextSelectionOverlay }
    }
    
    // MARK: - Visual Feedback
    
    func setSavingHighlight(_ active: Bool) {
        if active {
            // Phase 31: Use NeonFeedbackLayer — renders above settings neon border
            NeonFeedbackLayer.show(on: overlayView)
        } else {
            NeonFeedbackLayer.hide(from: overlayView)
        }
    }
    
    /// Determines appropriate highlight color based on edge pixels
    /// Returns yellow if background is reddish, otherwise red
    /// Cached for performance
    func determineHighlightColor() -> NSColor {
        // Return cached value if available
        if let cached = _cachedHighlightColor {
            return cached
        }
        
        // Sample pixels from image edges to detect if background is reddish
        let cgImage = capturedImage
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 0, height > 0 else {
            _cachedHighlightColor = NSColor.systemRed
            return NSColor.systemRed
        }
        
        // For performance, only sample if image is reasonably sized
        // For very large images, just use red to avoid slowdown
        guard width * height < 10_000_000 else {
            _cachedHighlightColor = NSColor.systemRed
            return NSColor.systemRed
        }
        
        // Create bitmap context to read pixels
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            _cachedHighlightColor = NSColor.systemRed
            return NSColor.systemRed
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            _cachedHighlightColor = NSColor.systemRed
            return NSColor.systemRed
        }
        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        // Sample edge pixels (corners and midpoints of edges)
        let samplePoints: [(Int, Int)] = [
            (0, 0), (width-1, 0), (0, height-1), (width-1, height-1),  // corners
            (width/2, 0), (width/2, height-1), (0, height/2), (width-1, height/2)  // edge midpoints
        ]
        
        var redCount = 0
        for (x, y) in samplePoints {
            let offset = (y * width + x) * 4
            let r = pointer[offset]
            let g = pointer[offset + 1]
            let b = pointer[offset + 2]
            
            // Check if pixel is "reddish" - red is dominant and significantly higher than green/blue
            if r > 120 && CGFloat(r) > CGFloat(g) * 1.3 && CGFloat(r) > CGFloat(b) * 1.3 {
                redCount += 1
            }
        }
        
        // If more than half the sample points are reddish, use yellow
        let result: NSColor
        if redCount >= samplePoints.count / 2 {
            result = NSColor.systemYellow
        } else {
            result = NSColor.systemRed
        }
        
        _cachedHighlightColor = result
        return result
    }
    
    // MARK: - Lock Indicator
    
    private func showLockedIndicator() {
        // Remove existing first
        hideLockedIndicator()
        
        // Add a permanent lock icon or border?
        // User requested: "show a yellow border dim light IF the user clicks on the locked screenshot"
        // But we probably want some visual indication that it is locked too?
        // Let's add a small lock icon in the corner
        
        let lockLayer = CATextLayer()
        lockLayer.name = "LockIcon"
        lockLayer.string = "🔒"
        lockLayer.fontSize = 16
        lockLayer.alignmentMode = .center
        lockLayer.foregroundColor = NSColor.white.cgColor
        lockLayer.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        lockLayer.cornerRadius = 10
        // Frame will be set by update wrapper
        
        lockLayer.shadowOpacity = 0.5
        lockLayer.shadowRadius = 2
        lockLayer.shadowOffset = CGSize(width: 0, height: -1)
        
        overlayView.layer?.addSublayer(lockLayer)
        updateLockIndicatorPosition()
    }
    
    // MARK: - Display Lock Indicator
    
    private func showDisplayLockedIndicator() {
        hideDisplayLockedIndicator() // Remove existing first
        
        let pinLayer = CATextLayer()
        pinLayer.name = "DisplayLockIcon"
        pinLayer.string = "📌" // Pin emoji to represent locked to display
        pinLayer.fontSize = 16
        pinLayer.alignmentMode = .center
        pinLayer.foregroundColor = NSColor.white.cgColor
        pinLayer.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        pinLayer.cornerRadius = 10
        
        pinLayer.shadowOpacity = 0.5
        pinLayer.shadowRadius = 2
        pinLayer.shadowOffset = CGSize(width: 0, height: -1)
        
        overlayView.layer?.addSublayer(pinLayer)
        updateDisplayLockIndicatorPosition()
    }
    
    private func hideDisplayLockedIndicator() {
        overlayView.layer?.sublayers?.removeAll(where: { $0.name == "DisplayLockIcon" })
    }
    
    private func hideLockedIndicator() {
        overlayView.layer?.sublayers?.removeAll(where: { $0.name == "LockIcon" })
        overlayView.layer?.sublayers?.removeAll(where: { $0.name == "LockedFeedback" })
    }
    
    func flashLockedIndicator() {
        // Flash yellow border
        let layer = CALayer()
        layer.name = "LockedFeedback"
        layer.borderWidth = 4
        layer.borderColor = NSColor.systemYellow.withAlphaComponent(0.8).cgColor
        layer.cornerRadius = overlayView.layer?.cornerRadius ?? 0
        layer.frame = overlayView.bounds
        
        // Add animation
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 0.5
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        layer.add(animation, forKey: "flash")
        layer.opacity = 0.0 // End state
        
        overlayView.layer?.addSublayer(layer)
        
        // Play sound?
        NSSound.beep()
        
        // Remove after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            layer.removeFromSuperlayer()
        }
    }
    
    func updateLockIndicatorPosition() {
        guard let layer = overlayView.layer?.sublayers?.first(where: { $0.name == "LockIcon" }) else { return }
        
        // Update position to bottom-right with margin
        // Assuming NSView coordinates (0,0 is bottom-left)
        // If using flipped coordinates, y would be height - 30
        // Standard NSImageView is NOT flipped.
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(x: overlayView.bounds.width - 30, y: 10, width: 20, height: 20)
        CATransaction.commit()
    }
    
    func updateDisplayLockIndicatorPosition() {
        guard let layer = overlayView.layer?.sublayers?.first(where: { $0.name == "DisplayLockIcon" }) else { return }
        
        // Move to Top-Right corner instead of bottom right
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Top-right coordinates: x is width - 30, y is height - 30 (since origin points bottom-left in NSView)
        // Or if flipped view, y is 10. Let's check standard NSView (bottom-left origin):
        layer.frame = CGRect(x: overlayView.bounds.width - 30, y: overlayView.bounds.height - 30, width: 20, height: 20)
        CATransaction.commit()
    }
    // MARK: - Annotation Remapping
    
    private func remapAnnotations(from sourceStrokes: [Stroke], to cropRect: CGRect, originalSize: CGSize) {
        let newWidth = cropRect.width
        let newHeight = cropRect.height
        
        var preservedStrokes: [Stroke] = []
        
        for stroke in sourceStrokes {
            var newPoints: [CGPoint] = []
            var hasVisiblePoints = false
            
            for point in stroke.points {
                // Convert normalized point to absolute old coords
                let oldAbsX = point.x * originalSize.width
                let oldAbsY = point.y * originalSize.height
                
                // Calculate new normalized coords relative to cropRect
                // cropRect is in original image coordinates
                let newNormX = (oldAbsX - cropRect.origin.x) / newWidth
                let newNormY = (oldAbsY - cropRect.origin.y) / newHeight
                
                // Check bounds (allow slight tolerance for strokes crossing edge)
                // We actually want to keep point if it connects to visible part, 
                // but for now simple bounds check is okay.
                // Note: We include points slightly outside to ensure lines didn't just disappear at edge.
                if newNormX >= -0.1 && newNormX <= 1.1 && newNormY >= -0.1 && newNormY <= 1.1 {
                    hasVisiblePoints = true
                }
                
                newPoints.append(CGPoint(x: newNormX, y: newNormY))
            }
            
            if hasVisiblePoints {
                let newStroke = Stroke(
                    id: stroke.id,
                    toolType: stroke.toolType,
                    points: newPoints,
                    color: stroke.color,
                    lineWidth: stroke.lineWidth, 
                    opacity: stroke.opacity
                )
                preservedStrokes.append(newStroke)
            }
        }
        
        metadata.annotations = preservedStrokes
        
        annotationLayer.clearAll()
        for stroke in preservedStrokes {
            annotationLayer.addStroke(stroke)
        }
    }

    // MARK: - Advanced Features Methods
    
    @objc func toggleRuler(_ sender: Any?) {
        if isRulerActive {
            // Deactivate
            rulerOverlay?.removeFromSuperview()
            rulerOverlay = nil
        } else {
            // Activate
            rulerOverlay = RulerOverlay(frame: overlayView.bounds)
            rulerOverlay?.autoresizingMask = [.width, .height]
            // If Color Picker is active, suppress internal tooltip immediately
            if isColorPickerMode {
                rulerOverlay?.showsMeasurementTooltip = false
            }
            overlayView.addSubview(rulerOverlay!)
        }
    }
    // MARK: - Loupe & Color Picker (moved to OverlayWindow+Loupe.swift)
    
    @objc func toggleGrayscale() {
        isGrayscale.toggle()
        updateDisplayImage()
        
        if isGrayscale {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(0.0, forKey: kCIInputSaturationKey)
                annotationLayer.filters = [filter]
            }
        } else {
            annotationLayer.filters = nil
        }
    }
    

    // MARK: - Copy Feedback (Prompt 8)
    
    func showCopiedFeedback() {
        // 1. "Copied" text label centered on the screenshot
        let copiedLabel = NSTextField(labelWithString: LanguageManager.shared.string("label_copied"))
        copiedLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        copiedLabel.textColor = .white
        copiedLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        copiedLabel.drawsBackground = true
        copiedLabel.alignment = .center
        copiedLabel.wantsLayer = true
        copiedLabel.layer?.cornerRadius = 8
        copiedLabel.layer?.masksToBounds = true
        copiedLabel.sizeToFit()
        let labelWidth = copiedLabel.frame.width + 24
        let labelHeight = copiedLabel.frame.height + 12
        copiedLabel.frame = CGRect(
            x: (overlayView.bounds.width - labelWidth) / 2,
            y: (overlayView.bounds.height - labelHeight) / 2,
            width: labelWidth,
            height: labelHeight
        )
        overlayView.addSubview(copiedLabel)
        
        // 2. Neon border using centralized NeonFeedbackLayer
        NeonFeedbackLayer.flash(on: overlayView, duration: 0.5)
        
        // 3. Fade out after 0.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                copiedLabel.animator().alphaValue = 0
            } completionHandler: {
                copiedLabel.removeFromSuperview()
            }
        }
    }
    
    @objc func toggleLockToDisplay() {
        lockToDisplay.toggle()
    }


}

// MARK: - OverlayContentView

protocol OverlayContentViewDelegate: AnyObject {
    func overlayViewDidReceiveClick(_ view: OverlayContentView)
    func overlayViewDidReceiveDoubleClick(_ view: OverlayContentView)
    func overlayViewMouseDown(_ view: OverlayContentView, at point: CGPoint, event: NSEvent)
    func overlayViewMouseUp(_ view: OverlayContentView, at point: CGPoint)
    func overlayViewMouseDragged(_ view: OverlayContentView, at point: CGPoint, event: NSEvent)
    func overlayViewDidReceiveRightClick(_ view: OverlayContentView, at point: CGPoint)
    func overlayViewDidLayout(_ view: OverlayContentView)
}

class OverlayContentView: NSImageView {
    
    weak var delegate: OverlayContentViewDelegate?
    
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func layout() {
        super.layout()
        delegate?.overlayViewDidLayout(self)
    }
    
    override func cursorUpdate(with event: NSEvent) {
        if let win = window as? OverlayWindow {
            // Priority 1: Annotation Tools
            if win.currentTool != nil {
                super.cursorUpdate(with: event)
                return
            }
            
            // Priority 2: Color Picker
            if win.isColorPickerMode {
                // Use a crosshair or specific Eyedropper if available
                NSCursor.crosshair.set()
                return
            }
        }
        super.cursorUpdate(with: event)
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        
        if let window = window as? OverlayWindow {
            // Ghost mode → no cursor override, use default arrow
            if window.isGhostMode { return }
            
            DebugLogger.shared.log("ResetCursorRects: CurrentTool: \(String(describing: window.currentTool))")
            let cursor: NSCursor
            switch window.currentTool {
            case .pen:
                // Tip is at bottom-right for pencil/highlighter
                cursor = cursorFromSymbol("pencil", hotspot: CGPoint(x: 22, y: 22)) 
            case .highlighter:
                cursor = cursorFromSymbol("highlighter", hotspot: CGPoint(x: 22, y: 22)) 
            case .eraser:
                // Center for eraser
                cursor = cursorFromSymbol("eraser", hotspot: CGPoint(x: 16, y: 16)) 
            case .text:
                cursor = .iBeam
            case nil:
                if window.isColorPickerMode {
                    // Try to load eyedropper cursor
                    cursor = cursorFromSymbol("eyedropper", hotspot: CGPoint(x: 8, y: 18))
                } else {
                    cursor = .arrow
                }
            case .blur:
                cursor = .crosshair
            case .stickyNote:
                cursor = .arrow
            case .crop:
                cursor = .crosshair
            }
            addCursorRect(bounds, cursor: cursor)
        }
    }
    
    private func cursorFromSymbol(_ name: String, hotspot: CGPoint) -> NSCursor {
        // Use bold weight for better visibility
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        
        if let symbolImage = NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(config) {
            let size = NSSize(width: 32, height: 32)
            let finalImage = NSImage(size: size)
            
            // Ensure we treat it as a template to allow tinting
            // symbolImage is immutable 'let', but we don't strictly need isTemplate for destinationIn masking.
            // If we did, we'd need a mutable copy.
            // symbolImage.isTemplate = true
            
            // Standard rect for the icon
            let iconRect = NSRect(origin: .zero, size: size)
            
            // Start Drawing context
            finalImage.lockFocus()
            
            // Draw White Outline using Shadow for visibility on dark/light
            let shadow = NSShadow()
            shadow.shadowColor = .white
            shadow.shadowBlurRadius = 2.0
            shadow.shadowOffset = .zero
            shadow.set()
            
            // Draw Black Icon
            NSColor.black.set()
            // Center in 32x32
            let drawRect = NSRect(x: (size.width - 22)/2, y: (size.height - 22)/2, width: 22, height: 22)
            symbolImage.draw(in: drawRect)
            
            finalImage.unlockFocus()
            
            return NSCursor(image: finalImage, hotSpot: hotspot)
        }
        DebugLogger.shared.log("CursorFromSymbol: Failed to load symbol '\(name)'")
        return .crosshair // Fallback
    }
    
    override func mouseDown(with event: NSEvent) {
        if let win = window as? OverlayWindow {
            // Track interaction for tray menu targeting
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.lastInteractedOverlayID = win.metadata.id
            }
            
            // Priority: Color Picker (Don't toggle Loupe if picking color)
            if win.isColorPickerMode {
                 let point = convert(event.locationInWindow, from: nil)
                 win.pickColor(at: point)
                 return
            }
            
            // Standard Loupe Toggle (Only if NOT picking color)
            if win.isLoupeActive {
                win.toggleLoupe(nil)
                return
            }
        }
        let point = convert(event.locationInWindow, from: nil)
        delegate?.overlayViewMouseDown(self, at: point, event: event)
    }
    

    
    override func mouseDragged(with event: NSEvent) {
        // Track interaction for tray menu targeting
        if let win = window as? OverlayWindow,
           let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.lastInteractedOverlayID = win.metadata.id
        }
        let point = convert(event.locationInWindow, from: nil)
        delegate?.overlayViewMouseDragged(self, at: point, event: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        delegate?.overlayViewMouseUp(self, at: point)
        
        if event.clickCount == 1 {
            // Lock Check
            if let window = window as? OverlayWindow, window.isLocked {
                window.flashLockedIndicator()
                return
            }
            delegate?.overlayViewDidReceiveClick(self)
        } else if event.clickCount == 2 {
            delegate?.overlayViewDidReceiveDoubleClick(self)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        // Loupe handled by Timer
        super.mouseMoved(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let win = window as? OverlayWindow, win.isLoupeActive {
             win.toggleLoupe(nil)
             // Proceed to show context menu
        }
        
        let point = convert(event.locationInWindow, from: nil)
        delegate?.overlayViewDidReceiveRightClick(self, at: point)
    }
    
    override func keyDown(with event: NSEvent) {
        if let window = window as? OverlayWindow {
            // Hotkey Handling
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Ctrl+M for Magnifier
            if flags.contains(.control) {
                 if let chars = event.charactersIgnoringModifiers?.lowercased() {
                     if chars == "m" {
                         window.toggleLoupe(nil)
                         return
                     }
                 }
            }
            
            if flags.contains([.control, .option]) {
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case "p":
                        window.currentTool = .pen
                        DebugLogger.shared.log("ContextView Hotkey: Pen")
                        return
                    case "h":
                        window.currentTool = .highlighter
                        DebugLogger.shared.log("ContextView Hotkey: Highlighter")
                        return
                    case "e":
                        window.currentTool = .eraser
                        DebugLogger.shared.log("ContextView Hotkey: Eraser")
                        return
                    case "m":
                        window.currentTool = nil
                        // Disable advanced features
                        if window.isLoupeActive { window.toggleLoupe(nil) }
                        if window.isColorPickerMode { window.toggleColorPicker(nil) }
                        
                        DebugLogger.shared.log("ContextView Hotkey: Move")
                        return
                    case "t":
                        window.currentTool = .text
                        DebugLogger.shared.log("ContextView Hotkey: Text")
                        return
                    default:
                        break
                    }
                }
            }

            if event.keyCode == 53 { // Escape

                
                // 2. Color Picker (High Priority Mode)
                if window.isColorPickerMode { 
                    window.toggleColorPicker(nil)
                    return 
                }
                
                // 3. Close Loop/Magnifier if strictly active
                if window.isLoupeActive {
                    window.toggleLoupe(nil)
                    return
                }
                
                // 4. End Crop Mode
                window.endCropMode()
                
                // 5. Clear Tool (return to Move Mode)
                // 5. Clear Tool (return to Move Mode)
                if window.currentTool != nil {
                     window.currentTool = nil
                     NSCursor.arrow.set()
                     DebugLogger.shared.log("ESC - Tool Cleared")
                }
            } else {
                super.keyDown(with: event)
            }
        } else {
             super.keyDown(with: event)
        }
    }

}

// MARK: - Crop Handle

enum CropEdge {
    case top, bottom, left, right
}


class CropHandle: NSView {
    
    let edge: CropEdge
    weak var overlayWindow: OverlayWindow?
    
    private var isDragging = false
    private var lastDragLocation: CGPoint = .zero
    
    init(edge: CropEdge, overlayWindow: OverlayWindow) {
        self.edge = edge
        self.overlayWindow = overlayWindow
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.cgColor
        layer?.cornerRadius = 3
        
        // Set cursor based on edge
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func cursorUpdate(with event: NSEvent) {
        switch edge {
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        lastDragLocation = NSEvent.mouseLocation
        overlayWindow?.startCrop(edge: edge)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = overlayWindow else { return }
        window.updateCrop(edge: edge)
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}

extension OverlayWindow: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Check for Command Modifier -> Commit
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.command) {
                 commitTextEntry()
                 return true
            }
            // Manual Newline Insertion
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Cancel on Esc
            activeTextField?.removeFromSuperview()
            activeTextField = nil
            self.makeKey()
            return true
        }
        return false
    }
    
    // Fix: Text field not expanding correctly
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = activeTextField else { return }
        
        // 1. Determine constraints
        // Max width is from current X position to 6px from right edge
        let maxAvailableWidth = overlayView.bounds.width - textField.frame.origin.x - 6
        
        // 2. Measure text
        let attrString = textField.attributedStringValue
        
        // Measure with unlimited width first to see natural length
        let naturalSize = attrString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        
        // 3. Determine new dimensions
        // Width: Grow naturally, but cap at maxAvailableWidth. Ensure at least 50px.
        // Add padding (+10) to avoid jitter/early wrapping
        let newWidth = max(50.0, min(naturalSize.width + 10, maxAvailableWidth))
        
        // Height: Constrain by the determined width
        // Use a slightly narrower constraint for height calc to ensure we wrap BEFORE hitting the frame edge visual
        let heightConstraintWidth = newWidth - 4 // small inset for internal padding
        
        let heightRect = attrString.boundingRect(
            with: CGSize(width: heightConstraintWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let newHeight = max(40.0, ceil(heightRect.height) + 10) // +10 buffer
        
        // 4. Update Frame
        // IMPORTANT: Non-Flipped Coordinates (Default)
        // Y grows UP. To keep the visual TOP fixed, we must lower the origin Y as height increases.
        // Current Visual Top = currentFrame.minY + currentFrame.height
        // New Origin Y = Current Visual Top - New Height
        
        let currentFrame = textField.frame
        let currentVisualTop = currentFrame.maxY
        let newOriginY = currentVisualTop - newHeight
        
        var newFrame = currentFrame
        newFrame.size = CGSize(width: newWidth, height: newHeight)
        newFrame.origin.y = newOriginY
        
        textField.frame = newFrame
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        // Also commit when focus is lost (e.g. clicking away)
        // But distinguish from explicit Enter which already committed?
        if activeTextField != nil {
            commitTextEntry()
        }
    }
    
    // pickColor, showFloatingToast, rgbToHSL moved to OverlayWindow+Loupe.swift
}
