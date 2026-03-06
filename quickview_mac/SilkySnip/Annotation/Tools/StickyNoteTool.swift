//
//  StickyNoteTool.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import QuartzCore

/// Handles Sticky Note annotation rendering and behavior
struct StickyNoteTool: AnnotationTool {
    let toolType: ToolType = .stickyNote
    
    // Default Padding
    private let textPadding: CGFloat = 10
    
    func createLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) -> CALayer {
        let containerLayer = CALayer()
        containerLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        let normalizedPoint = stroke.points.first ?? .zero
        let point = denormalizedPoint(normalizedPoint, in: bounds)
        
        // --- 1. Calculate Size ---
        let width = (stroke.width ?? 150) * zoom
        var height: CGFloat
        
        // Simulate text to get height
        let fontSize = (stroke.fontSize ?? 14) * zoom
        let fontName = stroke.fontName ?? "Helvetica"
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        if stroke.isBold == true { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black // Text always black on Sticky Note for now
        ]
        
        let displayString = formatText(stroke.text, listType: stroke.listType)
        let attributedString = NSAttributedString(string: displayString, attributes: attributes)
        
        if let strokeHeight = stroke.height {
            height = strokeHeight * zoom
        } else {
            // Auto-height
            let constraintSize = CGSize(width: width - (textPadding * 2), height: .greatestFiniteMagnitude)
            let rect = attributedString.boundingRect(with: constraintSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            height = max(rect.height + (textPadding * 2), width * 0.8) // Min height aspect
        }
        
        // Frame
        let frame = CGRect(origin: point, size: CGSize(width: width, height: height))
        containerLayer.frame = frame
        
        // --- 2. Background Shape (Yellow Paper with Fold) ---
        let bgLayer = CAShapeLayer()
        bgLayer.frame = containerLayer.bounds
        bgLayer.cornerRadius = 2
        
        let path = CGMutablePath()
        let w = frame.width
        let h = frame.height
        let foldSize: CGFloat = 20 * zoom
        
        // Main shape minus fold corner (top-right usually, or bottom-right?) 
        // Let's do bottom-right fold for classic look
        path.move(to: CGPoint(x: 0, y: 0)) // Top-Left
        path.addLine(to: CGPoint(x: w, y: 0)) // Top-Right
        path.addLine(to: CGPoint(x: w, y: h - foldSize)) // Right side stops before fold
        path.addLine(to: CGPoint(x: w - foldSize, y: h)) // Bottom side starts after fold
        path.addLine(to: CGPoint(x: 0, y: h)) // Bottom-Left
        path.closeSubpath()
        
        bgLayer.path = path
        bgLayer.fillColor = stroke.color.cgColor
        // Slight shadow for depth
        bgLayer.shadowColor = NSColor.black.cgColor
        bgLayer.shadowOpacity = 0.3
        bgLayer.shadowOffset = CGSize(width: 2, height: -2)
        bgLayer.shadowRadius = 4
        
        containerLayer.addSublayer(bgLayer)
        
        // Fold Triangle
        let foldLayer = CAShapeLayer()
        foldLayer.frame = containerLayer.bounds
        let foldPath = CGMutablePath()
        foldPath.move(to: CGPoint(x: w, y: h - foldSize))
        foldPath.addLine(to: CGPoint(x: w - foldSize, y: h - foldSize))
        foldPath.addLine(to: CGPoint(x: w - foldSize, y: h))
        foldPath.closeSubpath()
        
        foldLayer.path = foldPath
        // Slightly darker color for fold
        // We can't easily get "darker" from CGColor efficiently without helpers, so use a black overlay
        foldLayer.fillColor = NSColor(white: 0, alpha: 0.1).cgColor
        
        containerLayer.addSublayer(foldLayer)
        
        // --- 3. Text Layer ---
        let textLayer = CATextLayer()
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer.string = attributedString
        textLayer.isWrapped = true
        textLayer.alignmentMode = .left
        
        // Inset text
        textLayer.frame = containerLayer.bounds.insetBy(dx: textPadding, dy: textPadding)
        
        containerLayer.addSublayer(textLayer)
        
        return containerLayer
    }
    
    func rebuildLayer(_ layer: CALayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) {
        // Full rebuild for simplicity as frame and text changes affect everything
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        let newLayer = createLayer(for: stroke, in: bounds, zoom: zoom, backgroundImage: backgroundImage)
        layer.frame = newLayer.frame
        if let sublayers = newLayer.sublayers {
            for sub in sublayers {
                layer.addSublayer(sub)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatText(_ text: String?, listType: String?) -> String {
        guard let text = text, !text.isEmpty else {
            return listType == "bullet" ? "• " : (listType == "number" ? "1. " : "")
        }
        
        // Logic handled in interaction layer likely, but for display:
        // If it's just raw text, we display it.
        // If listType is set, we assume text already contains bullets or we prefix it?
        // User request says "Enter creates new bullet". This implies the underlying text string stores the bullets.
        // So here we likely just display raw text.
        return text
    }
}
