//
//  CaptureEngine.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa


class CaptureEngine {
    
    // MARK: - Public Methods
    
    /// Captures a region of the specified display
    /// - Parameters:
    ///   - rect: The region to capture in screen coordinates
    ///   - displayID: The display to capture from
    /// - Returns: CGImage at native resolution (retina-aware)
    func captureRegion(_ rect: CGRect, displayID: CGDirectDisplayID) async throws -> CGImage {
        Logger.shared.info("CaptureEngine.captureRegion called")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use legacy capture directly - it doesn't trigger permission popups
        // SCShareableContent.excludingDesktopWindows() triggers permission dialogs
        // so we avoid using it for the capture operation
        Logger.shared.info("Using LegacyCaptureEngine (Static)")
        let image = try LegacyCaptureEngine.captureRegion(rect, displayID: displayID)
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Logger.shared.info("Capture completed in \(String(format: "%.1f", elapsed * 1000))ms")
        
        return image
    }
    
    /// Captures the entire display
    func captureFullScreen(displayID: CGDirectDisplayID) async throws -> CGImage {
        let displayBounds = CGDisplayBounds(displayID)
        return try await captureRegion(displayBounds, displayID: displayID)
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case displayNotFound
    case permissionDenied
    case captureFailedUnknown
    case legacyCaptureFailed
    
    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "The target display was not found."
        case .permissionDenied:
            return "Screen recording permission is required."
        case .captureFailedUnknown:
            return "Screen capture failed for an unknown reason."
        case .legacyCaptureFailed:
            return "Legacy screen capture failed."
        }
    }
}
