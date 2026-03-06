//
//  PenTool.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import QuartzCore

/// Handles pen stroke rendering
struct PenTool: AnnotationTool {
    let toolType: ToolType = .pen
    
    func createLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) -> CALayer {
        return createShapeLayer(for: stroke, in: bounds, zoom: zoom)
    }
    
    func rebuildLayer(_ layer: CALayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) {
        guard let shapeLayer = layer as? CAShapeLayer else { return }
        rebuildShapeLayer(shapeLayer, for: stroke, in: bounds, zoom: zoom)
    }
    
    // MARK: - Shape Layer Creation
    
    private func createShapeLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat) -> CAShapeLayer {
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = bounds
        
        let path = CGMutablePath()
        let denormalizedPoints = stroke.points.map { denormalizedPoint($0, in: bounds) }
        
        // Apply zoom to line width
        let scaledLineWidth = stroke.lineWidth * zoom
        
        guard denormalizedPoints.count > 0 else {
            return shapeLayer
        }
        
        path.move(to: denormalizedPoints[0])
        
        if denormalizedPoints.count == 1 {
            // Single point - draw a dot
            let dotRect = CGRect(
                x: denormalizedPoints[0].x - scaledLineWidth / 2,
                y: denormalizedPoints[0].y - scaledLineWidth / 2,
                width: scaledLineWidth,
                height: scaledLineWidth
            )
            path.addEllipse(in: dotRect)
            shapeLayer.fillColor = stroke.color.cgColor
        } else if denormalizedPoints.count == 2 {
            path.addLine(to: denormalizedPoints[1])
        } else {
            // Use quadratic curves for smooth strokes
            for i in 1..<denormalizedPoints.count {
                let midPoint = CGPoint(
                    x: (denormalizedPoints[i - 1].x + denormalizedPoints[i].x) / 2,
                    y: (denormalizedPoints[i - 1].y + denormalizedPoints[i].y) / 2
                )
                path.addQuadCurve(to: midPoint, control: denormalizedPoints[i - 1])
            }
            path.addLine(to: denormalizedPoints.last!)
        }
        
        shapeLayer.path = path
        shapeLayer.strokeColor = stroke.color.cgColor
        shapeLayer.lineWidth = scaledLineWidth
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        shapeLayer.fillColor = nil
        shapeLayer.opacity = Float(stroke.opacity)
        
        // GPU Performance: Enable rasterization for instant zoom/resize
        shapeLayer.shouldRasterize = true
        shapeLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        return shapeLayer
    }
    
    private func rebuildShapeLayer(_ shapeLayer: CAShapeLayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat) {
        // Update line width based on zoom
        shapeLayer.lineWidth = stroke.lineWidth * zoom
        
        // Rebuild path with denormalized points based on new bounds
        let path = CGMutablePath()
        let denormalizedPoints = stroke.points.map { denormalizedPoint($0, in: bounds) }
        
        guard denormalizedPoints.count > 0 else { return }
        
        path.move(to: denormalizedPoints[0])
        
        if denormalizedPoints.count == 1 {
            // Single point - draw a dot
            let dotSize = stroke.lineWidth * zoom
            let dotRect = CGRect(
                x: denormalizedPoints[0].x - dotSize / 2,
                y: denormalizedPoints[0].y - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            path.addEllipse(in: dotRect)
        } else if denormalizedPoints.count == 2 {
            path.addLine(to: denormalizedPoints[1])
        } else {
            // Use quadratic curves for smooth strokes
            for i in 1..<denormalizedPoints.count {
                let midPoint = CGPoint(
                    x: (denormalizedPoints[i - 1].x + denormalizedPoints[i].x) / 2,
                    y: (denormalizedPoints[i - 1].y + denormalizedPoints[i].y) / 2
                )
                path.addQuadCurve(to: midPoint, control: denormalizedPoints[i - 1])
            }
            path.addLine(to: denormalizedPoints.last!)
        }
        
        shapeLayer.path = path
    }
}

/// Handles highlighter stroke rendering (same as pen but with different defaults)
struct HighlighterTool: AnnotationTool {
    let toolType: ToolType = .highlighter
    
    private let penTool = PenTool()
    
    func createLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) -> CALayer {
        return penTool.createLayer(for: stroke, in: bounds, zoom: zoom, backgroundImage: backgroundImage)
    }
    
    func rebuildLayer(_ layer: CALayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) {
        penTool.rebuildLayer(layer, for: stroke, in: bounds, zoom: zoom, backgroundImage: backgroundImage)
    }
}

/// Handles eraser rendering (visual representation of erased strokes)
struct EraserTool: AnnotationTool {
    let toolType: ToolType = .eraser
    
    private let penTool = PenTool()
    
    func createLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) -> CALayer {
        return penTool.createLayer(for: stroke, in: bounds, zoom: zoom, backgroundImage: backgroundImage)
    }
    
    func rebuildLayer(_ layer: CALayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) {
        penTool.rebuildLayer(layer, for: stroke, in: bounds, zoom: zoom, backgroundImage: backgroundImage)
    }
}
