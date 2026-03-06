//
//  RulerOverlay.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Cocoa

class RulerOverlay: NSView {
    
    // MARK: - Properties
    
    private let rulerThickness: CGFloat = 20
    private var trackingArea: NSTrackingArea?
    
    /// Guidelines (position in view coordinates)
    private var verticalGuides: [CGFloat] = []
    private var horizontalGuides: [CGFloat] = []
    
    /// Currently dragged guide
    private enum DraggedGuide {
        case vertical(index: Int)
        case horizontal(index: Int)
        case newVertical
        case newHorizontal
    }
    
    private var draggedGuide: DraggedGuide?
    
    /// Whether to show the internal measurement tooltip (X: Y:)
    /// Set to false if external tooltip is handling this data
    var showsMeasurementTooltip: Bool = true
    
    /// Mouse location for hover measurements
    private var hoverPoint: CGPoint?
    
    /// Public property to get current measurement string
    var currentMeasurementString: String? {
        guard let point = hoverPoint else { return nil }
        let pixelX = Int(point.x - rulerThickness)
        let pixelY = Int(bounds.height - rulerThickness - point.y)
        if pixelX >= 0 && pixelY >= 0 {
            let lm = LanguageManager.shared
            return "\(lm.string("label_x_axis")) \(pixelX), \(lm.string("label_y_axis")) \(pixelY)"
        }
        return nil
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
        
        super.updateTrackingAreas()
    }
    
    // MARK: - Drawing
    
    /// Helper to get measurement string at a specific point on demand
    func getMeasurement(at point: CGPoint) -> String? {
        let pixelX = Int(point.x - rulerThickness)
        let pixelY = Int(bounds.height - rulerThickness - point.y)
        
        // Return values even if slightly outside to be helpful, or strictly valid?
        // Let's constrain to positive to ensure validity relative to image
        if pixelX >= 0 && pixelY >= 0 {
             let lm = LanguageManager.shared
             return "\(lm.string("label_x_axis")) \(pixelX)  \(lm.string("label_y_axis")) \(pixelY)"
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw Rulers
        drawRulers(in: context)
        
        // Draw Guidelines
        drawGuidelines(in: context)
        
        // Draw Hover Crosshair/Measurement
        if let point = hoverPoint, showsMeasurementTooltip {
            drawHoverMeasurement(at: point, in: context)
        }
    }
    
    private func drawRulers(in context: CGContext) {
        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        
        // Top Ruler
        context.fill(CGRect(x: rulerThickness, y: bounds.height - rulerThickness, width: bounds.width - rulerThickness, height: rulerThickness))
        
        // Left Ruler
        context.fill(CGRect(x: 0, y: 0, width: rulerThickness, height: bounds.height - rulerThickness))
        
        // Corner
        context.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        context.fill(CGRect(x: 0, y: bounds.height - rulerThickness, width: rulerThickness, height: rulerThickness))
        
        // Ticks and Labels
        let step: CGFloat = 50
        
        // Text attributes
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.white
        ]
        
        // Top Ruler Ticks
        for x in stride(from: 0.0, through: bounds.width - rulerThickness, by: step) {
             let drawX = x + rulerThickness
             // Tick
             context.move(to: CGPoint(x: drawX, y: bounds.height))
             context.addLine(to: CGPoint(x: drawX, y: bounds.height - 5))
             context.setStrokeColor(NSColor.white.cgColor)
             context.strokePath()
             
             // Label
             let labelTerm = "\(Int(x))" as NSString
             labelTerm.draw(at: CGPoint(x: drawX + 2, y: bounds.height - 18), withAttributes: attributes)
        }
        
        // Left Ruler Ticks
        // Note: Y is 0 at bottom in Cocoa, but rulers usually start 0 at top-left for images.
        // Let's measure from Top-Left.
        for y in stride(from: 0.0, through: bounds.height - rulerThickness, by: step) {
            let drawY = bounds.height - rulerThickness - y
            // Tick
            context.move(to: CGPoint(x: 0, y: drawY))
            context.addLine(to: CGPoint(x: 5, y: drawY))
            context.setStrokeColor(NSColor.white.cgColor)
            context.strokePath()
            
            // Label
            let labelTerm = "\(Int(y))" as NSString
            // Draw mostly vertical text? Or just normal
            labelTerm.draw(at: CGPoint(x: 2, y: drawY - 10), withAttributes: attributes)
        }
    }
    
    private func drawGuidelines(in context: CGContext) {
        context.setStrokeColor(NSColor.cyan.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 2])
        
        for x in verticalGuides {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
            context.strokePath()
        }
        
        for y in horizontalGuides {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            context.strokePath()
        }
    }
    
    private func drawHoverMeasurement(at point: CGPoint, in context: CGContext) {
        // Draw crosshair on rulers
        context.setStrokeColor(NSColor.red.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [])
        
        // Line on Top Ruler
        context.move(to: CGPoint(x: point.x, y: bounds.height))
        context.addLine(to: CGPoint(x: point.x, y: bounds.height - rulerThickness))
        context.strokePath()
        
        // Line on Left Ruler
        context.move(to: CGPoint(x: 0, y: point.y))
        context.addLine(to: CGPoint(x: rulerThickness, y: point.y))
        context.strokePath()
        
        // Draw value near cursor?
        let pixelX = Int(point.x - rulerThickness)
        let pixelY = Int(bounds.height - rulerThickness - point.y)
        
        if pixelX >= 0 && pixelY >= 0 && showsMeasurementTooltip {
            let lm = LanguageManager.shared
            let text = "\(lm.string("label_x_axis")) \(pixelX), \(lm.string("label_y_axis")) \(pixelY)" as NSString
            let size = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
            
            let bgRect = CGRect(x: point.x + 10, y: point.y - 20, width: size.width + 8, height: size.height + 4)
            context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            context.fill(bgRect)
            
            text.draw(at: CGPoint(x: bgRect.minX + 4, y: bgRect.minY + 2), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.white
            ])
        }
    }
    
    // MARK: - Mouse Events
    override func hitTest(_ point: NSPoint) -> NSView? {
        let viewPoint = convert(point, from: nil)
        
        // 1. Ruler Tracks
        if viewPoint.y > bounds.height - rulerThickness || viewPoint.x < rulerThickness {
            return super.hitTest(point)
        }
        
        // 2. Guides (Tolerance)
        for x in verticalGuides {
            if abs(viewPoint.x - x) < 5 { return super.hitTest(point) }
        }
        for y in horizontalGuides {
            if abs(viewPoint.y - y) < 5 { return super.hitTest(point) }
        }
        
        // 3. Otherwise: Passthrough
        return nil
    }
    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check if clicking rulers to create guide
        if point.y > bounds.height - rulerThickness && point.x > rulerThickness {
            // New vertical guide
            draggedGuide = .newVertical
            NSCursor.resizeLeftRight.set()
        } else if point.x < rulerThickness && point.y < bounds.height - rulerThickness {
            // New horizontal guide
            draggedGuide = .newHorizontal
            NSCursor.resizeUpDown.set()
        } else {
            // Check existing guides
            // Tolerance
            let tolerance: CGFloat = 4
            
            for (i, x) in verticalGuides.enumerated() {
                if abs(point.x - x) < tolerance {
                    draggedGuide = .vertical(index: i)
                    NSCursor.resizeLeftRight.set()
                    return
                }
            }
            
            for (i, y) in horizontalGuides.enumerated() {
                if abs(point.y - y) < tolerance {
                    draggedGuide = .horizontal(index: i)
                    NSCursor.resizeUpDown.set()
                    return
                }
            }
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let guide = draggedGuide else { return }
        let point = convert(event.locationInWindow, from: nil)
        
        switch guide {
        case .newVertical:
            verticalGuides.append(point.x)
            draggedGuide = .vertical(index: verticalGuides.count - 1)
        case .newHorizontal:
            horizontalGuides.append(point.y)
            draggedGuide = .horizontal(index: horizontalGuides.count - 1)
        case .vertical(let index):
            if index < verticalGuides.count {
                // If dragged out of view (left), remove it
                if point.x < rulerThickness {
                    verticalGuides.remove(at: index)
                    draggedGuide = nil
                    NSCursor.arrow.set()
                } else {
                    verticalGuides[index] = point.x
                }
            }
        case .horizontal(let index):
            if index < horizontalGuides.count {
                // If dragged out of view (top/ruler), remove it
                if point.y > bounds.height - rulerThickness {
                    horizontalGuides.remove(at: index)
                    draggedGuide = nil
                    NSCursor.arrow.set()
                } else {
                    horizontalGuides[index] = point.y
                }
            }
        }
        
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        draggedGuide = nil
        NSCursor.arrow.set()
    }
}
