//
//  RegionSelector.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import Metal
import MetalKit
import CoreGraphics
import IOSurface

class RegionSelector: NSObject {
    
    // MARK: - Properties
    
    private var overlayWindows: [NSWindow] = []
    // Overlay Views Array swapped to MetalOverlayView
    private var overlayViews: [MetalOverlayView] = []
    
    private var isClosed = false
    private var selectionStartPoint: CGPoint?
    internal var selectionRect: CGRect = .zero
    private var activeDisplayID: CGDirectDisplayID?
    private var activeSelectionView: MetalOverlayView?  // Track which view started the selection
    private var isCountingDown = false // Prevent mouse events from firing during delay
    
    private var sizeTooltipWindow: NSWindow?
    private var sizeLabel: NSTextField?
    
    private let onComplete: (CGImage, CGRect, CGDirectDisplayID) -> Void
    private var captureDelay: TimeInterval = 0.0
    private var countdownTimer: Timer?
    private var timerWindow: TimerWindow?
    private var borderWindow: BorderWindow?
    
    // Store original presentation options to restore later
    // private var originalPresentationOptions: NSApplication.PresentationOptions = []
    
    // Quartz event tap for mouse events
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    
    // Throttled redraw timer (~60 FPS)
    private var redrawTimer: DispatchSourceTimer?
    
    private var keyDownMonitor: Any?
    
    // Frozen screen captures for each display (freeze-frame approach)
    private var frozenScreenshots: [CGDirectDisplayID: CGImage] = [:]
    
    // Background windows that display frozen screenshots (below selection panels)
    private var backgroundWindows: [NSWindow] = []
    
    // MARK: - Screen capture (zero-copy) integration
    private var captureEngine: ScreenCaptureEngine?
    private var captureDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Start capturing frames for the display that contains `point`
    private func startCaptureForPoint(_ point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()

        // If there's already an engine for this display, keep it.
        if captureEngine != nil { return }

        captureEngine = ScreenCaptureEngine(displayID: displayID)
        captureEngine?.start { [weak self] ioSurf, width, height in
            guard let self = self else { return }
            // Create Metal texture from IOSurface
            guard let device = self.captureDevice else { return }

            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]

            if let tex = device.makeTexture(descriptor: desc, iosurface: ioSurf, plane: 0) {
                // Provide the texture to the active overlay for possible GPU crop / preview
                self.activeOverlayView?.setSurfaceTexture(tex)
            } else {
                // Failed to create texture — fallback: nothing
            }
        }
    }

    private func stopCapture() {
        captureEngine?.stop()
        captureEngine = nil
        activeOverlayView?.setSurfaceTexture(nil)
    }

    // GPU cropper + live preview
    private var gpuCropper: GPUCropper?
    private var previewController: PreviewWindowController?

    private func ensureCropperAndPreview() {
        guard gpuCropper == nil, let device = captureDevice else { return }
        gpuCropper = GPUCropper(device: device)
        previewController = PreviewWindowController(device: device)
    }

    var activeOverlayView: MetalOverlayView? {
        return activeSelectionView
    }

    // MARK: - Initialization
    
    init(delay: TimeInterval = 0.0, onComplete: @escaping (CGImage, CGRect, CGDirectDisplayID) -> Void) {
        self.captureDelay = delay
        self.onComplete = onComplete
        super.init()
        DebugLogger.shared.log("RegionSelector initialized")
    }
    
    deinit {
        // M7: Safety net — remove event monitors if close() wasn't called
        if !isClosed {
            removeEventMonitors()
        }
        countdownTimer?.invalidate()
        DebugLogger.shared.log("RegionSelector deinit")
    }
    
    // MARK: - Public Methods
    
    func beginSelection() {
        // 1. Check user preference for freeze-frame behavior
        // Default to false for live live capture mode 
        let freezeEnabled = UserDefaults.standard.object(forKey: "FreezeScreenOnInstant") as? Bool ?? false
        let shouldFreeze = captureDelay == 0 && freezeEnabled
        
        // 2. Capture Frozen Screens IMMEDIATELY before any UI changes
        if shouldFreeze {
             captureFrozenScreens { [weak self] in
                 self?.finalizeSelectionUI(frozen: true)
             }
        } else {
             // Delayed capture OR freeze disabled: Live selection (transparent overlay)
             finalizeSelectionUI(frozen: false)
        }
    }
    
    private func finalizeSelectionUI(frozen: Bool) {
        createOverlayWindows(frozen: frozen)
        createSizeTooltip()
        setupEventMonitors()
        
        // Push crosshair cursor (same as macOS Cmd+Shift+4)
        // IMPORTANT: Do NOT call NSCursor.hide() here — it uses reference counting,
        // and an unmatched hide() will make the cursor invisible for the session.
        NSCursor.crosshair.push()
        NSCursor.crosshair.set()
    }
    
    /// Capture frozen screenshots of all displays before showing overlay concurrently for speed
    private func captureFrozenScreens(completion: @escaping () -> Void) {
        DebugLogger.shared.log("Capturing frozen screenshots concurrently for freeze-frame mode")
        
        let screens = NSScreen.screens
        let group = DispatchGroup()
        let lock = NSLock()
        
        for screen in screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                // Capture the entire display
                if let image = CGDisplayCreateImage(screenNumber) {
                    lock.lock()
                    self.frozenScreenshots[screenNumber] = image
                    lock.unlock()
                    DebugLogger.shared.log("Captured frozen screenshot for display \(screenNumber): \(image.width)x\(image.height)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion()
        }
    }
    
    func close() {
        guard !isClosed else { return }
        isClosed = true
        DebugLogger.shared.log("RegionSelector.close() called")
        
        // 1. Stop timer immediately to prevent any pending callbacks
        countdownTimer?.invalidate()
        countdownTimer = nil
        
        // 2. Remove event monitors FIRST
        removeEventMonitors()
        stopRedrawTimer()
        stopCapture()
        
        // 3. Remove all windows from screen
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        
        backgroundWindows.forEach { $0.orderOut(nil) }
        backgroundWindows.removeAll()
        
        // Clear frozen screenshots to free memory
        frozenScreenshots.removeAll()
        
        timerWindow?.orderOut(nil)
        timerWindow = nil
        
        borderWindow?.orderOut(nil)
        borderWindow = nil
        
        sizeTooltipWindow?.orderOut(nil)
        sizeTooltipWindow = nil
        
        activeSelectionView = nil
        
        // 4. Restore cursor
        NSCursor.unhide()
        NSCursor.arrow.set()
        
        // 5. Restore original presentation options
        // NSApp.presentationOptions = originalPresentationOptions
    }
    
    // MARK: - Event Monitors (for fullscreen compatibility)
    
    private func setupEventMonitors() {
        DebugLogger.shared.log("Setting up global event monitors for fullscreen support")
        
        // C8: Monitor for screen configuration changes (e.g., monitor unplugged)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenConfigChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        installEventTap()
        
        // Escape key monitor
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.close()
                return nil
            }
            return event
        }
    }
    
    private func installEventTap() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
                 | (1 << CGEventType.leftMouseDragged.rawValue)
                 | (1 << CGEventType.leftMouseUp.rawValue)
                 | (1 << CGEventType.mouseMoved.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let selector = Unmanaged<RegionSelector>.fromOpaque(refcon).takeUnretainedValue()

            let location = event.location

            switch type {
            case .leftMouseDown:
                selector.handleMouseDown(at: location)
            case .leftMouseDragged:
                selector.handleMouseDragged(at: location)
            case .leftMouseUp:
                selector.handleMouseUp(at: location)
            case .mouseMoved:
                selector.handleMouseMoved(at: location)
            default:
                break
            }

            return Unmanaged.passUnretained(event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap = eventTap else {
            print("Failed to create CGEvent tap")
            return
        }

        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func removeEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        eventTapSource = nil
    }
    
    @objc private func handleScreenConfigChanged() {
        DebugLogger.shared.log("Screen parameters changed - closing selection safely")
        close()
    }
    
    private func removeEventMonitors() {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let monitor = keyDownMonitor { NSEvent.removeMonitor(monitor) }
        keyDownMonitor = nil
        removeEventTap()
    }
    
    private func handleMouseDown(at point: CGPoint) {
        guard !isCountingDown else { return }
        
        // Use screen coordinates
        let screenPoint = NSEvent.mouseLocation
        DebugLogger.shared.log("Global mouseDown at: \(screenPoint)")
        
        selectionStartPoint = screenPoint
        activeDisplayID = LegacyCaptureEngine.displayID(for: screenPoint)
        
        // start streaming frames for the display where the user began selection
        startCaptureForPoint(screenPoint)
        
        // Find the view on the correct screen
        DebugLogger.shared.log("Searching \(overlayWindows.count) overlay windows for matching view")
        for (i, window) in overlayWindows.enumerated() {
            DebugLogger.shared.log("  Window[\(i)] frame=\(window.frame) contains=\(window.frame.contains(screenPoint)) isVisible=\(window.isVisible) level=\(window.level.rawValue)")
            if window.frame.contains(screenPoint),
               let view = window.contentView as? MetalOverlayView {
                activeSelectionView = view
                DebugLogger.shared.log("  -> Found activeSelectionView in window[\(i)]")
                break
            }
        }
        if activeSelectionView == nil {
            DebugLogger.shared.log("WARNING: activeSelectionView is nil after mouseDown!")
        }
    }
    
    private func handleMouseDragged(at point: CGPoint) {
        guard !isCountingDown else { return }
        
        guard let startPoint = selectionStartPoint else {
            DebugLogger.shared.log("handleMouseDragged: no startPoint, skipping")
            return
        }
        
        let screenPoint = NSEvent.mouseLocation
        
        // Calculate selection rectangle
        let x = min(startPoint.x, screenPoint.x)
        let y = min(startPoint.y, screenPoint.y)
        let width = abs(screenPoint.x - startPoint.x)
        let height = abs(screenPoint.y - startPoint.y)
        
        selectionRect = CGRect(x: x, y: y, width: width, height: height)
        
        // Forward rects to our metal view
        activeOverlayView?.updateSelection(rect: selectionRect)
        
        scheduleRedraw()
        
        updateSizeTooltip(at: screenPoint, size: selectionRect.size)
    }
    
    private func handleMouseUp(at point: CGPoint) {
        guard !isCountingDown else { return }
        
        stopRedrawTimer()
        // stop capture since selection is done; we will perform a GPU crop below
        stopCapture()
        
        // Finalize GPU crop and produce NSImage for export/clipboard
        if let img = finalizeSelectionAndExport() {
            // Example: copy to pasteboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }

        guard selectionRect.width > 5 && selectionRect.height > 5,
              let displayID = activeDisplayID else {
            DebugLogger.shared.log("Selection too small or no display ID, canceling")
            close()
            return
        }
        
        DebugLogger.shared.log("Selection complete: \(selectionRect)")
        
        if captureDelay >= 1.0 {
            startCountdown(rect: selectionRect, displayID: displayID)
        } else {
            performCapture(rect: selectionRect, displayID: displayID)
        }
    }
    
    private func handleMouseMoved(at point: CGPoint) {
        // Option to implement cursor updates here natively instead of monitoring in View
    }
    
    // MARK: - Throttled redraw

    private func scheduleRedraw() {
        if redrawTimer == nil {
            redrawTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            redrawTimer?.schedule(deadline: .now(), repeating: .milliseconds(16))

            redrawTimer?.setEventHandler { [weak self] in
                guard let self = self else { return }

                if let activeView = self.activeSelectionView {
                    activeView.needsDisplay = true
                }

                for overlay in self.overlayViews where overlay !== self.activeSelectionView {
                    overlay.needsDisplay = true
                }
                // Also update live GPU preview if possible
                self.updateLivePreviewIfNeeded()
            }

            redrawTimer?.resume()
        }
    }

    private func stopRedrawTimer() {
        redrawTimer?.cancel()
        redrawTimer = nil
    }

    private func updateLivePreviewIfNeeded() {
        guard let surfaceTex = activeOverlayView?.surfaceTexture,
              let start = selectionStartPoint,
              let gpuCropper = gpuCropper else { return }

        let current = NSEvent.mouseLocation

        // Compute pixel rect: convert points (NS coords) -> texture pixels
        // Determine the screen's scale factor
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(start) }) else { return }
        let scale = screen.backingScaleFactor

        let minX = Int(min(start.x, current.x) * scale)
        let minY = Int(min(start.y, current.y) * scale)
        let w = Int(abs(current.x - start.x) * scale)
        let h = Int(abs(current.y - start.y) * scale)

        guard w > 0 && h > 0 else { return }

        let texHeight = surfaceTex.height
        // Note: texture origin is lower-left; NSEvent.mouseLocation y is from bottom-left in CG coords.
        // If your coordinate systems differ, flip Y as needed:
        let pixelY = max(0, texHeight - (minY + h))

        let region = MTLRegion(origin: MTLOrigin(x: max(0, minX), y: max(0, pixelY), z: 0), size: MTLSize(width: w, height: h, depth: 1))

        // Ensure cropper & preview exist
        ensureCropperAndPreview()
        guard let cropped = gpuCropper.cropToTexture(sourceTexture: surfaceTex, pixelRect: region) else { return }

        // Send cropped texture to preview (fast — stays on GPU)
        previewController?.setPreviewTexture(cropped)
        // show preview near mouse (top-left of selection)
        let previewPoint = NSPoint(x: min(start.x, current.x), y: max(start.y, current.y) + 20)
        previewController?.show(at: previewPoint)
    }

    /// On completion (mouse up) produce an NSImage for export/clipboard using GPUCropper
    private func finalizeSelectionAndExport() -> NSImage? {
        guard let surfaceTex = activeOverlayView?.surfaceTexture,
              let start = selectionStartPoint,
              let gpuCropper = gpuCropper else { return nil }

        let current = NSEvent.mouseLocation

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(start) }) else { return nil }
        let scale = screen.backingScaleFactor

        let minX = Int(min(start.x, current.x) * scale)
        let minY = Int(min(start.y, current.y) * scale)
        let w = Int(abs(current.x - start.x) * scale)
        let h = Int(abs(current.y - start.y) * scale)
        guard w > 0 && h > 0 else { return nil }

        let texHeight = surfaceTex.height
        let pixelY = max(0, texHeight - (minY + h))
        let region = MTLRegion(origin: MTLOrigin(x: max(0, minX), y: max(0, pixelY), z: 0), size: MTLSize(width: w, height: h, depth: 1))

        // produce NSImage via GPUCropper
        let img = gpuCropper.cropToNSImage(sourceTexture: surfaceTex, pixelRect: region)
        return img
    }
    
    // MARK: - Overlay Windows
    
    private func createOverlayWindows(frozen: Bool) {
        // Store original presentation options for restoration
        // originalPresentationOptions = NSApp.presentationOptions
        
        // Force activation FIRST - critical for stealing focus from fullscreen apps
        NSApp.activate(ignoringOtherApps: true)
        
        // Create background windows ONLY if frozen (to display the static image)
        if frozen {
            createBackgroundWindows()
        }
        
        // Create overlay PANEL (not window) for each screen
        // NSPanel is specifically designed for floating utility windows and works better over fullscreen apps
        for screen in NSScreen.screens {
            // Get display ID for this screen
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            
            let panel = SelectionPanel(
                contentRect: screen.frame,
                // Adding .nonactivatingPanel to capture clicks over fullscreen apps without focus-stealing issues
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            
            // NSPanel specific properties — set BEFORE level because isFloatingPanel resets level
            panel.isFloatingPanel = true
            panel.worksWhenModal = true
            panel.hidesOnDeactivate = false // CRITICAL: Don't hide when app loses focus
            
            // Set level AFTER isFloatingPanel (which resets level to .floating = 3)
            // screenSaverWindow level ensures we are above the frozen background window
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
            
            // Enhanced collection behavior for fullscreen compatibility
            panel.collectionBehavior = [
                .canJoinAllSpaces,      // Appear on all Spaces including fullscreen
                .fullScreenAuxiliary,   // Can coexist with fullscreen apps
                .stationary,            // Stay in place during Space transitions
                .ignoresCycle,          // Don't appear in Cmd+Tab window cycle
                .transient              // Transient panel behavior
            ]
            
            panel.isMovableByWindowBackground = false
            panel.isReleasedWhenClosed = false // Critical: We manage lifecycle manually
            panel.acceptsMouseMovedEvents = true
            
            let selectionView = MetalOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), device: MTLCreateSystemDefaultDevice())
            selectionView.wantsLayer = true  // CRITICAL: Layer-backed for correct compositing over frozen background
            
            // No longer pass frozen image to view - background window handles it
            // selectionView.frozenImage = frozenScreenshots[displayID]
            
            panel.contentView = selectionView
            
            // Tell the panel to invalidate cursor rects so resetCursorRects will be called
            panel.invalidateCursorRects(for: selectionView)
            
            panel.makeKeyAndOrderFront(nil)
            overlayWindows.append(panel)
            overlayViews.append(selectionView)
        }
        
        
        
        // Hide menu bar to ensure we capture clicks at the top of the screen
        // The frozen image will still show the menu bar visually
        // STOPPED using autoHideMenuBar because it caused the menu bar to disappear visually for the user.
        // High window level (ScreenSaver + 1) should be enough to capture clicks.
        // NSApp.presentationOptions = [.autoHideMenuBar, .disableHideApplication]
        
        // Activate app AGAIN after windows are created to ensure we have focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Make the first panel key to receive events
        overlayWindows.first?.makeKey()
    }
    
    /// Create background windows that display frozen screenshots
    /// These sit below the selection panels and show the frozen screen content
    private func createBackgroundWindows() {
        for screen in NSScreen.screens {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            
            guard let frozenImage = frozenScreenshots[displayID] else {
                DebugLogger.shared.log("No frozen image for display \(displayID)")
                continue
            }
            
            // Create window at screen position using NSPanel with .nonactivatingPanel
            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            
            // Place just below the selection panels but still high enough to cover everything
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true // Let clicks pass through to selection panels

            
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
            
            window.isReleasedWhenClosed = false
            
            // Create NSImageView that handles all scaling automatically
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            
            // Create NSImage from CGImage
            let nsImage = NSImage(cgImage: frozenImage, size: NSSize(width: frozenImage.width, height: frozenImage.height))
            imageView.image = nsImage
            
            window.contentView = imageView
            window.orderFront(nil)
            backgroundWindows.append(window)
            
            DebugLogger.shared.log("Created background window for display \(displayID)")
        }
    }
    
    private func createSizeTooltip() {
        let tooltipRect = CGRect(x: 0, y: 0, width: 100, height: 28)
        
        let panel = NSPanel(
            contentRect: tooltipRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .popUpMenu
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        sizeTooltipWindow = panel
        
        sizeLabel = NSTextField(labelWithString: "0 × 0")
        sizeLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        sizeLabel?.textColor = .white
        sizeLabel?.alignment = .center
        // Vertically center text
        sizeLabel?.cell?.usesSingleLineMode = true
        sizeLabel?.cell?.truncatesLastVisibleLine = true
        sizeLabel?.frame = NSMakeRect(0, 4, tooltipRect.width, 20)
        
        if let label = sizeLabel {
            sizeTooltipWindow?.contentView?.addSubview(label)
        }
    }
    
    private func updateSizeTooltip(at point: CGPoint, size: CGSize) {
        guard let window = sizeTooltipWindow, let label = sizeLabel else { return }
        
        let text = "\(Int(size.width)) × \(Int(size.height))"
        label.stringValue = text
        
        // Resize window to fit text
        let textSize = (text as NSString).size(withAttributes: [.font: label.font!])
        let windowWidth = textSize.width + 24
        label.frame = NSMakeRect(0, 4, windowWidth, 20)
        
        // Dynamic Positioning to keep tooltip OUTSIDE selection
        // Default: Bottom-Right of cursor
        var windowOrigin = CGPoint(x: point.x + 15, y: point.y - 30) // Offset (15, -30) matches cursor tail
        
        // Check if cursor is Top-Left or Bottom-Left relative to start (dragging UP or LEFT implies we might be inside)
        // Actually, simpler check: Does the default position intersect the selection rect?
        
        // Construct standard tooltip rect
        let defaultTooltipRect = CGRect(x: windowOrigin.x, y: windowOrigin.y, width: windowWidth, height: 28)
        
        // Note: selectionRect is properly normalized (x,y is always bottom-left or top-left depending on coordinate system, but width/height always positive)
        // We need to be careful with coordinate spaces. RegionSelector uses Screen Coordinates (Bottom-Left origin usually? No, Cocoa uses Bottom-Left).
        // BUT NSEvent.mouseLocation is Screen Coordinates (Bottom-Left 0,0).
        // window.setFrame uses Screen Coordinates.
        
        // If the tooltip is inside the selection, flip it to the opposite side of the cursor.
        // Opposite of (15, -30) is (-Width - 15, +30)
        
        if selectionRect.intersects(defaultTooltipRect) {
            // Overlapping! Flip to Top-Left of cursor
            windowOrigin = CGPoint(
                x: point.x - windowWidth - 15,
                y: point.y + 15 // Move UP above cursor
            )
        }
        
        window.setFrame(CGRect(x: windowOrigin.x, y: windowOrigin.y, width: windowWidth, height: 28), display: true)
        
        if !window.isVisible {
            window.orderFront(nil)
        }
    }
    
    private func hideSizeTooltip() {
        sizeTooltipWindow?.orderOut(nil)
    }

    // MARK: - Legacy Event Callbacks
    
    // (Legacy SelectionViewDelegate functions removed due to MetalOverlayView transition)
    
    // MARK: - Countdown Logic
    
    private func startCountdown(rect: CGRect, displayID: CGDirectDisplayID) {
        // 0. Set counting down state to block all mouse monitors
        isCountingDown = true
        
        // 1. Hide Selection UI
        overlayWindows.forEach { $0.orderOut(nil) }
        sizeTooltipWindow?.orderOut(nil)
        
        // 2. Restore Cursor immediately so user can interact with apps
        NSCursor.unhide()
        NSCursor.arrow.set()
        // Try to pop crosshair if we pushed it
        NSCursor.crosshair.pop()
        
        // 3. Show Timer HUD
        // Position it roughly in the center of the screen (or selection?)
        // Center of selection might obscure subject. Center of screen is safer/standard.
        // Let's put it at center of selection but slightly above or below?
        // User request: "show a mini timer also which starts after the user selects an area"
        // Let's put it in the center of the screen for visibility.
        
        let screen = NSScreen.screens.first(where: { 
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID 
        }) ?? NSScreen.main
        
        let initialSeconds = Int(captureDelay)
        timerWindow = TimerWindow(seconds: initialSeconds)
        
        if let screenFrame = screen?.frame {
            // H6: Fall back to screen center if selection rect is not yet drawn
            if rect.width > 0 && rect.height > 0 {
                timerWindow?.centerIn(rect: rect)
            } else {
                timerWindow?.centerIn(rect: screenFrame)
            }
        }
        
        timerWindow?.makeKeyAndOrderFront(nil)
        
        // 3b. Show Border Window
        borderWindow = BorderWindow(frame: rect)
        borderWindow?.orderFront(nil)
        
        // 4. Start Timer
        var remaining = initialSeconds
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining > 0 {
                self?.timerWindow?.updateSeconds(remaining)
            } else {
                timer.invalidate()
                // Explicitly hide windows BEFORE capture — use guard to prevent stuck windows
                guard let self = self else {
                    // self was deallocated — timer/border are orphaned, nothing to do
                    return
                }
                self.timerWindow?.orderOut(nil)
                self.timerWindow = nil
                self.borderWindow?.orderOut(nil)
                self.borderWindow = nil
                
                // Wait for WindowServer to fully remove the windows from the compositor
                // before capturing, so the timer box doesn't appear in the screenshot
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.performCapture(rect: rect, displayID: displayID)
                }
            }
        }
    }
    
    func selectionDidCancel() {
        close()
    }
    
    private func performCapture(rect: CGRect, displayID: CGDirectDisplayID) {
        // Hide selection UI explicitly to prevent capturing the selection border (ants)
        self.overlayWindows.forEach { $0.orderOut(nil) }
        self.backgroundWindows.forEach { $0.orderOut(nil) }
        self.sizeTooltipWindow?.orderOut(nil)
        self.borderWindow?.orderOut(nil)
        self.timerWindow?.orderOut(nil)
        
        // CRITICAL: Force UI update to clear the windows from screen buffer
        // Adding a small sleep to let WindowServer catch up
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        DebugLogger.shared.log("performCapture (High Quality) started with rect: \(rect)")
        
        // 1. Get the image source
        // If we have a frozen image, use it. If not, capture NOW.
        var sourceImage = frozenScreenshots[displayID]
        
        if sourceImage == nil {
             // Live Capture Mode (Delayed)
             // Capture the screen now using the same reliable method as freeze frame
             DebugLogger.shared.log("Live capture: Capturing display \(displayID) now")
             sourceImage = CGDisplayCreateImage(displayID)
        }
        
        guard let validSourceImage: CGImage = sourceImage else {
            DebugLogger.shared.log("Error: No image source available for display \(displayID)")
            self.close()
            return
        }
        
        // 2. Hide windows immediately
        overlayWindows.forEach { $0.orderOut(nil) }
        backgroundWindows.forEach { $0.orderOut(nil) }
        sizeTooltipWindow?.orderOut(nil)
        
        NSCursor.unhide()
        NSCursor.arrow.set()
        NSCursor.crosshair.pop()
        
        // 3. Crop the image from the source buffer
        // Note: The rect is in Screen Points (logical), but frozenImage is in Pixels (physical)
        // We need to scale the rect to match the image resolution
        
        // Find the screen object to get its frame (points)
        let screen = NSScreen.screens.first(where: { 
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID 
        }) ?? NSScreen.main
        
        guard let screenFrame = screen?.frame else {
            close()
            return
        }
        
        // Calculate coordinate space
        // RegionSelector rect is in screen coordinates (bottom-left origin)
        // We need to convert it to the screen's local coordinates
        
        // Rect relative to the specific screen's origin
        var localRect = rect
        localRect.origin.x -= screenFrame.minX
        localRect.origin.y -= screenFrame.minY
        
        // Convert Y-axis (Flip from bottom-left to top-left origin)
        // Image origin is top-left
        let flippedY = screenFrame.height - localRect.maxY
        
        // Calculate scale factor (Physical Pixels / Logical Points)
        let imageWidth = CGFloat(validSourceImage.width)
        let imageHeight = CGFloat(validSourceImage.height)
        
        let scaleX = imageWidth / screenFrame.width
        let scaleY = imageHeight / screenFrame.height
        
        // Scale the rect to pixels
        let pixelRect = CGRect(
            x: localRect.origin.x * scaleX,
            y: flippedY * scaleY,
            width: localRect.width * scaleX,
            height: localRect.height * scaleY
        )
        
        DebugLogger.shared.log("Cropping frozen image. Screen: \(screenFrame.width)x\(screenFrame.height) Image: \(imageWidth)x\(imageHeight) Scale: \(scaleX)")
        DebugLogger.shared.log("Capture Rect: \(rect) -> Pixel Rect: \(pixelRect)")
        
        // Crop!
        if let croppedImage = validSourceImage.cropping(to: pixelRect) {
            DebugLogger.shared.log("Crop Success. Size: \(croppedImage.width)x\(croppedImage.height)")
            
            // Success!
            self.close()
            self.onComplete(croppedImage, rect, displayID)
        } else {
            DebugLogger.shared.log("Cropping failed")
            self.close()
            let error = NSError(domain: "com.silkysnip", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cropping failed"])
            self.showCaptureError(error)
        }
    }
    
    private func showCaptureError(_ error: Error) {
        let lm = LanguageManager.shared
        let alert = NSAlert()
        alert.messageText = lm.string("alert_capture_failed_title")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: lm.string("ok"))
        alert.runModal()
    }
}

// MARK: - SelectionPanel (NSPanel for fullscreen compatibility)

class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false } // Panels typically don't become main
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        // NSPanel specific setup
        self.becomesKeyOnlyIfNeeded = false // Always become key when clicked
    }
    
    deinit {
        print("[DebugLogger] SelectionPanel deinit") 
    }
}

// MARK: - SelectionView

protocol SelectionViewDelegate: AnyObject {
    func selectionDidStart(at point: CGPoint, in view: SelectionView)
    func selectionDidChange(to point: CGPoint, in view: SelectionView)
    func selectionDidEnd(at point: CGPoint, in view: SelectionView)
    func selectionDidCancel()
}

class SelectionView: NSView {
    
    weak var delegate: SelectionViewDelegate?
    var selectionRect: CGRect = .zero
    
    // Note: frozenImage managed by background window now
    
    private var isSelecting = false
    
    // MARCHING ANTS SUPPORT
    private var marchTimer: Timer?
    private var lineDashPhase: CGFloat = 0.0
    
    func startMarchingAnts() {
        stopMarchingAnts()
        marchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.lineDashPhase -= 1.0 // Move dash
            self.needsDisplay = true
        }
    }
    
    func stopMarchingAnts() {
        marchTimer?.invalidate()
        marchTimer = nil
        lineDashPhase = 0.0
        needsDisplay = true
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true 
    }
    
    deinit {
        print("[DebugLogger] SelectionView deinit")
        // Clean up tracking areas to prevent zombie crashes
        for area in trackingAreas {
            removeTrackingArea(area)
        }
    }
    
    // MARK: - Cursor Support
    
    override func resetCursorRects() {
        super.resetCursorRects()
        // Set crosshair cursor for entire view (same as macOS Cmd+Shift+4)
        addCursorRect(bounds, cursor: .crosshair)
    }
    
    override func cursorUpdate(with event: NSEvent) {
        // Always show crosshair cursor in this view
        NSCursor.crosshair.set()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove old tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        
        // Add tracking area to detect mouse enter/exit for cursor updates
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Force crosshair cursor when mouse enters
        NSCursor.crosshair.set()
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        // Keep crosshair cursor during mouse movement
        NSCursor.crosshair.set()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let dimColor = NSColor.black.withAlphaComponent(0.2)
        
        if selectionRect.width > 0 && selectionRect.height > 0 {
            // selectionRect is in global SCREEN coordinates.
            // 1. Convert screen rect to window coordinates
            let windowRect = window?.convertFromScreen(selectionRect) ?? selectionRect
            // 2. Convert window rect to local view coordinates
            let localRect = convert(windowRect, from: nil)
            
            // Draw dim overlay in the 4 regions AROUND the selection (not inside it)
            // This avoids using .clear compositing which breaks layer-backed views
            dimColor.setFill()
            
            // Top strip (above selection to top of view)
            NSRect(x: bounds.minX, y: localRect.maxY, 
                   width: bounds.width, height: bounds.maxY - localRect.maxY).fill()
            // Bottom strip (below selection to bottom of view)
            NSRect(x: bounds.minX, y: bounds.minY, 
                   width: bounds.width, height: localRect.minY - bounds.minY).fill()
            // Left strip (between top and bottom strips)
            NSRect(x: bounds.minX, y: localRect.minY, 
                   width: localRect.minX - bounds.minX, height: localRect.height).fill()
            // Right strip (between top and bottom strips)
            NSRect(x: localRect.maxX, y: localRect.minY, 
                   width: bounds.maxX - localRect.maxX, height: localRect.height).fill()
            
            // Draw selection border (High Contrast "Marching Ants" style)
            // 1. Black solid line (background)
            NSColor.black.setStroke()
            let blackBorderPath = NSBezierPath(rect: localRect.insetBy(dx: 0.5, dy: 0.5))
            blackBorderPath.lineWidth = 1.0
            blackBorderPath.stroke()
            
            // 2. White dashed line (foreground) 
            NSColor.white.setStroke()
            let whiteBorderPath = NSBezierPath(rect: localRect.insetBy(dx: 0.5, dy: 0.5))
            whiteBorderPath.lineWidth = 1.0
            let dashPattern: [CGFloat] = [4.0, 4.0]
            whiteBorderPath.setLineDash(dashPattern, count: 2, phase: lineDashPhase)
            whiteBorderPath.stroke()
            
            // Draw corner handles
            drawCornerHandles(for: localRect)
        } else {
            // No selection yet — dim the entire view
            dimColor.setFill()
            bounds.fill()
        }
    }
    
    private func drawCornerHandles(for rect: CGRect) {
        let handleSize: CGFloat = 8
        let handleColor = NSColor.white
        
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        
        handleColor.setFill()
        
        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSBezierPath(ovalIn: handleRect).fill()
        }
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        let screenPoint = window?.convertPoint(toScreen: point) ?? point
        
        isSelecting = true
        startMarchingAnts() // Start animation on selection start
        delegate?.selectionDidStart(at: screenPoint, in: self)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        
        let point = event.locationInWindow
        let screenPoint = window?.convertPoint(toScreen: point) ?? point
        
        delegate?.selectionDidChange(to: screenPoint, in: self)
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isSelecting else { return }
        
        let point = event.locationInWindow
        let screenPoint = window?.convertPoint(toScreen: point) ?? point
        
        isSelecting = false
        stopMarchingAnts() // Stop animation on finish
        delegate?.selectionDidEnd(at: screenPoint, in: self)
    }
    
    // MARK: - Keyboard Events
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            stopMarchingAnts()
            delegate?.selectionDidCancel()
        }
    }
}

// MARK: - TimerWindow

class TimerWindow: NSWindow {
    
    private let label: NSTextField
    
    init(seconds: Int) {
        let size: CGFloat = 50
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        
        self.label = NSTextField(labelWithString: "\(seconds)")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
        self.backgroundColor = .clear  // Window itself is clear; we draw the background in the container
        self.isOpaque = false
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        
        // Create a container view with rounded corners and 20% opacity background
        let container = NSView(frame: NSRect(origin: .zero, size: rect.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        
        self.contentView = container
        container.addSubview(label)
        
        // Center the label perfectly using Auto Layout
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }
    
    func updateSeconds(_ s: Int) {
        label.stringValue = "\(s)"
    }
    
    func centerIn(rect: CGRect) {
        let x = rect.midX - self.frame.width / 2
        let y = rect.midY - self.frame.height / 2
        self.setFrameOrigin(CGPoint(x: x, y: y))
    }
    
    override var canBecomeKey: Bool { false }
}

// MARK: - BorderWindow

class BorderWindow: NSWindow {
    
    init(frame: CGRect) {
        // Inset slightly to likely be outside capture if capture is exact rect?
        // Actually, user wants to identify the area.
        // We typically want the border OUTSIDE the selection if possible, or inside.
        // If we capture the rect, an inside border would be captured?
        // Wait, the timer captures the screen. If the border is visible, it WILL be captured unless we hide it.
        // The `cleanup` happens in the timer closure: `self?.borderWindow?.close()` THEN `performCapture`.
        // `performCapture` waits 0.05s via `DispatchQueue.main.asyncAfter`.
        // So the border window should be gone by the time capture happens.
        
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        
        // Ensure border is also high level
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true // Click-through
        self.isReleasedWhenClosed = false // Critical for manual management
        
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemBlue.cgColor // Dynamic system color
        view.layer?.borderWidth = 2.0
        // Corner radius to look nice? Or sharp? Selection is usually sharp.
        view.layer?.cornerRadius = 0
        
        self.contentView = view
    }
}


