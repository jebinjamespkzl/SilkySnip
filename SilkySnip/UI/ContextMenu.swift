//
//  ContextMenu.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa

class ContextMenuBuilder {
    
    // MARK: - Tool Sync Helper
    
    /// Syncs the annotation tool (Pen/Highlighter/Eraser) to ALL overlay windows
    /// This allows users to draw on any screenshot without re-selecting the tool
    private static func syncToolToAllOverlays(_ tool: ToolType?) {
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        for overlay in overlayWindows {
            overlay.currentTool = tool
        }
        Logger.shared.info("Tool \(tool?.rawValue ?? "none") synced to \(overlayWindows.count) overlays")
    }
    
    // MARK: - Main Menu (Status Bar) Items
    
    /// Builds tools for the main menu bar — flat layout matching the right-click context menu.
    /// Each tool has its own submenu for options (colors, sizes, etc.).
    static func buildMainMenuItems(for overlay: OverlayWindow, into menu: NSMenu) {
        let lm = LanguageManager.shared
        let settings = ContextMenuSettings.shared
        
        // Pen (with color/size submenu)
        let penItem = NSMenuItem(title: lm.string("tool_pen"), action: nil, keyEquivalent: Constants.Shortcut.pen.key)
        penItem.keyEquivalentModifierMask = Constants.Shortcut.pen.modifiers
        penItem.submenu = buildPenSubmenu(for: overlay)
        if overlay.currentTool == .pen { penItem.state = .on }
        penItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pen")
        menu.addItem(penItem)
        
        // Highlighter (with color/size submenu)
        let highlighterItem = NSMenuItem(title: lm.string("tool_highlighter"), action: nil, keyEquivalent: Constants.Shortcut.highlighter.key)
        highlighterItem.keyEquivalentModifierMask = Constants.Shortcut.highlighter.modifiers
        highlighterItem.submenu = buildHighlighterSubmenu(for: overlay)
        if overlay.currentTool == .highlighter { highlighterItem.state = .on }
        highlighterItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Highlighter")
        menu.addItem(highlighterItem)
        
        // Eraser
        let eraserItem = NSMenuItem(title: lm.string("tool_eraser"), action: #selector(calculateEraserAction(_:)), keyEquivalent: Constants.Shortcut.eraser.key)
        eraserItem.keyEquivalentModifierMask = Constants.Shortcut.eraser.modifiers
        eraserItem.representedObject = overlay
        eraserItem.target = ContextMenuBuilder.self
        if overlay.currentTool == .eraser { eraserItem.state = .on }
        eraserItem.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: "Eraser")
        menu.addItem(eraserItem)
        
        // Text (with options submenu)
        let textItem = NSMenuItem(title: lm.string("tool_text"), action: nil, keyEquivalent: Constants.Shortcut.text.key)
        textItem.keyEquivalentModifierMask = Constants.Shortcut.text.modifiers
        textItem.submenu = buildTextSubmenu(for: overlay)
        if overlay.currentTool == .text { textItem.state = .on }
        textItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text")
        menu.addItem(textItem)
        
        // Blur (with options submenu)
        let blurItem = NSMenuItem(title: lm.string("tool_blur"), action: nil, keyEquivalent: Constants.Shortcut.blur.key)
        blurItem.keyEquivalentModifierMask = Constants.Shortcut.blur.modifiers
        blurItem.submenu = buildBlurSubmenu(for: overlay)
        if overlay.currentTool == .blur { blurItem.state = .on }
        blurItem.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Blur")
        menu.addItem(blurItem)
    }
    
    // MARK: - Build Menu
    
    static func buildMenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        let settings = ContextMenuSettings.shared
        
        // MARK: - Tools Section
        
        // Pen
        let penItem = NSMenuItem(title: lm.string("tool_pen"), action: nil, keyEquivalent: Constants.Shortcut.pen.key)
        penItem.keyEquivalentModifierMask = Constants.Shortcut.pen.modifiers
        penItem.submenu = buildPenSubmenu(for: overlay)
        if overlay.currentTool == .pen { penItem.state = .on }
        penItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pen")
        menu.addItem(penItem)
        
        // Highlighter
        let highlighterItem = NSMenuItem(title: lm.string("tool_highlighter"), action: nil, keyEquivalent: Constants.Shortcut.highlighter.key)
        highlighterItem.keyEquivalentModifierMask = Constants.Shortcut.highlighter.modifiers
        highlighterItem.submenu = buildHighlighterSubmenu(for: overlay)
        if overlay.currentTool == .highlighter { highlighterItem.state = .on }
        highlighterItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Highlighter")
        menu.addItem(highlighterItem)
        
        // Eraser
        // Eraser (Simplified - Single Action)
        let eraserItem = NSMenuItem(title: lm.string("tool_eraser"), action: #selector(calculateEraserAction(_:)), keyEquivalent: Constants.Shortcut.eraser.key)
        eraserItem.keyEquivalentModifierMask = Constants.Shortcut.eraser.modifiers
        eraserItem.representedObject = overlay
        eraserItem.target = ContextMenuBuilder.self
        if overlay.currentTool == .eraser { eraserItem.state = .on }
        eraserItem.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: "Eraser")
        menu.addItem(eraserItem)
        
        // Text
        let textItem = NSMenuItem(title: lm.string("tool_text"), action: nil, keyEquivalent: Constants.Shortcut.text.key)
        textItem.keyEquivalentModifierMask = Constants.Shortcut.text.modifiers
        textItem.submenu = buildTextSubmenu(for: overlay)
        if overlay.currentTool == .text { textItem.state = .on }
        textItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text")
        menu.addItem(textItem)
        
        // Select Text (OCR) - Moved to Tools section

        // Select Text (OCR) - Moved here as requested
        let selectTextItem = NSMenuItem(title: lm.string("menu.ocr"), action: #selector(selectText(_:)), keyEquivalent: "t")
        selectTextItem.keyEquivalentModifierMask = [.control, .shift]
        selectTextItem.representedObject = overlay
        selectTextItem.target = ContextMenuBuilder.self
        selectTextItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "OCR")
        menu.addItem(selectTextItem)

        // Blur
        let blurItem = NSMenuItem(title: lm.string("tool_blur"), action: nil, keyEquivalent: Constants.Shortcut.blur.key)
        blurItem.keyEquivalentModifierMask = Constants.Shortcut.blur.modifiers
        blurItem.submenu = buildBlurSubmenu(for: overlay)
        if overlay.currentTool == .blur { blurItem.state = .on }
        blurItem.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Blur")
        menu.addItem(blurItem)
        
        // Speech Bubble (Advanced - toggleable in Settings)
        // Sticky Note - REMOVED (Moved to Floating Window via Advanced Tools)

        
        // Crop
        let cropItem = NSMenuItem(title: lm.string("tool_crop"), action: #selector(cropScreenshot(_:)), keyEquivalent: Constants.Shortcut.crop.key)
        cropItem.keyEquivalentModifierMask = Constants.Shortcut.crop.modifiers
        cropItem.representedObject = overlay
        cropItem.target = ContextMenuBuilder.self
        cropItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Crop")
        menu.addItem(cropItem)

        // Move Mode
        let noneItem = NSMenuItem(title: lm.string("tool_move"), action: #selector(selectNoTool(_:)), keyEquivalent: Constants.Shortcut.move.key)
        noneItem.keyEquivalentModifierMask = Constants.Shortcut.move.modifiers
        noneItem.representedObject = overlay
        noneItem.target = ContextMenuBuilder.self
        
        // Fix: Ensure Move Mode is NOT checked if other tools are active
        let toolsActive = overlay.isColorPickerMode || overlay.isLoupeActive || overlay.currentTool != nil
        noneItem.state = (!toolsActive) ? .on : .off
        
        noneItem.image = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Move")
        menu.addItem(noneItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // MARK: - View Section
        
        // Zoom submenu
        let zoomSubmenu = buildZoomSubmenu(for: overlay)
        // Zoom (Moved here as per standard)
        let zoomItem = NSMenuItem(title: lm.string("menu.zoom"), action: nil, keyEquivalent: "")
        zoomItem.submenu = zoomSubmenu
        // Phase 27: Show tickmark if Zoom is NOT 100% (1.0)
        zoomItem.state = abs(overlay.metadata.zoom - 1.0) > 0.01 ? .on : .off
        zoomItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Zoom")
        menu.addItem(zoomItem)
        
        // Opacity submenu
        let opacityItem = NSMenuItem(title: lm.string("menu.opacity"), action: nil, keyEquivalent: "")
        opacityItem.submenu = buildOpacitySubmenu(for: overlay)
        opacityItem.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Opacity")
        menu.addItem(opacityItem)
        
        // Lock Screenshot (Ctrl+L)
        let lockTitle = overlay.isLocked ? lm.string("menu.unlock.screenshot") : lm.string("menu.lock.screenshot")
        let lockScreenshotItem = NSMenuItem(title: lockTitle, action: #selector(toggleLockScreenshot(_:)), keyEquivalent: "l")
        lockScreenshotItem.keyEquivalentModifierMask = .control
        lockScreenshotItem.representedObject = overlay
        lockScreenshotItem.target = ContextMenuBuilder.self
        lockScreenshotItem.state = overlay.isLocked ? .on : .off
        lockScreenshotItem.image = NSImage(systemSymbolName: overlay.isLocked ? "lock.open" : "lock", accessibilityDescription: "Lock")
        menu.addItem(lockScreenshotItem)
        
        // Lock to Display
        let lockDisplayItem = NSMenuItem(title: lm.string("menu.lock.display"), action: #selector(toggleLockToDisplay(_:)), keyEquivalent: Constants.Shortcut.lockDisplay.key)
        lockDisplayItem.keyEquivalentModifierMask = Constants.Shortcut.lockDisplay.modifiers
        lockDisplayItem.representedObject = overlay
        lockDisplayItem.target = ContextMenuBuilder.self
        lockDisplayItem.state = overlay.lockToDisplay ? .on : .off
        lockDisplayItem.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Lock to Display")
        menu.addItem(lockDisplayItem)
        
        // Filters submenu removed per user request (Grayscale is available separately)
        
        // Flip submenu (Disabled Phase 28)
//        let flipItem = NSMenuItem(title: lm.string("menu.flip"), action: nil, keyEquivalent: "")
//        flipItem.submenu = buildFlipSubmenu(for: overlay)
//        flipItem.image = NSImage(systemSymbolName: "arrow.left.and.right.righttriangle.left.righttriangle.right", accessibilityDescription: "Flip")
//        menu.addItem(flipItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // MARK: - Advanced Tools Section (Flattened)
        
        // Color Picker
        if settings.showColorPicker {
            let colorPickerItem = NSMenuItem(title: lm.string("menu.pick.color"), action: #selector(toggleColorPicker(_:)), keyEquivalent: Constants.Shortcut.colorPicker.key)
            colorPickerItem.keyEquivalentModifierMask = Constants.Shortcut.colorPicker.modifiers
            colorPickerItem.representedObject = overlay
            colorPickerItem.target = ContextMenuBuilder.self
            colorPickerItem.state = overlay.isColorPickerMode ? .on : .off
            colorPickerItem.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Color Picker")
            colorPickerItem.toolTip = LanguageManager.shared.string("tooltip_right_click_disable")
            menu.addItem(colorPickerItem)
        }
        
        // Magnifier
        if settings.showMagnify {
            let magnifyItem = NSMenuItem(title: lm.string("tool_magnify"), action: #selector(toggleLoupe(_:)), keyEquivalent: "m")
            magnifyItem.keyEquivalentModifierMask = .control
            magnifyItem.representedObject = overlay
            magnifyItem.target = ContextMenuBuilder.self
            magnifyItem.state = overlay.isLoupeActive ? .on : .off
            magnifyItem.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Magnify")
            magnifyItem.toolTip = LanguageManager.shared.string("tooltip_right_click_disable")
            
            let magMenu = NSMenu()
            let levels: [CGFloat] = [3.0, 5.0, 10.0]
            for level in levels {
                let item = NSMenuItem(title: "\(Int(level))x", action: #selector(OverlayWindow.setMagnification(_:)), keyEquivalent: "")
                item.target = overlay
                item.representedObject = level
                // Show checkmark ONLY if Loupe is Active AND this is the current level
                item.state = (overlay.isLoupeActive && overlay.magnificationLevel == level) ? .on : .off
                magMenu.addItem(item)
            }
            magnifyItem.submenu = magMenu
            
            menu.addItem(magnifyItem)
        }
        
        // Ruler
        if settings.showRulers {
            let rulerItem = NSMenuItem(title: lm.string("menu.show.rulers"), action: #selector(toggleRuler(_:)), keyEquivalent: Constants.Shortcut.ruler.key)
            rulerItem.keyEquivalentModifierMask = Constants.Shortcut.ruler.modifiers
            rulerItem.target = ContextMenuBuilder.self
            rulerItem.representedObject = overlay
            rulerItem.state = overlay.isRulerActive ? .on : .off
            rulerItem.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Rulers")
            menu.addItem(rulerItem)
        }
        
        // Grayscale
        if settings.showFilters {
            let grayscaleItem = NSMenuItem(title: lm.string("menu.grayscale"), action: #selector(toggleGrayscale(_:)), keyEquivalent: Constants.Shortcut.grayscale.key)
            grayscaleItem.keyEquivalentModifierMask = Constants.Shortcut.grayscale.modifiers
            grayscaleItem.representedObject = overlay
            grayscaleItem.target = ContextMenuBuilder.self
            grayscaleItem.state = overlay.isGrayscale ? .on : .off
            grayscaleItem.image = NSImage(systemSymbolName: "camera.filters", accessibilityDescription: "Grayscale")
            menu.addItem(grayscaleItem)
        }

        // Ghost Mode
        if settings.showGhostMode {
            let ghostItem = NSMenuItem(title: lm.string("menu.ghost.mode"), action: #selector(toggleGhostMode(_:)), keyEquivalent: Constants.Shortcut.ghostMode.key)
            ghostItem.keyEquivalentModifierMask = Constants.Shortcut.ghostMode.modifiers
            ghostItem.representedObject = overlay
            ghostItem.target = ContextMenuBuilder.self
            ghostItem.state = overlay.isGhostMode ? .on : .off
            ghostItem.image = NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "Ghost Mode")
            menu.addItem(ghostItem)
        }

        // Smart Pinning
        if SmartRestoreManager.shared.isEnabled {
            let pinItem = NSMenuItem(title: LanguageManager.shared.string("menu.pin.to.app"), action: nil, keyEquivalent: "")
            pinItem.submenu = buildPinSubmenu(for: overlay)
            pinItem.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin to App")
            pinItem.state = SmartRestoreManager.shared.isPinned(overlay.metadata.id) ? .on : .off
            menu.addItem(pinItem)
        }

        menu.addItem(NSMenuItem.separator())
        
        // MARK: - Actions Section
        
        // New - Removed from Context Menu

        // Save
        let saveItem = NSMenuItem(title: lm.string("save"), action: #selector(saveScreenshot(_:)), keyEquivalent: Constants.Shortcut.saveCurrent.key)
        saveItem.keyEquivalentModifierMask = Constants.Shortcut.saveCurrent.modifiers
        saveItem.representedObject = overlay
        saveItem.target = ContextMenuBuilder.self
        saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        menu.addItem(saveItem)
        
        // Copy
        let copyItem = NSMenuItem(title: lm.string("menu.copy.image"), action: #selector(copyImage(_:)), keyEquivalent: Constants.Shortcut.copyImage.key)
        copyItem.keyEquivalentModifierMask = Constants.Shortcut.copyImage.modifiers
        copyItem.representedObject = overlay
        copyItem.target = ContextMenuBuilder.self
        copyItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy")
        menu.addItem(copyItem)
        
        // Share
        let shareItem = NSMenuItem(title: lm.string("menu.share"), action: #selector(shareScreenshot(_:)), keyEquivalent: "")
        shareItem.representedObject = overlay
        shareItem.target = ContextMenuBuilder.self
        shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        menu.addItem(shareItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Restore - Removed from Context Menu
        
        // Clear Cached - Removed from Context Menu
        
        menu.addItem(NSMenuItem.separator())
        
        // Hide
        let hideItem = NSMenuItem(title: lm.string("menu.hide"), action: #selector(hideScreenshot(_:)), keyEquivalent: Constants.Shortcut.hideCurrent.key)
        hideItem.keyEquivalentModifierMask = Constants.Shortcut.hideCurrent.modifiers
        hideItem.representedObject = overlay
        hideItem.target = ContextMenuBuilder.self
        hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide")
        menu.addItem(hideItem)
        
        // Close
        let closeItem = NSMenuItem(title: lm.string("menu.close"), action: #selector(closeScreenshot(_:)), keyEquivalent: Constants.Shortcut.closeCurrent.key)
        closeItem.keyEquivalentModifierMask = Constants.Shortcut.closeCurrent.modifiers
        closeItem.representedObject = overlay
        closeItem.target = ContextMenuBuilder.self
        closeItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        menu.addItem(closeItem)
        
        // Close All - Removed from Context Menu
        
        return menu
    }
    
    // MARK: - Tools Submenu
    
    private static func buildToolsSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // Pen submenu with options
        let penItem = NSMenuItem(title: lm.string("tool_pen"), action: nil, keyEquivalent: "")
        penItem.submenu = buildPenSubmenu(for: overlay)
        if overlay.currentTool == .pen { penItem.state = .on }
        menu.addItem(penItem)
        
        // Highlighter submenu with options
        let highlighterItem = NSMenuItem(title: lm.string("tool_highlighter"), action: nil, keyEquivalent: "")
        highlighterItem.submenu = buildHighlighterSubmenu(for: overlay)
        if overlay.currentTool == .highlighter { highlighterItem.state = .on }
        menu.addItem(highlighterItem)
        
        // Eraser submenu with options
        let eraserItem = NSMenuItem(title: lm.string("tool_eraser"), action: nil, keyEquivalent: "")
        eraserItem.submenu = buildEraserSubmenu(for: overlay)
        if overlay.currentTool == .eraser { eraserItem.state = .on }
        menu.addItem(eraserItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let noneItem = NSMenuItem(title: lm.string("tool_move"), action: #selector(selectNoTool(_:)), keyEquivalent: "m")
        noneItem.representedObject = overlay
        noneItem.target = ContextMenuBuilder.self
        noneItem.state = overlay.currentTool == nil ? .on : .off
        menu.addItem(noneItem)
        
        return menu
    }
    
    // MARK: - Pen Submenu
    
    static func buildPenSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // Pen colors directly

        
        menu.addItem(NSMenuItem.separator())
        
        // Colors
        let colors: [(String, String)] = [
            (lm.string("color_black"), Theme.Colors.black),
            (lm.string("color_white"), Theme.Colors.white),
            (lm.string("color_red"), Theme.Colors.red),
            (lm.string("color_blue"), Theme.Colors.blue),
            (lm.string("color_green"), Theme.Colors.green),
            (lm.string("color_orange"), Theme.Colors.orange)
        ]
        
        let currentPenHex = ToolManager.shared.penColor.hexString.uppercased()
        for (name, hex) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(setPenColor(_:)), keyEquivalent: "")
            colorItem.representedObject = (overlay, hex)
            colorItem.target = ContextMenuBuilder.self
            // Checkmark only if Pen is active AND color matches
            let isPenActive = overlay.currentTool == .pen
            colorItem.state = (isPenActive && currentPenHex == hex.uppercased()) ? .on : .off
            menu.addItem(colorItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Sizes
        let sizes = [lm.string("size_thin"), lm.string("size_medium"), lm.string("size_thick")]
        let currentPenSize = ToolManager.shared.penSize
        for (index, size) in sizes.enumerated() {
            let sizeItem = NSMenuItem(title: size, action: #selector(setPenSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = (overlay, index)
            sizeItem.target = ContextMenuBuilder.self
            // Checkmark only if Pen is active AND size matches
            let isPenActive = overlay.currentTool == .pen
            sizeItem.state = (isPenActive && currentPenSize == Constants.penSizes[index]) ? .on : .off
            menu.addItem(sizeItem)
        }
        
        return menu
    }
    
    // MARK: - Highlighter Submenu
    
    static func buildHighlighterSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // Highlighter colors directly

        
        menu.addItem(NSMenuItem.separator())
        
        // Colors
        let colors: [(String, String)] = [
            (lm.string("color_yellow"), Theme.Colors.yellow),
            (lm.string("color_green"), Theme.Colors.green),
            (lm.string("color_pink"), Theme.Colors.pink),
            (lm.string("color_cyan"), Theme.Colors.cyan),
            (lm.string("color_orange"), Theme.Colors.orange)
        ]
        
        let currentHighlighterHex = ToolManager.shared.highlighterColor.hexString.uppercased()
        for (name, hex) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(setHighlighterColor(_:)), keyEquivalent: "")
            colorItem.representedObject = (overlay, hex)
            colorItem.target = ContextMenuBuilder.self
            // Checkmark only if Highlighter is active AND color matches
            let isHighlighterActive = overlay.currentTool == .highlighter
            colorItem.state = (isHighlighterActive && currentHighlighterHex == hex.uppercased()) ? .on : .off
            menu.addItem(colorItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Sizes (Small, Normal, Large) -> (0, 1, 2)
        let sizes = [lm.string("size_small"), lm.string("size_normal"), lm.string("size_large")]
        let currentHighlighterSize = ToolManager.shared.highlighterSize
        for (index, size) in sizes.enumerated() {
            let sizeItem = NSMenuItem(title: size, action: #selector(setHighlighterSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = (overlay, index)
            sizeItem.target = ContextMenuBuilder.self
            
            // Checkmark logic
            let isHighlighterActive = overlay.currentTool == .highlighter
            // Check against Constants.highlighterSizes
            let targetSize = Constants.highlighterSizes[index]
            sizeItem.state = (isHighlighterActive && abs(currentHighlighterSize - targetSize) < 0.1) ? .on : .off
            menu.addItem(sizeItem)
        }
        
        return menu
    }
    
    // MARK: - Eraser Submenu
    
    static func buildEraserSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // Eraser sizes directly

        
        menu.addItem(NSMenuItem.separator())
        
        // Sizes
        let sizes = [(lm.string("size_small"), 10), (lm.string("size_medium"), 20), (lm.string("size_large"), 40)]
        let currentEraserSize = Int(ToolManager.shared.eraserSize)
        for (name, size) in sizes {
            let sizeItem = NSMenuItem(title: name, action: #selector(setEraserSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = (overlay, size)
            sizeItem.target = ContextMenuBuilder.self
            // Checkmark only if Eraser is active AND size matches
            let isEraserActive = overlay.currentTool == .eraser
            sizeItem.state = (isEraserActive && currentEraserSize == size) ? .on : .off
            menu.addItem(sizeItem)
        }
        
        return menu
    }
    
    // MARK: - Blur Submenu
    
    static func buildBlurSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        
        let isBlurActive = overlay.currentTool == .blur
        
        // Blur strength percentages - 100% = maximum blur coverage
        let blurLevels: [(String, CGFloat, CGFloat)] = [
            // (label, blur intensity, opacity)
            ("25%", 8, 0.25),
            ("50%", 15, 0.5),
            ("75%", 22, 0.75),
            ("100%", 30, 1.0)
        ]
        let currentOpacity = ToolManager.shared.blurOpacity
        
        for (name, intensity, opacity) in blurLevels {
            let item = NSMenuItem(title: name, action: #selector(setBlurLevel(_:)), keyEquivalent: "")
            item.representedObject = (overlay, intensity, opacity)
            item.target = ContextMenuBuilder.self
            item.state = (isBlurActive && abs(currentOpacity - opacity) < 0.01) ? .on : .off
            menu.addItem(item)
        }
        
        return menu
    }
    
    // MARK: - Text Submenu
    
    static func buildTextSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        let isTextActive = overlay.currentTool == .text
        
        // Colors FIRST (like Pen) - selecting any color activates text tool
        let colors: [(String, String)] = [
            (lm.string("color_black"), Theme.Colors.black),
            (lm.string("color_white"), Theme.Colors.white),
            (lm.string("color_red"), Theme.Colors.red),
            (lm.string("color_blue"), Theme.Colors.blue),
            (lm.string("color_green"), Theme.Colors.green),
            (lm.string("color_orange"), Theme.Colors.orange)
        ]
        
        let currentTextHex = ToolManager.shared.textColor.hexString.uppercased()
        for (name, hex) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(setTextColor(_:)), keyEquivalent: "")
            colorItem.representedObject = (overlay, hex)
            colorItem.target = ContextMenuBuilder.self
            // Only show checkmark if text tool is active AND this color is selected
            colorItem.state = (isTextActive && currentTextHex == hex.uppercased()) ? .on : .off
            menu.addItem(colorItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Sizes SECOND (like Pen)
        let fontSizes: [(String, CGFloat)] = [
            (lm.string("size_small"), 11),
            (lm.string("size_normal"), 15),
            (lm.string("size_large"), 19)
        ]
        
        let currentTextSize = ToolManager.shared.textSize
        for (name, size) in fontSizes {
            let sizeItem = NSMenuItem(title: name, action: #selector(setTextSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = (overlay, size)
            sizeItem.target = ContextMenuBuilder.self
            // Only show checkmark if text tool is active AND this size is selected
            sizeItem.state = (isTextActive && currentTextSize == size) ? .on : .off
            menu.addItem(sizeItem)
        }
        
        return menu
    }
    
    @objc private static func setTextSize(_ sender: NSMenuItem) {
        guard let (_, size) = sender.representedObject as? (OverlayWindow, CGFloat) else { return }
        ToolManager.shared.textSize = size
        // Activate text tool when size is selected (same as Pen/Highlighter behavior)
        syncToolToAllOverlays(.text)
    }

    
    // MARK: - Pen Options Submenu
    
    private static func buildPenOptionsSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // Colors
        let colors: [(String, String)] = [
            (lm.string("color_black"), Theme.Colors.black),
            (lm.string("color_red"), Theme.Colors.red),
            (lm.string("color_blue"), Theme.Colors.blue),
            (lm.string("color_green"), Theme.Colors.green),
            (lm.string("color_orange"), Theme.Colors.orange),
            (lm.string("color_purple"), Theme.Colors.purple)
        ]
        
        for (name, hex) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(setPenColor(_:)), keyEquivalent: "")
            colorItem.representedObject = (overlay, hex)
            colorItem.target = ContextMenuBuilder.self
            menu.addItem(colorItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Sizes
        let sizes = [lm.string("size_thin"), lm.string("size_medium"), lm.string("size_thick")]
        for (index, size) in sizes.enumerated() {
            let sizeItem = NSMenuItem(title: size, action: #selector(setPenSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = (overlay, index)
            sizeItem.target = ContextMenuBuilder.self
            menu.addItem(sizeItem)
        }
        
        return menu
    }
    
    // MARK: - Highlighter Options Submenu
    
    private static func buildHighlighterOptionsSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // Colors
        let colors: [(String, String)] = [
            (lm.string("color_yellow"), Theme.Colors.yellow),
            (lm.string("color_green"), Theme.Colors.green),
            (lm.string("color_pink"), Theme.Colors.pink),
            (lm.string("color_cyan"), Theme.Colors.cyan),
            (lm.string("color_orange"), Theme.Colors.orange)
        ]
        
        for (name, hex) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(setHighlighterColor(_:)), keyEquivalent: "")
            colorItem.representedObject = (overlay, hex)
            colorItem.target = ContextMenuBuilder.self
            menu.addItem(colorItem)
        }
        
        return menu
    }
    
    // MARK: - Zoom Submenu
    
    private static func buildZoomSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        for zoom in Constants.zoomLevels {
            let title = zoom == 1.0 ? "100% (\(lm.string("zoom_actual_size")))" : "\(Int(zoom * 100))%"
            let zoomItem = NSMenuItem(title: title, action: #selector(setZoom(_:)), keyEquivalent: "")
            zoomItem.representedObject = (overlay, zoom)
            zoomItem.target = ContextMenuBuilder.self
            zoomItem.state = overlay.metadata.zoom == zoom ? .on : .off
            menu.addItem(zoomItem)
        }
        
        return menu
    }
    
    // MARK: - Actions
    
    @objc private static func saveScreenshot(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        ExportManager.shared.saveOverlay(overlay)
    }
    
    @objc private static func copyImage(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        ExportManager.shared.copyOverlayToClipboard(overlay)
        NSHapticFeedbackManager.defaultPerformer.perform(Constants.Haptics.success, performanceTime: .default)
        if UserDefaults.standard.object(forKey: "PlaySounds") as? Bool ?? true {
            NSSound(named: "Glass")?.play()
        }
        overlay.showCopiedFeedback()
        // Audit log the copy action
        AuditLogger.shared.logCopy(screenshotID: overlay.metadata.id)
    }
    
    
    
    @objc private static func selectText(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        let lm = LanguageManager.shared
        
        // Check MDM policy
        if !MDMManager.shared.isActionAllowed(.ocr) {
            let alert = NSAlert()
            alert.messageText = lm.string("alert_ocr_disabled_title")
            alert.informativeText = lm.string("alert_ocr_disabled")
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        
        // Deactivate crop/OCR on other overlays
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        for otherOverlay in overlayWindows where otherOverlay != overlay {
            otherOverlay.endCropMode()
            otherOverlay.hideTextSelection()
        }
        
        overlay.showTextSelection()
    }
    
    @objc private static func closeScreenshot(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        overlay.overlayDelegate?.overlayWindowDidRequestClose(overlay)
    }

    @objc private static func hideScreenshot(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        overlay.orderOut(nil)
        // Notify app delegate to update menu state if needed
        (NSApp.delegate as? AppDelegate)?.updateMenuStateForHiddenWindows()
    }
    
    @objc private static func cropScreenshot(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        
        // Deactivate crop/OCR on other overlays
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        for otherOverlay in overlayWindows where otherOverlay != overlay {
            otherOverlay.endCropMode()
            otherOverlay.hideTextSelection()
        }
        
        overlay.startCropMode()
    }
    
    @objc private static func selectPen(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        // Toggle: if already pen, deselect all
        if overlay.currentTool == .pen {
            syncToolToAllOverlays(nil)
        } else {
            syncToolToAllOverlays(.pen)
        }
    }
    
    @objc private static func selectBlur(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        if overlay.currentTool == .blur {
            syncToolToAllOverlays(nil)
        } else {
            syncToolToAllOverlays(.blur)
        }
    }
    
    @objc static func calculateEraserAction(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        if overlay.currentTool == .eraser {
            syncToolToAllOverlays(nil)
        } else {
            syncToolToAllOverlays(.eraser)
        }
    }

    @objc private static func setBlurLevel(_ sender: NSMenuItem) {
        guard let (overlay, intensity, opacity) = sender.representedObject as? (OverlayWindow, CGFloat, CGFloat) else { return }
        ToolManager.shared.blurIntensity = intensity
        ToolManager.shared.blurOpacity = opacity
        // Activate blur tool if not already active
        if overlay.currentTool != .blur {
            syncToolToAllOverlays(.blur)
        }
    }
    
    
    // selectSpeechBubble removed - Speech Bubble replaced by Sticky Notes (floating windows)


    @objc private static func selectHighlighter(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        // Toggle: if already highlighter, deselect all
        if overlay.currentTool == .highlighter {
            syncToolToAllOverlays(nil)
        } else {
            syncToolToAllOverlays(.highlighter)
        }
    }
    
    @objc private static func selectEraser(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        // Toggle: if already eraser, deselect all
        if overlay.currentTool == .eraser {
            syncToolToAllOverlays(nil)
        } else {
            syncToolToAllOverlays(.eraser)
        }
    }
    
    @objc private static func selectNoTool(_ sender: NSMenuItem) {
        guard let _ = sender.representedObject as? OverlayWindow else { return }
        // Clear tool from ALL overlays
        syncToolToAllOverlays(nil)
    }
    
    @objc private static func setPenColor(_ sender: NSMenuItem) {
        guard let (_, hex) = sender.representedObject as? (OverlayWindow, String) else { return }
        
        let newColor = CodableColor(hex: hex)
        let isSameColor = ToolManager.shared.penColor.hexString == newColor.hexString
        
        // Get any overlay to check current tool
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        let currentTool = overlayWindows.first?.currentTool
        
        if currentTool == .pen && isSameColor {
            // Same color selected -> Toggle off all
            syncToolToAllOverlays(nil)
        } else {
            // Different color or tool not active -> Set color and activate pen on all
            ToolManager.shared.penColor = newColor
            syncToolToAllOverlays(.pen)
        }
    }
    
    @objc private static func setPenSize(_ sender: NSMenuItem) {
        guard let (_, sizeIndex) = sender.representedObject as? (OverlayWindow, Int) else { return }
        
        let currentSizeIndex = Constants.penSizes.firstIndex(of: ToolManager.shared.penSize) ?? -1
        let isSameSize = currentSizeIndex == sizeIndex
        
        // Get any overlay to check current tool
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        let currentTool = overlayWindows.first?.currentTool
        
        if currentTool == .pen && isSameSize {
            // Same size selected -> Toggle off all
            syncToolToAllOverlays(nil)
        } else {
            // Different size or tool not active -> Set size and activate pen on all
            ToolManager.shared.setPenSize(sizeIndex)
            syncToolToAllOverlays(.pen)
        }
    }
    
    @objc private static func setHighlighterColor(_ sender: NSMenuItem) {
        guard let (_, hex) = sender.representedObject as? (OverlayWindow, String) else { return }
        
        let newColor = CodableColor(hex: hex)
        let isSameColor = ToolManager.shared.highlighterColor.hexString == newColor.hexString
        
        // Get any overlay to check current tool
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        let currentTool = overlayWindows.first?.currentTool
        
        if currentTool == .highlighter && isSameColor {
            // Same color selected -> Toggle off all
            syncToolToAllOverlays(nil)
        } else {
            // Different color or tool not active -> Set color and activate highlighter on all
            ToolManager.shared.highlighterColor = newColor
            syncToolToAllOverlays(.highlighter)
        }
    }
    
    @objc private static func setZoom(_ sender: NSMenuItem) {
        guard let (overlay, zoom) = sender.representedObject as? (OverlayWindow, CGFloat) else { return }
        overlay.setZoom(zoom)
    }
    
    @objc private static func setTool(_ sender: NSMenuItem) {
        guard let (overlay, tool) = sender.representedObject as? (OverlayWindow, ToolType) else { return }
        overlay.currentTool = tool
        NSHapticFeedbackManager.defaultPerformer.perform(Constants.Haptics.click, performanceTime: .default)
        // Sync tool globally
        ToolManager.shared.currentTool = tool
    }
    
    @objc private static func selectTextTool(_ sender: NSMenuItem) {
        // Deprecated/Removed from UI but kept for safety if called elsewhere? 
        // Or remove entirely. Let's keep it safe.
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        if overlay.currentTool == .text {
            syncToolToAllOverlays(nil)
        } else {
            syncToolToAllOverlays(.text)
        }
    }
    
    @objc private static func setHighlighterSize(_ sender: NSMenuItem) {
        guard let (_, sizeIndex) = sender.representedObject as? (OverlayWindow, Int) else { return }
        
        let currentSizeIndex = Constants.highlighterSizes.firstIndex { abs($0 - ToolManager.shared.highlighterSize) < 0.1 } ?? -1
        let isSameSize = currentSizeIndex == sizeIndex
        
        // Get any overlay to check current tool
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        let currentTool = overlayWindows.first?.currentTool
        
        if currentTool == .highlighter && isSameSize {
            // Same size selected -> Toggle off all
            syncToolToAllOverlays(nil)
        } else {
            // Different size or tool not active -> Set size and activate highlighter on all
            ToolManager.shared.setHighlighterSize(sizeIndex)
            syncToolToAllOverlays(.highlighter)
        }
    }
    
    @objc private static func setTextColor(_ sender: NSMenuItem) {
        guard let (_, hex) = sender.representedObject as? (OverlayWindow, String) else { return }
        
        let newColor = CodableColor(hex: hex)
        let isSameColor = ToolManager.shared.textColor.hexString == newColor.hexString
        
        // Get any overlay to check current tool
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        let currentTool = overlayWindows.first?.currentTool
        
        if currentTool == .text && isSameColor {
            // Same color selected -> Toggle off all
            syncToolToAllOverlays(nil)
        } else {
            // Different color or tool not active -> Set color and activate text on all
            ToolManager.shared.textColor = newColor
            ToolManager.shared.textColorSelected = true  // User explicitly selected a color
            syncToolToAllOverlays(.text)
            
            // Also update any active editing session?
            // "Formatting texts which already entered"
            // The user wants formatting to apply to selected/active text?
            // If we just clicked the menu, we might have lost focus on text field?
            // But if `activeTextField` is kept, we can update it.
            updateActiveTextInAllWindows()
        }
    }
    

    
    private static func updateActiveTextInAllWindows() {
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        for window in overlayWindows {
            window.updateActiveTextAttributes()
        }
    }
    
    @objc private static func setEraserSize(_ sender: NSMenuItem) {
        guard let (_, size) = sender.representedObject as? (OverlayWindow, Int) else { return }
        
        let isSameSize = Int(ToolManager.shared.eraserSize) == size
        
        // Get any overlay to check current tool
        let overlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }
        let currentTool = overlayWindows.first?.currentTool
        
        if currentTool == .eraser && isSameSize {
            // Same size selected -> Toggle off all
            syncToolToAllOverlays(nil)
        } else {
            // Different size or tool not active -> Set size and activate eraser on all
            ToolManager.shared.eraserSize = CGFloat(size)
            syncToolToAllOverlays(.eraser)
        }
    }
    
    @objc private static func toggleLockScreenshot(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        overlay.isLocked.toggle()
        
        // Play sound for feedback
        if overlay.isLocked {
            NSSound(named: "Tink")?.play()
        }
    }

    @objc private static func toggleLockToDisplay(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        overlay.lockToDisplay.toggle()
    }
    
    // MARK: - Phase 1: Opacity Submenu
    
    private static func buildOpacitySubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        
        // Predefined opacity levels
        let levels: [(String, CGFloat)] = [
            ("100%", 1.0),
            ("80%", 0.8),
            ("60%", 0.6),
            ("40%", 0.4),
            ("20%", 0.2)
        ]
        
        for (title, opacity) in levels {
            let item = NSMenuItem(title: title, action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.representedObject = (overlay, opacity)
            item.target = ContextMenuBuilder.self
            item.representedObject = (overlay, opacity)
            item.target = ContextMenuBuilder.self
            // item.state = abs(overlay.currentOpacity - opacity) < 0.05 ? .on : .off
            item.state = .off
            menu.addItem(item)
        }
        
        return menu
    }
    
    // MARK: - Phase 1: Close Behavior Submenu
    
    // MARK: - Phase 1: Close Behavior Submenu
    
    private static func buildCloseBehaviorSubmenu() -> NSMenu {
        let menu = NSMenu()
        // Close Behavior unsupported in this version
        return menu
    }
    
    // MARK: - Phase 1: Actions
    
    @objc private static func setOpacity(_ sender: NSMenuItem) {
        guard let (overlay, opacity) = sender.representedObject as? (OverlayWindow, CGFloat) else { return }
        overlay.alphaValue = opacity
    }
    
    @objc private static func toggleDock(_ sender: NSMenuItem) {
        // Feature unsupported
    }
    
    @objc private static func toggleGhostMode(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        overlay.isGhostMode.toggle()
    }
    
    // MARK: - Phase 2.4: Magnify
    
    @objc private static func toggleLoupe(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        
        // Global toggle: if any overlay has loupe active, disable it there
        let allOverlays = NSApp.windows.compactMap { $0 as? OverlayWindow }
        if let activeOverlay = allOverlays.first(where: { $0.isLoupeActive }) {
            activeOverlay.toggleLoupe(nil)
        } else {
            // Enable on the current overlay
            overlay.toggleLoupe(nil)
        }
    }
    
    @objc private static func setCloseBehavior(_ sender: NSMenuItem) {
        // unsupported
    }
    

    
    // MARK: - Phase 3: Flip Submenu
    
    // MARK: - Phase 3: Flip Submenu
    
    private static func buildFlipSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        // Flip unsupported
        return menu
    }
    
    // MARK: - Smart Restore / App Pinning
    
    private static func buildPinSubmenu(for overlay: OverlayWindow) -> NSMenu {
        let menu = NSMenu()
        let manager = SmartRestoreManager.shared
        
        // Ensure Smart Restore is always enabled when user interacts with pinning
        if !manager.isEnabled {
            manager.isEnabled = true
        }
        
        // List running apps
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        
        let pinnedApps = manager.getPinnedApps(for: overlay.metadata.id)
        
        for app in runningApps {
            guard let name = app.localizedName, let bundleID = app.bundleIdentifier else { continue }
            
            let item = NSMenuItem(title: name, action: #selector(togglePin(_:)), keyEquivalent: "")
            item.target = ContextMenuBuilder.self
            item.representedObject = ["overlay": overlay, "bundleID": bundleID]
            item.image = app.icon
            item.image?.size = NSSize(width: 16, height: 16)
            
            if pinnedApps.contains(bundleID) {
                item.state = .on
            }
            
            menu.addItem(item)
        }
        
        if runningApps.isEmpty {
            menu.addItem(NSMenuItem(title: LanguageManager.shared.string("menu_no_running_apps"), action: nil, keyEquivalent: ""))
        }
        
        // Add "Unpin from All" if there are any pins
        if !pinnedApps.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let unpinAllItem = NSMenuItem(title: LanguageManager.shared.string("menu_unpin_from_all"), action: #selector(unpinFromAll(_:)), keyEquivalent: "")
            unpinAllItem.target = ContextMenuBuilder.self
            unpinAllItem.representedObject = overlay
            unpinAllItem.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: "Unpin from All")
            menu.addItem(unpinAllItem)
        }
        
        return menu
    }
    
    @objc private static func toggleSmartRestoreGlobal(_ sender: NSMenuItem) {
        SmartRestoreManager.shared.isEnabled.toggle()
    }
    
    @objc private static func togglePin(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let overlay = info["overlay"] as? OverlayWindow,
              let bundleID = info["bundleID"] as? String else { return }
        
        let manager = SmartRestoreManager.shared
        if manager.isPinned(overlay.metadata.id) && manager.getPinnedApps(for: overlay.metadata.id).contains(bundleID) {
            manager.unpinOverlay(overlay.metadata.id, fromAppBundleID: bundleID)
        } else {
            manager.pinOverlay(overlay.metadata.id, toAppBundleID: bundleID)
        }
    }
    
    @objc private static func unpinFromAll(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        SmartRestoreManager.shared.clearPins(for: overlay.metadata.id)
        // Make the overlay visible again since it's no longer pinned
        if !overlay.isVisible {
            overlay.orderFront(nil)
        }
        Logger.shared.info("Unpinned overlay \(overlay.metadata.id) from all apps")
    }
    
    // MARK: - Phase 3: Actions
    
    @objc private static func toggleGrayscale(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        overlay.toggleGrayscale()
    }
    
    @objc private static func resetFlip(_ sender: NSMenuItem) {
        // unsupported
    }
    
    // MARK: - Phase 6.1: Neon Border
    
    @objc private static func toggleNeonBorder(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        // overlay.toggleNeonBorder()
    }
    
    // MARK: - Phase 5.4: Color Picker
    
    @objc private static func toggleColorPicker(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        
        // Global toggle: if any overlay has color picker active, disable it there
        let allOverlays = NSApp.windows.compactMap { $0 as? OverlayWindow }
        if let activeOverlay = allOverlays.first(where: { $0.isColorPickerMode }) {
            activeOverlay.toggleColorPicker(nil)
        } else {
            // Enable on the current overlay
            overlay.toggleColorPicker(nil)
        }
    }
    
    // MARK: - Phase 2.2: Rulers
    
    @objc private static func toggleRuler(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        overlay.toggleRuler(nil)
    }
    
    
    // MARK: - Phase 6: Share
    
    @objc private static func shareScreenshot(_ sender: NSMenuItem) {
        guard let overlay = sender.representedObject as? OverlayWindow else { return }
        
        // Get flattened image for sharing
        overlay.endCropMode()
        
        let image = NSImage(cgImage: overlay.renderFlattenedImage(), size: NSSize(
            width: overlay.capturedImage.width,
            height: overlay.capturedImage.height
        ))
        
        // Create sharing service picker
        let picker = NSSharingServicePicker(items: [image])
        
        // Show picker from the overlay window
        if let contentView = overlay.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
    
    // MARK: - Advanced Actions
    
    @objc static func startNewStickyNote(_ sender: Any?) {
        StickyNoteManager.shared.createNote()
        Logger.shared.info("Created new Sticky Note from Overlay Context Menu")
    }
    
    // Note: toggleGrayscale is defined elsewhere in this file (line ~1055)
}
