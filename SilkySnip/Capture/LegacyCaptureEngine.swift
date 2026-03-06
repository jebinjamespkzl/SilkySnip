//
//  LegacyCaptureEngine.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa

class LegacyCaptureEngine {
    
    /// Captures a region using legacy CGWindowList APIs
    /// - Parameters:
    ///   - rect: The region to capture in screen coordinates
    ///   - displayID: The display to capture from (used for scale factor)
    /// - Returns: CGImage at native resolution
    static func captureRegion(_ rect: CGRect, displayID: CGDirectDisplayID) throws -> CGImage {
        Logger.shared.info("LegacyCaptureEngine.captureRegion called (Static)")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Get the screen for scale factor
        Logger.shared.info("Attempting to get screen info")
        let screens = NSScreen.screens
        
        // Safety check for displayID
        var targetScreen: NSScreen? = NSScreen.main
        for screen in screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if id == displayID {
                    targetScreen = screen
                    break
                }
            }
        }
        
        let scaleFactor = targetScreen?.backingScaleFactor ?? 1.0
        Logger.shared.info("Scale factor determined: \(scaleFactor)")
        
        // Adjust rect for retina
        let scaledRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        
        Logger.shared.info("Calling CGWindowListCreateImage with rect: \(scaledRect)")
        
        // Capture using CGWindowList
        guard let image = CGWindowListCreateImage(
            scaledRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            Logger.shared.info("CGWindowListCreateImage returned nil")
            throw CaptureError.legacyCaptureFailed
        }
        
        Logger.shared.info("CGWindowListCreateImage success. Image size: \(image.width)x\(image.height)")
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Logger.shared.info("Legacy capture completed in \(String(format: "%.1f", elapsed * 1000))ms")
        
        // Note: Do NOT re-tag color space - CGWindowListCreateImage already 
        // captures with correct colors. Re-tagging can cause color shifts/darkening.
        
        return image
    }
    
    /// Captures the entire display
    static func captureFullScreen(displayID: CGDirectDisplayID) throws -> CGImage {
        let displayBounds = CGDisplayBounds(displayID)
        return try captureRegion(displayBounds, displayID: displayID)
    }
    
    /// Gets the display ID for a given point on screen
    static func displayID(for point: CGPoint) -> CGDirectDisplayID {
        var displayID: CGDirectDisplayID = CGMainDisplayID()
        var displayCount: UInt32 = 0
        
        CGGetDisplaysWithPoint(point, 1, &displayID, &displayCount)
        
        return displayID
    }
    
    /// Gets all available display IDs
    static func getAllDisplayIDs() -> [CGDirectDisplayID] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)
        
        return Array(displayIDs.prefix(Int(displayCount)))
    }
}
