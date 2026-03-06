//
//  Stroke.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Stroke Model

struct Stroke: Codable, Identifiable, Equatable {
    let id: UUID
    var toolType: ToolType
    var points: [CGPoint]         // Normalized coordinates (0-1)
    var color: CodableColor
    var lineWidth: CGFloat        // Logical pixels
    var opacity: CGFloat
    let createdAt: Date
    
    // Text Properties
    var text: String?
    var fontName: String?
    var fontSize: CGFloat?
    var isBold: Bool?
    var isItalic: Bool?
    var isUnderline: Bool?
    var width: CGFloat?  // Text box width (logical, scaled with zoom)
    var height: CGFloat? // Text box height (logical, scaled with zoom)
    
    // Phase 2: Blur Properties
    var blurRadius: CGFloat?      // Gaussian blur radius
    var blurOpacity: CGFloat?     // Blur overlay opacity
    
    // Phase 2: Speech Bubble / Sticky Note Properties
    var tailPoint: CGPoint?       // Normalized tail anchor point
    var bubbleStyle: String?      // "round", "rectangle", "sticky"
    var listType: String?         // "none", "bullet", "number"

    
    init(
        id: UUID = UUID(),
        toolType: ToolType,
        points: [CGPoint] = [],
        color: CodableColor = CodableColor(hex: "#000000"),
        lineWidth: CGFloat = 4,
        opacity: CGFloat = 1.0
    ) {
        self.id = id
        self.toolType = toolType
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.createdAt = Date()
        
        // Text defaults
        self.text = nil
        self.fontName = nil
        self.fontSize = nil
        self.isBold = false
        self.isItalic = false
        self.isUnderline = false
    }
    
    // Text specific init
    init(
        id: UUID = UUID(),
        toolType: ToolType,
        location: CGPoint,
        color: CodableColor,
        text: String,
        fontName: String = "Helvetica",
        fontSize: CGFloat = 16,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        width: CGFloat? = nil,
        height: CGFloat? = nil
    ) {
        self.id = id
        self.toolType = toolType
        self.points = [location]
        self.color = color
        self.lineWidth = 0
        self.opacity = 1.0
        self.createdAt = Date()
        
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.width = width
        self.height = height
    }
    
    mutating func addPoint(_ point: CGPoint) {
        points.append(point)
    }
}

// MARK: - Tool Types

enum ToolType: String, Codable, CaseIterable {
    case pen
    case highlighter
    case eraser
    case text
    case blur           // Phase 2: Blur sensitive areas
    case stickyNote     // Sticky Notes (was speechBubble)
    case crop           // Action: Crop Mode
    
    var defaultColor: CodableColor {
        switch self {
        case .pen:
            return CodableColor(hex: Constants.defaultPenColor)
        case .highlighter:
            return CodableColor(hex: Constants.defaultHighlighterColor)
        case .eraser:
            return CodableColor(hex: "#000000")
        case .text:
            return CodableColor(hex: "#000000")
        case .blur:
            return CodableColor(hex: "#888888")
        case .stickyNote:
            return CodableColor(hex: "#FFEB3B") // Yellow default for sticky note
        case .crop:
            return CodableColor(hex: "#000000") // Not used for crop
        }
    }
    
    var defaultLineWidth: CGFloat {
        switch self {
        case .pen:
            return Constants.penSizes[1]  // Medium
        case .highlighter:
            return Constants.highlighterSizes[1]  // Medium
        case .eraser:
            return 20
        case .text:
            return 0
        case .blur:
            return 10  // Default blur radius
        case .stickyNote:
            return 0   // No border width by default for sticky note logic, or use 1
        case .crop:
            return 1
        }
    }
    
    // Helper to identify if tool is additive (draws stroke)
    var isDrawingTool: Bool {
        return self != .crop
    }
    
    var defaultOpacity: CGFloat {
        switch self {
        case .pen:
            return 1.0
        case .highlighter:
            return Constants.defaultHighlighterOpacity
        case .eraser:
            return 1.0
        case .text:
            return 1.0
        case .blur:
            return 1.0
        case .stickyNote:
            return 1.0
        case .crop:
            return 1.0
        }
    }
}

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
    
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        self.red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        self.green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        self.blue = CGFloat(rgb & 0x0000FF) / 255.0
        self.alpha = 1.0
    }
    
    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    var hexString: String {
        String(format: "#%02X%02X%02X",
               Int(red * 255),
               Int(green * 255),
               Int(blue * 255))
    }
}
