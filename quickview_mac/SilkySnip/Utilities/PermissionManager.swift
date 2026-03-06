//
//  PermissionManager.swift
//  SilkySnip
//
//  Copyright © 2026 Silky Apple Technologies. All rights reserved.
//

import Cocoa
import CoreGraphics

final class PermissionManager {
    
    static let shared = PermissionManager()
    
    private init() {}
    
    // MARK: - Quick Status Check
    
    struct PermissionStatus {
        let screenRecording: Bool
        let accessibility: Bool
        
        var allGranted: Bool {
            screenRecording && accessibility
        }
        
        /// For onboarding: only Screen Recording is truly required
        /// Accessibility detection is unreliable for ad-hoc builds but hotkeys often work anyway
        var minimumRequiredGranted: Bool {
            screenRecording
        }
    }
    
    /// Check all permissions at once and return status
    func checkAllPermissions() -> PermissionStatus {
        return PermissionStatus(
            screenRecording: hasScreenRecordingPermission(),
            accessibility: hasAccessibilityPermission()
        )
    }
    
    /// Quick check if all required permissions are granted
    /// Note: Only Screen Recording is strictly required. Accessibility detection is unreliable
    /// for ad-hoc builds but hotkeys typically work via Carbon API regardless.
    func allRequiredPermissionsGranted() -> Bool {
        return checkAllPermissions().minimumRequiredGranted
    }
    
    // MARK: - Screen Recording Permission
    
    /// Checks if the app has screen recording permission.
    func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 11.0, *) {
            // Modern, reliable way to check
            let hasAccess = CGPreflightScreenCaptureAccess()
            Logger.shared.info("Screen Recording Permission Check (macOS 11+): \(hasAccess)")
            return hasAccess
        } else {
            // Fallback for older macOS
            guard let image = CGWindowListCreateImage(
                CGRect(x: 0, y: 0, width: 1, height: 1),
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            ) else {
                return false
            }
            let hasContent = image.width > 0 && image.height > 0
            return hasContent
        }
    }
    
    /// Requests screen recording permission. Only opens Settings if not already granted.
    func requestScreenRecordingPermission() {
        // Check if we already have permission
        if hasScreenRecordingPermission() {
            Logger.shared.info("Screen recording permission already granted")
            return
        }
        
        // Trigger the system prompt
        if #available(macOS 11.0, *) {
            // This will prompt if not granted, or do nothing if already granted/denied previously
            let _ = CGRequestScreenCaptureAccess()
        }
        
        // Open settings to guide the user
        openScreenRecordingSettings()
    }
    
    func checkAndPromptForScreenRecording() {
        if hasScreenRecordingPermission() {
            Logger.shared.info("Screen recording permission verified: Authorized")
            return
        }
        
        Logger.shared.warning("Screen recording permission denied or not yet determined")
        requestScreenRecordingPermission()
    }
    
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Accessibility Permission (for global hotkeys)
    
    func hasAccessibilityPermission() -> Bool {
        // Check without prompting
        let result = AXIsProcessTrusted()
        Logger.shared.info("Accessibility Permission Check: \(result)")
        return result
    }
    
    /// Requests accessibility permission. Opens System Settings directly.
    func requestAccessibilityPermission() {
        // Trigger the system prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        
        // Open settings so user knows where to go
        openAccessibilitySettings()
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
