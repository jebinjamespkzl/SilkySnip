//
//  AnnotationTool.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import QuartzCore

/// Protocol defining the interface for all annotation tools
protocol AnnotationTool {
    /// The tool type this handler manages
    var toolType: ToolType { get }
    
    /// Creates a CALayer for rendering the given stroke
    /// - Parameters:
    ///   - stroke: The stroke data to render
    ///   - bounds: The current bounds of the annotation layer
    ///   - zoom: The current zoom level
    ///   - backgroundImage: Optional background image for tools like Blur
    /// - Returns: A configured CALayer for the stroke
    func createLayer(for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?) -> CALayer
    
    /// Rebuilds an existing layer when zoom or bounds change
    /// - Parameters:
    ///   - layer: The layer to rebuild
    ///   - stroke: The stroke data
    ///   - bounds: The new bounds
    ///   - zoom: The new zoom level
    ///   - backgroundImage: Optional background image for tools like Blur
    func rebuildLayer(_ layer: CALayer, for stroke: Stroke, in bounds: CGRect, zoom: CGFloat, backgroundImage: CGImage?)
    
    /// Converts a normalized point (0-1) to actual coordinates
    func denormalizedPoint(_ point: CGPoint, in bounds: CGRect) -> CGPoint
}

// MARK: - Default Implementation

extension AnnotationTool {
    func denormalizedPoint(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        return CGPoint(
            x: point.x * bounds.width,
            y: point.y * bounds.height
        )
    }
}

// MARK: - Tool Registry

/// Manages registration and lookup of annotation tools
class AnnotationToolRegistry {
    static let shared = AnnotationToolRegistry()
    
    private var tools: [ToolType: AnnotationTool] = [:]
    
    private init() {
        // Register all tools
        register(PenTool())
        register(HighlighterTool())
        register(EraserTool())
        register(TextTool())
        register(BlurTool())
        // StickyNoteTool removed - Sticky Notes are now floating windows via StickyNoteManager
    }
    
    func register(_ tool: AnnotationTool) {
        tools[tool.toolType] = tool
    }
    
    func tool(for type: ToolType) -> AnnotationTool? {
        return tools[type]
    }
}
