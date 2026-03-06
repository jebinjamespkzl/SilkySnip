//
//  ToolManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Foundation
import CoreGraphics
import AppKit

class ToolManager {
    
    // MARK: - Shared Instance for Global Color Sync
    
    /// Shared instance used for global pen/highlighter color settings
    /// All overlays use this for consistent colors across screenshots
    static let shared = ToolManager()
    
    // MARK: - Properties
    
    var currentTool: ToolType? {
        didSet {
            updateCursor()
            NotificationCenter.default.post(name: Notification.Name("ToolManagerToolChanged"), object: nil)
        }
    }
    
    var penColor: CodableColor = CodableColor(hex: Constants.defaultPenColor) {
        didSet { NotificationCenter.default.post(name: Notification.Name("ToolManagerSettingsChanged"), object: nil) }
    }
    var penSize: CGFloat = Constants.penSizes[1] {
        didSet { NotificationCenter.default.post(name: Notification.Name("ToolManagerSettingsChanged"), object: nil) }
    }
    
    var highlighterColor: CodableColor = CodableColor(hex: Constants.defaultHighlighterColor) {
        didSet { NotificationCenter.default.post(name: Notification.Name("ToolManagerSettingsChanged"), object: nil) }
    }
    var highlighterSize: CGFloat = Constants.highlighterSizes[1] {
        didSet { NotificationCenter.default.post(name: Notification.Name("ToolManagerSettingsChanged"), object: nil) }
    }
    var highlighterOpacity: CGFloat = Constants.defaultHighlighterOpacity {
        didSet { NotificationCenter.default.post(name: Notification.Name("ToolManagerSettingsChanged"), object: nil) }
    }
    
    var eraserSize: CGFloat = 20 {
        didSet { NotificationCenter.default.post(name: Notification.Name("ToolManagerSettingsChanged"), object: nil) }
    }
    
    // Text Properties
    var textColor: CodableColor = CodableColor(hex: Theme.Colors.black) // Will only be used after explicit selection
    var textColorSelected: Bool = false  // Must be true before text tool can be used
    var textSize: CGFloat = 15  // Normal font size (Small=11, Normal=15, Large=19)
    var textIsBold: Bool = false
    var textIsItalic: Bool = true // Default to Italic for security reasons
    var textIsUnderline: Bool = false
    
    // Phase 2: Blur Tool Properties
    var blurIntensity: CGFloat = 10.0  // Gaussian blur radius (1-30)
    var blurOpacity: CGFloat = 1.0     // Blur overlay opacity
    
    // Phase 2: Magnify (Loupe) Properties
    var loupeEnabled: Bool = false     // Toggle via preferences
    var loupeMagnification: CGFloat = 3.0  // 3x, 5x, or 10x magnification
    
    // Phase 8: Sticky Note Properties
    var stickyNoteColor: CodableColor = CodableColor(hex: "#FFEB3B") // Yellow
    var stickyNoteListType: String = "bullet" // bullet, number, none
    
    private(set) var currentStroke: Stroke?
    
    // MARK: - Stroke Lifecycle
    
    func beginStroke(at point: CGPoint) {
        guard let tool = currentTool else {
            Logger.shared.info("beginStroke: No tool selected")
            return
        }
        Logger.shared.info("beginStroke at \(point) with tool \(tool)")
        
        let color: CodableColor
        let lineWidth: CGFloat
        let opacity: CGFloat
        
        switch tool {
        case .pen:
            color = penColor
            lineWidth = penSize
            opacity = 1.0
        case .highlighter:
            color = highlighterColor
            lineWidth = highlighterSize
            opacity = highlighterOpacity
        case .eraser:
            color = CodableColor(hex: "#000000")
            lineWidth = eraserSize
            opacity = 1.0

        case .text:
            // Text stroke is handled differently (via addText)
            // But if we ever treat it as a stroke, these are defaults
            color = textColor
            lineWidth = 0
            opacity = 1.0
            
        case .blur:
            // Blur uses transparent overlay with blur effect
            color = CodableColor(hex: "#888888")
            lineWidth = blurIntensity
            opacity = blurOpacity
            
        case .stickyNote:
            // Sticky Notes use yellow fill by default
            color = CodableColor(hex: "#FFEB3B")
            lineWidth = 0  // No border by default
            opacity = 1.0
            
        case .crop:
            // Crop is not a drawing tool, but handle case to satisfy exhaustiveness
            color = CodableColor(hex: "#000000")
            lineWidth = 1
            opacity = 1.0
        }
        
        currentStroke = Stroke(
            toolType: tool,
            points: [point],
            color: color,
            lineWidth: lineWidth,
            opacity: opacity
        )
        Logger.shared.info("Stroke created, lineWidth \(lineWidth)")
    }
    
    func continueStroke(at point: CGPoint) {
        currentStroke?.addPoint(point)
        // Log every 10th point to avoid spam
        if let stroke = currentStroke, stroke.points.count % 10 == 0 {
            Logger.shared.info("Stroke has \(stroke.points.count) points")
        }
    }
    
    func endStroke() -> Stroke? {
        defer { currentStroke = nil }
        if let stroke = currentStroke {
            Logger.shared.info("endStroke: Stroke with \(stroke.points.count) points")
        } else {
            Logger.shared.info("endStroke: No stroke to end")
        }
        return currentStroke
    }
    
    func cancelStroke() {
        currentStroke = nil
    }
    
    // MARK: - Tool Settings
    
    func setPenSize(_ index: Int) {
        guard index >= 0 && index < Constants.penSizes.count else { return }
        penSize = Constants.penSizes[index]
    }
    
    func setHighlighterSize(_ index: Int) {
        guard index >= 0 && index < Constants.highlighterSizes.count else { return }
        highlighterSize = Constants.highlighterSizes[index]
    }
    
    func setTextSize(_ size: CGFloat) {
        textSize = size
    }
    
    func toggleTextBold() {
        textIsBold.toggle()
    }
    
    func toggleTextItalic() {
        textIsItalic.toggle()
    }
    
    func toggleTextUnderline() {
        textIsUnderline.toggle()
    }
    
    // Helper to create text annotation
    func createTextAnnotation(at point: CGPoint, text: String, width: CGFloat? = nil, height: CGFloat? = nil) -> Stroke {
        return Stroke(
            toolType: .text,
            location: point,
            color: textColor,
            text: text,
            fontName: "Helvetica", // Default for now
            fontSize: textSize,
            isBold: textIsBold,
            isItalic: true, // Always Italic for security purposes
            isUnderline: textIsUnderline,
            width: width,
            height: height
        )
    }
    
    // Helper to create sticky note
    func createStickyNoteStroke(at point: CGPoint, text: String = "") -> Stroke {
        var stroke = Stroke(
            toolType: .stickyNote, // Use Sticky Note tool
            location: point,
            color: CodableColor(hex: "#FFEB3B"), // Default Yellow
            text: text,
            fontSize: 14, // Smaller font for notes
            width: 150, // Default width
            height: nil // Auto height
        )
        stroke.listType = "bullet" // Default to bullet
        return stroke
    }
    
    // MARK: - Cursor
    
    private func updateCursor() {
        switch currentTool {
        case .pen:
            if let image = createPenCursorImage() {
                // Hotspot at tip (bottom left)
                let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 2, y: 22))
                cursor.set()
            } else {
                NSCursor.crosshair.set()
            }
        case .highlighter:
            if let image = createHighlighterCursorImage() {
                let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 2, y: 22))
                cursor.set()
            } else {
                NSCursor.crosshair.set()
            }
        case .eraser:
            if let image = createEraserCursorImage() {
                let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
                cursor.set()
            } else {
                NSCursor.crosshair.set()
            }
        case .text:
            NSCursor.iBeam.set()
        case .blur:
            NSCursor.crosshair.set()
        case .stickyNote:
            // Custom sticky note cursor or crosshair
            if let image = createStickyNoteCursorImage() {
                 let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 0, y: 16)) // Top Left
                 cursor.set()
            } else {
                 NSCursor.crosshair.set()
            }
        case .crop:
            NSCursor.crosshair.set()
        case nil:
            NSCursor.arrow.set()
        }
    }
    
    private func createPenCursorImage() -> NSImage? {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let path = NSBezierPath()
        // Simple pen shape
        // Tip at bottom left (2, 22) -> wait, Y is flipped in cursor coords? 
        // In NSCursor, (0,0) is top-left usually, but hotspot is from top-left.
        // Let's draw a diagonal pen.
        
        // Handle
        path.move(to: NSPoint(x: 18, y: 22))
        path.line(to: NSPoint(x: 22, y: 18))
        path.line(to: NSPoint(x: 8, y: 4))
        path.line(to: NSPoint(x: 4, y: 8))
        path.close()
        
        penColor.nsColor.setFill()
        path.fill()
        NSColor.white.setStroke()
        path.lineWidth = 1
        path.stroke()
        
        // Tip
        let tipPath = NSBezierPath()
        tipPath.move(to: NSPoint(x: 4, y: 8))
        tipPath.line(to: NSPoint(x: 2, y: 2))
        tipPath.line(to: NSPoint(x: 8, y: 4))
        tipPath.close()
        
        NSColor.black.setFill()
        tipPath.fill()
        
        image.unlockFocus()
        return image
    }
    
    private func createHighlighterCursorImage() -> NSImage? {
        let size = NSSize(width: 16, height: 32)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8, y: 32))
        path.line(to: NSPoint(x: 4, y: 20))
        path.line(to: NSPoint(x: 4, y: 8))
        path.line(to: NSPoint(x: 12, y: 8))
        path.line(to: NSPoint(x: 12, y: 20))
        path.close()
        
        highlighterColor.nsColor.withAlphaComponent(0.8).setFill()
        path.fill()
        
        NSColor.black.setStroke()
        path.lineWidth = 1
        path.stroke()
        
        image.unlockFocus()
        
        return image
    }
    
    private func createEraserCursorImage() -> NSImage? {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let rect = NSRect(x: 2, y: 2, width: 16, height: 16)
        let path = NSBezierPath(ovalIn: rect)
        
        NSColor.white.setFill()
        path.fill()
        
        NSColor.darkGray.setStroke()
        path.lineWidth = 1.5
        path.stroke()
        
        image.unlockFocus()
        
        return image
    }
    private func createStickyNoteCursorImage() -> NSImage? {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Draw a small yellow square with folded corner
        let rect = NSRect(x: 2, y: 2, width: 16, height: 16)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 2, y: 18)) // Top Left
        path.line(to: NSPoint(x: 14, y: 18)) // Top Right (minus fold)
        path.line(to: NSPoint(x: 18, y: 14)) // Right Top (fold end)
        path.line(to: NSPoint(x: 18, y: 2))  // Bottom Right
        path.line(to: NSPoint(x: 2, y: 2))   // Bottom Left
        path.close()
        
        CodableColor(hex: "#FFEB3B").nsColor.setFill()
        path.fill()
        NSColor.black.setStroke()
        path.lineWidth = 1
        path.stroke()
        
        // Fold
        let foldPath = NSBezierPath()
        foldPath.move(to: NSPoint(x: 14, y: 18))
        foldPath.line(to: NSPoint(x: 14, y: 14))
        foldPath.line(to: NSPoint(x: 18, y: 14))
        NSColor(white: 0, alpha: 0.1).setFill()
        foldPath.fill()
        NSColor.black.setStroke()
        foldPath.stroke()
        
        image.unlockFocus()
        return image
    }
}
