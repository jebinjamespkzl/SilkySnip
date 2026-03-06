//
//  TextTool.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import QuartzCore

/// Handles text annotation rendering
struct TextTool: AnnotationTool {
    let toolType: ToolType = .text
    
    func createLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) -> CALayer {
        let textLayer = CATextLayer()
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        let normalizedPoint = stroke.points.first ?? .zero
        let point = denormalizedPoint(normalizedPoint, in: bounds)
        
        // Configure font
        let fontSize = (stroke.fontSize ?? 24) * zoom
        let fontName = stroke.fontName ?? "Helvetica"
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        
        if stroke.isBold == true {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if stroke.isItalic == true {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        
        // Create attributed string to support underline and color
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: stroke.color.nsColor,
            .underlineStyle: (stroke.isUnderline == true) ? NSUnderlineStyle.single.rawValue : 0
        ]
        
        let attributedString = NSAttributedString(string: stroke.text ?? "", attributes: attributes)
        textLayer.string = attributedString
        
        // Calculate size and frame
        var size = attributedString.size()
        
        if let strokeWidth = stroke.width {
            let width = strokeWidth * zoom
            var height: CGFloat
            
            if let strokeHeight = stroke.height {
                height = strokeHeight * zoom
            } else {
                // Calculate height based on text wrapping
                let constraintSize = CGSize(width: width, height: .greatestFiniteMagnitude)
                let context = NSStringDrawingContext()
                let rect = attributedString.boundingRect(with: constraintSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: context)
                height = ceil(rect.height + 5)
            }
            
            size = CGSize(width: width, height: height)
            textLayer.isWrapped = true
        } else {
            // Add slight padding even for unwrapped to avoid clipping edges of italic text
            size.width += 5
            size.height += 2
        }
        
        // Set frame
        textLayer.frame = CGRect(origin: point, size: size)
        
        return textLayer
    }
    
    func rebuildLayer(_ layer: CALayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) {
        guard let textLayer = layer as? CATextLayer else { return }
        
        let point = denormalizedPoint(stroke.points.first ?? .zero, in: bounds)
        let fontSize = (stroke.fontSize ?? 24) * zoom
        
        // Rebuild attributed string with new font size
        let fontName = stroke.fontName ?? "Helvetica"
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        
        if stroke.isBold == true {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if stroke.isItalic == true {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: stroke.color.nsColor,
            .underlineStyle: (stroke.isUnderline == true) ? NSUnderlineStyle.single.rawValue : 0
        ]
        
        let attributedString = NSAttributedString(string: stroke.text ?? "", attributes: attributes)
        textLayer.string = attributedString
        let size = attributedString.size()
        textLayer.frame = CGRect(origin: point, size: size)
    }
}
