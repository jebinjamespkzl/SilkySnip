//
//  AnnotationLayer.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import QuartzCore
import CoreImage // Phase 31: True Blur

class AnnotationLayer: CALayer {
    
    // MARK: - Properties
    
    private var strokes: [Stroke] = []
    private var strokeLayers: [UUID: CALayer] = [:]
    private var currentStrokeLayer: CALayer?
    
    // Phase 31: Background Image for True Blur
    var backgroundImage: CGImage? {
        didSet {
            // Re-render blur layers if background changes
            if strokes.contains(where: { $0.toolType == .blur }) {
                updateLayout()
            }
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setup()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        masksToBounds = true
        isOpaque = false
        backgroundColor = CGColor.clear
    }
    
    // MARK: - Zoom Support
    
    var currentZoom: CGFloat = 1.0
    
    // MARK: - Flip Support (Phase 22)
    
    var isFlippedHorizontally: Bool = false {
        didSet { updateTextTransforms() }
    }
    
    var isFlippedVertically: Bool = false {
        didSet { updateTextTransforms() }
    }
    
    private func updateTextTransforms() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, layer) in strokeLayers {
            if let stroke = strokes.first(where: { $0.id == id }), stroke.toolType == .text {
                applyFlipTransform(to: layer)
            }
        }
        CATransaction.commit()
    }
    
    private func applyFlipTransform(to layer: CALayer) {
        // If parent is flipped, flip the child text layer specifically to restore readable text
        var transform = CATransform3DIdentity
        
        if isFlippedHorizontally {
            transform = CATransform3DScale(transform, -1, 1, 1)
        }
        if isFlippedVertically {
            transform = CATransform3DScale(transform, 1, -1, 1)
        }
        
        layer.transform = transform
    }
    
    // MARK: - Stroke Management
    
    func getAllStrokes() -> [Stroke] {
        return strokes
    }
    
    // MARK: - Stroke Management
    
    func addStroke(_ stroke: Stroke) {
        strokes.append(stroke)
        Logger.shared.info("AnnotationLayer.addStroke: \(stroke.points.count) points, tool: \(stroke.toolType)")
        
        // Use Tool Registry to create layer
        if let tool = AnnotationToolRegistry.shared.tool(for: stroke.toolType) {
            let layer = tool.createLayer(for: stroke, in: bounds, zoom: currentZoom, backgroundImage: backgroundImage)
            strokeLayers[stroke.id] = layer
            addSublayer(layer)
            
            // Phase 22: Apply flip correction for new Text layers
            if stroke.toolType == .text {
                applyFlipTransform(to: layer)
            }
            
            Logger.shared.info("AnnotationLayer: Layer added, frame: \(layer.frame)")
        }
        
        // Clear current stroke layer
        currentStrokeLayer?.removeFromSuperlayer()
        currentStrokeLayer = nil
    }
    
    // MARK: - Layout Sync (Phase 26)
    
    /// Re-renders all strokes to match the new layer bounds (e.g. after Zoom)
    func updateLayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Temporarily collect current details
        let currentStrokes = strokes
        
        for stroke in currentStrokes {
            // Remove old layer if exists
            if let oldLayer = strokeLayers[stroke.id] {
                oldLayer.removeFromSuperlayer()
            }
            
            // Re-create using new bounds
            if let tool = AnnotationToolRegistry.shared.tool(for: stroke.toolType) {
                let layer = tool.createLayer(for: stroke, in: bounds, zoom: currentZoom, backgroundImage: backgroundImage)
                strokeLayers[stroke.id] = layer
                addSublayer(layer)
                
                if stroke.toolType == .text {
                    applyFlipTransform(to: layer)
                }
            }
        }
        
        CATransaction.commit()
    }

    func updateCurrentStroke(_ stroke: Stroke) {
        // Remove existing current stroke layer
        currentStrokeLayer?.removeFromSuperlayer()
        
        // Create new layer for preview
        if let tool = AnnotationToolRegistry.shared.tool(for: stroke.toolType) {
             currentStrokeLayer = tool.createLayer(for: stroke, in: bounds, zoom: currentZoom, backgroundImage: backgroundImage)
             if let layer = currentStrokeLayer {
                 addSublayer(layer)
             }
        }
    }
    
    func removeStroke(at normalizedPoint: CGPoint) -> Stroke? {
        if let stroke = hitTestStroke(at: normalizedPoint) {
            strokes.removeAll { $0.id == stroke.id }
            
            if let layer = strokeLayers[stroke.id] {
                layer.removeFromSuperlayer()
                strokeLayers.removeValue(forKey: stroke.id)
            }
            return stroke
        }
        return nil
    }
    
    func hitTestStroke(at normalizedPoint: CGPoint) -> Stroke? {
        let point = denormalizedPoint(normalizedPoint)
        let hitRadius: CGFloat = 10 * currentZoom
        
        Logger.shared.info("Hit testing at norm: \(normalizedPoint) -> denorm: \(point). Total strokes: \(strokes.count)")
        
        // Find stroke that intersects with the point
        for stroke in strokes.reversed() {
            if stroke.toolType == .text {
                // For text, we need to check bounding box of the text layer
               if let layer = strokeLayers[stroke.id] as? CATextLayer {
                   // Check if point is inside layer frame
                   if layer.frame.contains(point) {
                       Logger.shared.info("Hit text stroke: \(stroke.id)")
                       return stroke
                   }
               } else {
                   Logger.shared.info("Text stroke missing layer: \(stroke.id)")
               }
            } else {
                if strokeContainsPoint(stroke, point: point, tolerance: hitRadius) {
                    return stroke
                }
            }
        }
        
        return nil
    }
    
    func removeStroke(_ stroke: Stroke) {
        if let layer = strokeLayers[stroke.id] {
            layer.removeFromSuperlayer()
            strokeLayers.removeValue(forKey: stroke.id)
        }
        strokes.removeAll { $0.id == stroke.id }
    }
    
    func clearAll() {
        strokes.removeAll()
        strokeLayers.values.forEach { $0.removeFromSuperlayer() }
        strokeLayers.removeAll()
        currentStrokeLayer?.removeFromSuperlayer()
        currentStrokeLayer = nil
    }
    
    /// Instantly scales all strokes using GPU-accelerated CALayer transforms
    /// Much faster than rebuilding paths - provides real-time zoom sync
    func scaleToFit(oldBounds: CGRect, newBounds: CGRect) {
        guard oldBounds.width > 0 && oldBounds.height > 0 else { return }
        
        // Calculate scale factors
        let scaleX = newBounds.width / oldBounds.width
        let scaleY = newBounds.height / oldBounds.height
        
        // Disable animations for instant sync
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Apply transform to all stroke layers
        for (id, layer) in strokeLayers {
            // For container layers (blur, speechBubble), scale the sublayers directly
            if let stroke = strokes.first(where: { $0.id == id }) {
                if stroke.toolType == .blur || stroke.toolType == .stickyNote {
                    // Scale the container frame and sublayer frames
                    layer.frame = newBounds
                    if let sublayer = layer.sublayers?.first {
                        let oldFrame = sublayer.frame
                        sublayer.frame = CGRect(
                            x: oldFrame.origin.x * scaleX,
                            y: oldFrame.origin.y * scaleY,
                            width: oldFrame.width * scaleX,
                            height: oldFrame.height * scaleY
                        )
                    }
                } else {
                    // Shape layers - use GPU-accelerated transform
                    layer.transform = CATransform3DMakeScale(scaleX, scaleY, 1.0)
                }
            } else {
                layer.transform = CATransform3DMakeScale(scaleX, scaleY, 1.0)
            }
        }
        
        if let currentLayer = currentStrokeLayer {
            currentLayer.transform = CATransform3DMakeScale(scaleX, scaleY, 1.0)
        }
        
        CATransaction.commit()
    }
    
    /// Rebuilds all stroke paths based on current bounds and resets transforms
    /// Call this after zooming is complete for crisp rendering
    func rebuildStrokesForCurrentBounds() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Update each stroke layer's frame and path based on new bounds
        for stroke in strokes {
            guard let layer = strokeLayers[stroke.id] else { continue }
            
            // Reset transform
            layer.transform = CATransform3DIdentity
            layer.frame = bounds
            
            if let tool = AnnotationToolRegistry.shared.tool(for: stroke.toolType) {
                tool.rebuildLayer(layer, for: stroke, in: bounds, zoom: currentZoom, backgroundImage: backgroundImage)
                
                // Specific flip correction for Text
                if stroke.toolType == .text {
                    applyFlipTransform(to: layer)
                }
            }
        }
        
        // Update current stroke too if any
        if let currentLayer = currentStrokeLayer {
            currentLayer.transform = CATransform3DIdentity
            currentLayer.frame = bounds
        }
        
        CATransaction.commit()
    }
    

    
    /// Legacy method for compatibility - calls rebuildStrokesForCurrentBounds
    func redrawAllStrokes() {
        rebuildStrokesForCurrentBounds()
    }
    
    // MARK: - Rendering
    

    

    
    // MARK: - Phase 2: Speech Bubble Layer
    



    
    func denormalizedPoint(_ normalizedPoint: CGPoint) -> CGPoint {
        return CGPoint(
            x: normalizedPoint.x * bounds.width,
            y: normalizedPoint.y * bounds.height
        )
    }
    
    private func strokeContainsPoint(_ stroke: Stroke, point: CGPoint, tolerance: CGFloat) -> Bool {
        let points = stroke.points.map { denormalizedPoint($0) }
        
        // Shape Tools Hit Test (Blur, StickyNote)
        if stroke.toolType == .blur || stroke.toolType == .stickyNote || stroke.toolType == .crop {
            guard !points.isEmpty else { return false }
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            
            // Calculate bounding box
            let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
        
        for i in 0..<points.count {
            let strokePoint = points[i]
            let distance = hypot(point.x - strokePoint.x, point.y - strokePoint.y)
            
            if distance <= tolerance + stroke.lineWidth / 2 {
                return true
            }
            
            // Check line segments
            if i > 0 {
                let prevPoint = points[i - 1]
                if distanceFromPointToLineSegment(point, start: prevPoint, end: strokePoint) <= tolerance {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func distanceFromPointToLineSegment(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        
        if dx == 0 && dy == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
        
        let projectionX = start.x + t * dx
        let projectionY = start.y + t * dy
        
        return hypot(point.x - projectionX, point.y - projectionY)
    }
    
    // MARK: - Export
    
    /// Renders the annotation layer to a CGImage for flattening with the screenshot
    func renderToImage() -> CGImage? {
        let scale = contentsScale
        
        // Create a bitmap context
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        
        guard width > 0 && height > 0 else { return nil }
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.scaleBy(x: scale, y: scale)
        
        // Render the layer
        render(in: context)
        
        return context.makeImage()
    }
}
