//
//  NeonFeedbackLayer.swift
//  SilkySnip
//
//  Centralized neon border glow feedback for Save, Copy, and Find operations.
//  Directly manipulates the host layer's border properties for maximum reliability.
//

import AppKit
import QuartzCore

class NeonFeedbackLayer {
    
    private static let feedbackLayerName = "NeonFeedbackBorder"
    
    // Store original border state so we can restore it
    private static var savedBorderWidth: CGFloat = 0
    private static var savedBorderColor: CGColor?
    
    /// Shows a neon highlight border on the given view by directly setting
    /// the layer's borderWidth and borderColor. This is the same technique
    /// used by setSavingHighlight which is known to work reliably.
    static func show(on view: NSView, color: NSColor? = nil, borderWidth: CGFloat = 6) {
        guard let layer = view.layer else { return }
        
        // Save current border values so we can restore later
        savedBorderWidth = layer.borderWidth
        savedBorderColor = layer.borderColor
        
        let highlightColor = color ?? resolveHighlightColor(for: view)
        
        // Directly set on the host layer — guaranteed visible
        layer.borderWidth = borderWidth
        layer.borderColor = highlightColor.cgColor
    }
    
    /// Removes the neon highlight and restores the original border state.
    static func hide(from view: NSView) {
        guard let layer = view.layer else { return }
        
        // Restore original border
        layer.borderWidth = savedBorderWidth
        layer.borderColor = savedBorderColor
    }
    
    /// Shows a neon highlight that auto-dismisses after the specified duration.
    /// Uses direct layer border manipulation (no sublayers) for reliability.
    static func flash(on view: NSView, color: NSColor? = nil, duration: TimeInterval = 1.0, borderWidth: CGFloat = 6) {
        show(on: view, color: color, borderWidth: borderWidth)
        
        // Auto-hide after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            hide(from: view)
        }
    }
    
    /// Resolves the appropriate highlight color.
    /// Uses OverlayWindow's determineHighlightColor() if available, otherwise systemRed.
    private static func resolveHighlightColor(for view: NSView) -> NSColor {
        if let overlay = view.window as? OverlayWindow {
            return overlay.determineHighlightColor()
        }
        return NSColor.systemRed
    }
}
