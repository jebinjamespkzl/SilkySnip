//
//  OverlayWindow+Loupe.swift
//  SilkySnip
//
//  Extracted Loupe (Magnifier) and Color Picker logic from OverlayWindow.
//  Phase 30: Expanded scope to entire display (including additional monitors)
//  via CGDisplayCreateImage instead of sampling from capturedImage only.
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import AppKit
import QuartzCore

// MARK: - Loupe & Color Picker Extension

extension OverlayWindow {
    
    // MARK: - Loupe Toggle & Magnification
    
    @objc func toggleLoupe(_ sender: Any?) {
        // Mutual exclusion: disable color picker if active
        if !isLoupeActive && isColorPickerMode {
            toggleColorPicker(nil)
        }
        
        if isLoupeActive {
            loupeTimer?.invalidate()
            loupeTimer = nil
            loupeWindow?.orderOut(nil)
            loupeWindow = nil
            removeLoupeRightClickMonitor()
        } else {
            loupeWindow = LoupeWindow()
            loupeWindow?.level = .screenSaver
            loupeWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            loupeWindow?.orderFront(nil)
            
            let timer = Timer(timeInterval: 0.016, target: self, selector: #selector(updateLoupeState), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            loupeTimer = timer
            
            installLoupeRightClickMonitor()
        }
    }
    
    @objc func setMagnification(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? CGFloat else { return }
        
        // Toggle logic
        if isLoupeActive && magnificationLevel == level {
            toggleLoupe(nil) // Deactivate
        } else {
            self.magnificationLevel = level
            if isCropMode {
                updateCropHandlePositions()
            }
            if !isLoupeActive {
                toggleLoupe(nil) // Activate
            } else {
                updateLoupeState() // Update immediately
            }
        }
    }
    
    // MARK: - Screen-Wide Loupe Update (Phase 30)
    
    @objc func updateLoupeState() {
        guard let loupe = loupeWindow else { return }
        
        // 1. Get Mouse Location (Screen coordinates, AppKit bottom-left origin)
        let mouseLoc = NSEvent.mouseLocation
        
        // 2. Update Loupe Position (keep existing offset logic)
        let offset = CGPoint(x: 120, y: -120)
        let loupeCenter = CGPoint(x: mouseLoc.x + offset.x, y: mouseLoc.y + offset.y)
        
        // Screen-edge clamping for loupe position
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let loupeSize = loupe.frame.size
            var clampedCenter = loupeCenter
            
            // If loupe would overflow right, flip to left side
            if clampedCenter.x + loupeSize.width / 2 > screenFrame.maxX {
                clampedCenter.x = mouseLoc.x - offset.x - loupeSize.width
            }
            // If loupe would overflow left
            if clampedCenter.x - loupeSize.width / 2 < screenFrame.minX {
                clampedCenter.x = screenFrame.minX + loupeSize.width / 2
            }
            // If loupe would overflow bottom
            if clampedCenter.y - loupeSize.height / 2 < screenFrame.minY {
                clampedCenter.y = mouseLoc.y + abs(offset.y)
            }
            // If loupe would overflow top
            if clampedCenter.y + loupeSize.height / 2 > screenFrame.maxY {
                clampedCenter.y = screenFrame.maxY - loupeSize.height / 2
            }
            
            loupe.updatePosition(center: clampedCenter)
        } else {
            loupe.updatePosition(center: loupeCenter)
        }
        
        // 3. Determine which display the cursor is on
        let cursorScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
        let screenHeight = cursorScreen?.frame.height ?? (NSScreen.main?.frame.height ?? 900)
        let screenOriginY = cursorScreen?.frame.origin.y ?? 0
        
        // Convert AppKit coords (bottom-left) to CG coords (top-left)
        let cgMouseX = mouseLoc.x
        let cgMouseY = (screenOriginY + screenHeight) - mouseLoc.y
        
        var displayCount: UInt32 = 0
        var displayID: CGDirectDisplayID = 0
        let cgPoint = CGPoint(x: cgMouseX, y: cgMouseY)
        CGGetDisplaysWithPoint(cgPoint, 1, &displayID, &displayCount)
        
        guard displayCount > 0 else { return }
        
        // 4. Calculate capture rect in CG coordinates
        var captureRect: CGRect
        let targetGridSize = 5 // Fixed 5x5 for color picker
        
        if isColorPickerMode {
            // Over-capture to guarantee >= 5 device pixels in every case
            // We capture 8 points (which is >=5 pixels even on 1x screens)
            let capturePoints: CGFloat = 8.0
            let halfCapture = capturePoints / 2
            
            captureRect = CGRect(
                x: cgMouseX - halfCapture,
                y: cgMouseY - halfCapture,
                width: capturePoints,
                height: capturePoints
            )
        } else {
            // Classic Smooth Zoom
            let scaleFactor = cursorScreen?.backingScaleFactor ?? 2.0
            let displaySize = 200.0 / magnificationLevel / scaleFactor
            captureRect = CGRect(
                x: cgMouseX - displaySize / 2,
                y: cgMouseY - displaySize / 2,
                width: displaySize,
                height: displaySize
            )
        }
        
        // 5. Capture the screen region
        guard let screenImage = CGDisplayCreateImage(displayID, rect: captureRect) else { return }
        
        // 6. Feed to Loupe
        if isColorPickerMode {
            // Use fixed-grid method — always exactly 5x5 cells
            loupe.updateContent(image: screenImage, gridSize: targetGridSize)
        } else {
            let fullRect = CGRect(x: 0, y: 0, width: screenImage.width, height: screenImage.height)
            loupe.updateContent(image: screenImage, from: fullRect)
        }
    }
    
    // MARK: - Color Picker Toggle
    
    @objc func toggleColorPicker(_ sender: Any?) {
        isColorPickerMode.toggle()
        if isColorPickerMode {
            // Mutual exclusion: color picker replaces standalone magnifier
            // But we need the loupe to show pixels — auto-enable it
            if !isLoupeActive {
                // Enable loupe silently (as visual aid for color picker)
                loupeWindow = LoupeWindow()
                loupeWindow?.level = .screenSaver
                loupeWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                loupeWindow?.orderFront(nil)
                
                let timer = Timer(timeInterval: 0.016, target: self, selector: #selector(updateLoupeState), userInfo: nil, repeats: true)
                RunLoop.main.add(timer, forMode: .common)
                loupeTimer = timer
            }
            
            // Suppress Ruler Tooltip
            rulerOverlay?.showsMeasurementTooltip = false
            
            NSCursor.crosshair.set()
            overlayView?.window?.invalidateCursorRects(for: overlayView)
            
            let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(updateColorPickerState), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            colorPickerTimer = timer
            
            // Phase 31: Global click monitor for auto-copy color
            installColorPickerClickMonitor()
            
        } else {
             // Revert cursor
             overlayView?.window?.invalidateCursorRects(for: overlayView)
             
             // Restore Ruler Tooltip
             rulerOverlay?.showsMeasurementTooltip = true
             
             // Stop HUD Timer
             colorPickerTimer?.invalidate()
             colorPickerTimer = nil
             colorPickerBitmapRep = nil
             
             // Clean up floating HUD window
             colorPickerHUDWindow?.orderOut(nil)
             colorPickerHUDWindow = nil
             
             // Auto-disable loupe (it was enabled as part of color picker)
             if isLoupeActive {
                 loupeTimer?.invalidate()
                 loupeTimer = nil
                 loupeWindow?.orderOut(nil)
                 loupeWindow = nil
             }
             
             // Remove global click monitor
             removeColorPickerClickMonitor()
        }
    }
    
    // MARK: - Color Picker State Update (Screen-Wide, Phase 30)
    
    @objc func updateColorPickerState() {
        // Throttle to prevent CPU spikes
        let now = Date()
        guard now.timeIntervalSince(lastColorSampleTime) > 0.05 else { return }
        lastColorSampleTime = now
        
        // 1. Get Mouse Location (screen coordinates)
        let mouseLoc = NSEvent.mouseLocation
        
        // 2. Determine which display
        let cursorScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
        let screenHeight = cursorScreen?.frame.height ?? (NSScreen.main?.frame.height ?? 900)
        let screenOriginY = cursorScreen?.frame.origin.y ?? 0
        
        // Convert to CG coordinates
        let cgPoint = CGPoint(x: mouseLoc.x, y: (screenOriginY + screenHeight) - mouseLoc.y)
        
        var displayCount: UInt32 = 0
        var displayID: CGDirectDisplayID = 0
        CGGetDisplaysWithPoint(cgPoint, 1, &displayID, &displayCount)
        
        guard displayCount > 0 else {
            colorPickerHUDWindow?.orderOut(nil)
            return
        }
        
        // 3. Capture small region around cursor (3x3 pixels)
        let sampleSize: CGFloat = 3
        let sampleRect = CGRect(
            x: cgPoint.x - sampleSize / 2,
            y: cgPoint.y - sampleSize / 2,
            width: sampleSize,
            height: sampleSize
        )
        
        guard let screenImage = CGDisplayCreateImage(displayID, rect: sampleRect) else {
            colorPickerHUDWindow?.orderOut(nil)
            return
        }
        
        // 4. Sample center pixel
        let rep = NSBitmapImageRep(cgImage: screenImage)
        let centerX = rep.pixelsWide / 2
        let centerY = rep.pixelsHigh / 2
        
        guard let color = rep.colorAt(x: centerX, y: centerY),
              let rgb = color.usingColorSpace(.sRGB) else {
            colorPickerHUDWindow?.orderOut(nil)
            return
        }
        
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let hexString = String(format: "#%02X%02X%02X", r, g, b)
        
        // 5. Build info string
        let lm = LanguageManager.shared
        var infoText = "\(lm.string("label_hex"))  \(hexString)\n"
        infoText += "\(lm.string("label_rgb"))  \(r), \(g), \(b)\n"
        let (h, s, l) = rgbToHSL(r: r, g: g, b: b)
        infoText += "\(lm.string("label_hsl")) \(h), \(s), \(l)"
        
        // 6. Create or update floating HUD window (attached to loupe)
        if colorPickerHUDWindow == nil {
            let hudPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 180, height: 60),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            hudPanel.isOpaque = false
            hudPanel.backgroundColor = .clear
            hudPanel.level = .screenSaver  // Same z-level as Loupe
            hudPanel.hasShadow = true
            hudPanel.ignoresMouseEvents = true
            hudPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            
            let hud = NSTextField(labelWithString: "")
            hud.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            hud.textColor = .white
            hud.backgroundColor = NSColor.black.withAlphaComponent(0.85)
            hud.drawsBackground = true
            hud.alignment = .left
            hud.wantsLayer = true
            hud.layer?.cornerRadius = 6
            hud.layer?.masksToBounds = true
            hud.tag = 999
            
            hudPanel.contentView = hud
            colorPickerHUDWindow = hudPanel
        }
        
        guard let hudWindow = colorPickerHUDWindow,
              let hud = hudWindow.contentView as? NSTextField else { return }
        
        hud.stringValue = infoText
        
        // 7. Size and position the HUD — attached to the loupe window
        let hudSize = hud.sizeThatFits(NSSize(width: 220, height: 100))
        let paddedWidth = hudSize.width + 16
        let paddedHeight = hudSize.height + 10
        
        // Anchor HUD to the loupe window frame
        let gap: CGFloat = 4  // Small gap between loupe and HUD
        
        if let loupeFrame = loupeWindow?.frame {
            var hudX: CGFloat
            let hudY = loupeFrame.midY - paddedHeight / 2  // Vertically centered on loupe
            
            // Dynamic positioning: check which half of the screen the cursor is on
            let screen = cursorScreen ?? NSScreen.main
            let screenMidX = screen?.frame.midX ?? (NSScreen.main?.frame.midX ?? 960)
            
            if mouseLoc.x > screenMidX {
                // Cursor is on right side of screen → show HUD on LEFT of loupe
                hudX = loupeFrame.minX - paddedWidth - gap
            } else {
                // Cursor is on left side of screen → show HUD on RIGHT of loupe
                hudX = loupeFrame.maxX + gap
            }
            
            // Final screen-edge clamping
            if let sf = screen?.visibleFrame {
                if hudX + paddedWidth > sf.maxX {
                    hudX = loupeFrame.minX - paddedWidth - gap
                }
                if hudX < sf.minX {
                    hudX = sf.minX + 4
                }
            }
            
            hudWindow.setFrame(NSRect(x: hudX, y: hudY, width: paddedWidth, height: paddedHeight), display: true)
        } else {
            // Fallback: position near cursor if loupe is somehow missing
            hudWindow.setFrame(NSRect(x: mouseLoc.x + 20, y: mouseLoc.y - paddedHeight - 20, width: paddedWidth, height: paddedHeight), display: true)
        }
        
        hudWindow.orderFront(nil)
    }
    
    // MARK: - Pick Color on Click (Screen-Wide, Phase 30)
    
    func pickColor(at viewPoint: CGPoint) {
        // Get screen-level mouse coordinates
        let mouseLoc = NSEvent.mouseLocation
        
        // Determine display
        let cursorScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
        let screenHeight = cursorScreen?.frame.height ?? (NSScreen.main?.frame.height ?? 900)
        let screenOriginY = cursorScreen?.frame.origin.y ?? 0
        
        let cgPoint = CGPoint(x: mouseLoc.x, y: (screenOriginY + screenHeight) - mouseLoc.y)
        
        var displayCount: UInt32 = 0
        var displayID: CGDirectDisplayID = 0
        CGGetDisplaysWithPoint(cgPoint, 1, &displayID, &displayCount)
        
        guard displayCount > 0 else { return }
        
        // Capture a small region (3x3) for precise pixel sampling
        let sampleRect = CGRect(x: cgPoint.x - 1, y: cgPoint.y - 1, width: 3, height: 3)
        guard let screenImage = CGDisplayCreateImage(displayID, rect: sampleRect) else { return }
        
        let rep = NSBitmapImageRep(cgImage: screenImage)
        let centerX = rep.pixelsWide / 2
        let centerY = rep.pixelsHigh / 2
        
        guard let color = rep.colorAt(x: centerX, y: centerY),
              let rgb = color.usingColorSpace(.sRGB) else { return }
        
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        
        let (h, s, l) = rgbToHSL(r: r, g: g, b: b)
        
        let lm = LanguageManager.shared
        let copyText = """
        \(lm.string("label_hex"))  \(hex)
        \(lm.string("label_rgb"))  \(r), \(g), \(b)
        \(lm.string("label_hsl")) \(h), \(s), \(l)
        
        """
        
        // Instant copy to clipboard (first for speed)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
        
        // Async sound feedback (non-blocking)
        DispatchQueue.global(qos: .utility).async {
            NSSound(named: "Tink")?.play()
        }
        
        // Floating Toast Feedback (lightweight)
        let adjustedPoint = CGPoint(x: mouseLoc.x + 30, y: mouseLoc.y - 30)
        showFloatingToast(message: lm.string("msg_copied"), at: adjustedPoint)
    }
    
    // MARK: - Toast
    
    func showFloatingToast(message: String, at screenPoint: CGPoint) {
        // Cleanup previous if exists
        self.activeToastWindow?.close()
        self.activeToastWindow = nil
        
        let toastWindow = NSPanel(contentRect: NSRect(x: screenPoint.x, y: screenPoint.y, width: 200, height: 40),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        toastWindow.level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)  // Above everything including fullscreen
        toastWindow.backgroundColor = .clear
        toastWindow.isOpaque = false
        toastWindow.ignoresMouseEvents = true
        toastWindow.isReleasedWhenClosed = false
        toastWindow.hidesOnDeactivate = false  // Stay visible even when app is not active
        toastWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        toastWindow.contentView = contentView
        
        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 8
        visualEffect.layer?.masksToBounds = true
        visualEffect.autoresizingMask = [.width, .height]
        
        contentView.addSubview(visualEffect)
        
        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = visualEffect.bounds
        label.autoresizingMask = [.width, .height]
        
        visualEffect.addSubview(label)
        
        // Sizing
        let size = label.sizeThatFits(NSSize(width: 200, height: 30))
        let width = max(80, size.width + 20)
        let height = max(30, size.height + 10)
        toastWindow.setFrame(NSRect(x: screenPoint.x, y: screenPoint.y, width: width, height: height), display: true)
        
        // Retain
        self.activeToastWindow = toastWindow
        toastWindow.orderFront(nil)
        
        // Animate & Close
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 2.0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toastWindow.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            toastWindow.close()
            if self?.activeToastWindow == toastWindow {
                self?.activeToastWindow = nil
            }
        })
    }
    
    // MARK: - Utility
    
    func rgbToHSL(r: Int, g: Int, b: Int) -> (Int, Int, Int) {
        let rNorm = CGFloat(r) / 255.0
        let gNorm = CGFloat(g) / 255.0
        let bNorm = CGFloat(b) / 255.0
        
        let minVal = min(rNorm, gNorm, bNorm)
        let maxVal = max(rNorm, gNorm, bNorm)
        let delta = maxVal - minVal
        
        var h: CGFloat = 0
        var s: CGFloat = 0
        let l: CGFloat = (maxVal + minVal) / 2.0
        
        if delta == 0 {
            h = 0
            s = 0
        } else {
            s = l > 0.5 ? delta / (2.0 - maxVal - minVal) : delta / (maxVal + minVal)
            
            if maxVal == rNorm {
                h = (gNorm - bNorm) / delta + (gNorm < bNorm ? 6.0 : 0.0)
            } else if maxVal == gNorm {
                h = (bNorm - rNorm) / delta + 2.0
            } else {
                h = (rNorm - gNorm) / delta + 4.0
            }
            h /= 6.0
        }
        return (Int(h * 360), Int(s * 100), Int(l * 100))
    }
    
    // MARK: - Global Click Monitor (Phase 31)
    
    func installColorPickerClickMonitor() {
        removeColorPickerClickMonitor() // Ensure no duplicates
        
        // Global monitor: left clicks OUTSIDE the app's windows
        colorPickerClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isColorPickerMode else { return }
            
            if event.type == .rightMouseDown {
                // Right-click anywhere outside the app deactivates color picker
                DispatchQueue.main.async {
                    self.toggleColorPicker(nil)
                }
                return
            }
            
            self.pickColor(at: .zero)
        }
        
        // Local monitor: clicks INSIDE the app's windows
        colorPickerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isColorPickerMode else { return event }
            
            // Right-click deactivates color picker
            if event.type == .rightMouseDown {
                self.toggleColorPicker(nil)
                return event
            }
            
            // Allow clicks on menu bar and status items to pass through
            if let window = event.window {
                let windowClassName = String(describing: type(of: window))
                if windowClassName.contains("Menu") || windowClassName.contains("StatusBar") || windowClassName.contains("PopUp") {
                    return event
                }
            }
            
            // Check if click is on the menu bar area (top 25 pixels of screen)
            let screenPoint = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) }) {
                let menuBarHeight: CGFloat = 25
                if screenPoint.y > (screen.frame.maxY - menuBarHeight) {
                    return event
                }
            }
            
            // Color pick on left click
            self.pickColor(at: .zero)
            return nil
        }
    }
    
    func removeColorPickerClickMonitor() {
        if let monitor = colorPickerClickMonitor {
            NSEvent.removeMonitor(monitor)
            colorPickerClickMonitor = nil
        }
        if let monitor = colorPickerLocalMonitor {
            NSEvent.removeMonitor(monitor)
            colorPickerLocalMonitor = nil
        }
    }
    
    // MARK: - Standalone Magnifier Right-Click Deactivation
    
    func installLoupeRightClickMonitor() {
        removeLoupeRightClickMonitor()
        
        // Combined global + local right-click monitor to deactivate magnifier
        loupeRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self, self.isLoupeActive, !self.isColorPickerMode else { return event }
            self.toggleLoupe(nil)
            return event
        }
        
        // Also install global monitor for right-clicks outside app windows
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self, self.isLoupeActive, !self.isColorPickerMode else { return }
            DispatchQueue.main.async {
                self.toggleLoupe(nil)
            }
        }
        // Store as array for cleanup
        if loupeRightClickMonitor != nil {
            loupeRightClickMonitor = [loupeRightClickMonitor!, globalMonitor as Any]
        }
    }
    
    func removeLoupeRightClickMonitor() {
        if let monitors = loupeRightClickMonitor as? [Any] {
            for monitor in monitors {
                NSEvent.removeMonitor(monitor)
            }
        } else if let monitor = loupeRightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        loupeRightClickMonitor = nil
    }
}
