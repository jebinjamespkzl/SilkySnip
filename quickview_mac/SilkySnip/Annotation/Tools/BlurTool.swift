//
//  BlurTool.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import QuartzCore
import CoreImage

/// Handles blur region rendering for privacy masking
struct BlurTool: AnnotationTool {
    let toolType: ToolType = .blur
    
    func createLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) -> CALayer {
        let containerLayer = CALayer()
        containerLayer.frame = bounds
        
        // Get bounding rect for blur region from stroke points
        let denormalizedPoints = stroke.points.map { denormalizedPoint($0, in: bounds) }
        guard denormalizedPoints.count >= 2 else {
            return containerLayer
        }
        
        // Calculate bounding rect
        let blurRect = calculateBoundingRect(from: denormalizedPoints)
        
        // Create blur effect layer
        let blurLayer = CALayer()
        blurLayer.frame = blurRect
        blurLayer.cornerRadius = 4
        blurLayer.masksToBounds = true
        
        // Phase 31: True Blur Logic
        if let bgImage = backgroundImage {
            // Need to crop the background image to the blur rect
            // 1. Calculate relative rect on the image
            // bounds.width handles zoom. bgImage is usually full internal resolution.
            
            // Avoid division by zero
            let bWidth = max(bounds.width, 1)
            let bHeight = max(bounds.height, 1)
            
            let scaleX = CGFloat(bgImage.width) / bWidth
            let scaleY = CGFloat(bgImage.height) / bHeight
            
            // Image coordinates (Y is Top-Originated in CGImage usually, but check flipped context)
            // OverlayWindow is flipped? No, default CALayer is bottom-up?
            // "denormalizedPoint" -> (0,0) is bottom-left usually in Mac CALayers unless isGeometryFlipped is true.
            // Mac NSView is Bottom-Left.
            // CGImage is Top-Left usually in data, but drawing context handles it.
            
            // Note: If scaleX/Y is roughly NSScreen.main.backingScaleFactor (e.g. 2.0), it matches.
            
            let cropRect = CGRect(
                 x: blurRect.origin.x * scaleX,
                 y: (bounds.height - blurRect.maxY) * scaleY, // Flip Y for CGImage cropping (Top-down)
                 width: blurRect.width * scaleX,
                 height: blurRect.height * scaleY
            )
            
            if let cropped = bgImage.cropping(to: cropRect) {
                // Apply Blur Filter
                let ciImage = CIImage(cgImage: cropped)
                let blurRadius = stroke.blurRadius ?? stroke.lineWidth
                
                // Use a larger radius for better privacy obscuring
                let effectiveRadius = blurRadius * 1.5
                
                if let filter = CIFilter(name: "CIGaussianBlur") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(effectiveRadius, forKey: kCIInputRadiusKey)
                    
                    if let output = filter.outputImage {
                        let context = CIContext()
                        // Crop to original extent to avoid blur expansion
                        if let finalImage = context.createCGImage(output, from: ciImage.extent) {
                            blurLayer.contents = finalImage
                            // CRITICAL FIX: No background color if we have true blur
                            blurLayer.backgroundColor = nil
                        } else {
                            Logger.shared.error("Blur Context Failed")
                            blurLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.5).cgColor
                        }
                    }
                }
            } else {
                 Logger.shared.error("Blur Cropping Failed. Rect: \(cropRect), Image: \(bgImage.width)x\(bgImage.height)")
                 blurLayer.backgroundColor = NSColor.gray.withAlphaComponent(stroke.blurOpacity ?? 0.8).cgColor
            }
        } else {
             // Fallback: Semi-transparent gray (Privacy Mask style)
             blurLayer.backgroundColor = NSColor.gray.withAlphaComponent(stroke.blurOpacity ?? 0.8).cgColor
             
            // Try applying filter to self? No, that only blurs the gray box edges.
        }
        
        containerLayer.addSublayer(blurLayer)
        return containerLayer
    }
    
    func rebuildLayer(_ layer: CALayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) {
        // Since Blur depends on background image cropping which changes on Zoom/Resize
        // It's safer to just replace the sublayer content entirely.
        
        // 1. Remove old sublayers
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        // 2. Create new content essentially via createLayer, but avoiding creating a new container
        // Actually, createLayer returns a container.
        // Let's just run the logic to create the blurLayer and add it.
        
        let denormalizedPoints = stroke.points.map { denormalizedPoint($0, in: bounds) }
        guard denormalizedPoints.count >= 2 else { return }
        
        let blurRect = calculateBoundingRect(from: denormalizedPoints)
        
        let blurLayer = CALayer()
        blurLayer.frame = blurRect
        blurLayer.cornerRadius = 4
        blurLayer.masksToBounds = true
        
        // Duplicated Logic (Refactor into helper ideally, but for now inline for safety)
        if let bgImage = backgroundImage {
             let bWidth = max(bounds.width, 1)
             let bHeight = max(bounds.height, 1)
             let scaleX = CGFloat(bgImage.width) / bWidth
             let scaleY = CGFloat(bgImage.height) / bHeight
             
            let cropRect = CGRect(
                  x: blurRect.origin.x * scaleX,
                  y: (bounds.height - blurRect.maxY) * scaleY,
                  width: blurRect.width * scaleX,
                  height: blurRect.height * scaleY
             )
             
             if let cropped = bgImage.cropping(to: cropRect) {
                 let ciImage = CIImage(cgImage: cropped)
                 let blurRadius = stroke.blurRadius ?? stroke.lineWidth
                 let effectiveRadius = blurRadius * 1.5
                 
                 if let filter = CIFilter(name: "CIGaussianBlur") {
                     filter.setValue(ciImage, forKey: kCIInputImageKey)
                     filter.setValue(effectiveRadius, forKey: kCIInputRadiusKey)
                     
                     if let output = filter.outputImage {
                         let context = CIContext()
                         if let finalImage = context.createCGImage(output, from: ciImage.extent) {
                             blurLayer.contents = finalImage
                             blurLayer.backgroundColor = nil
                         } else {
                             blurLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.5).cgColor
                         }
                     }
                 }
             } else {
                  blurLayer.backgroundColor = NSColor.gray.withAlphaComponent(stroke.blurOpacity ?? 0.8).cgColor
             }
        } else {
             blurLayer.backgroundColor = NSColor.gray.withAlphaComponent(stroke.blurOpacity ?? 0.8).cgColor
        }
        
        layer.addSublayer(blurLayer)
    }
    
    // MARK: - Helpers
    
    private func calculateBoundingRect(from points: [CGPoint]) -> CGRect {
        var minX = points[0].x
        var maxX = points[0].x
        var minY = points[0].y
        var maxY = points[0].y
        
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
