//
//  Constants.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Foundation
import Cocoa

enum Constants {
    
    // MARK: - App Info
    
    static let appName = "SilkySnip"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.silkysnip.app"
    
    // MARK: - Cache
    
    static let cacheDirectoryName = "Cache"
    static let cacheTTL: TimeInterval = 48 * 60 * 60  // 48 hours
    static let maxCacheSize: Int = 500_000_000  // 500 MB
    static let cacheCleanupInterval: TimeInterval = 6 * 60 * 60  // 6 hours
    
    // MARK: - Performance Targets
    
    static let captureLatencyTarget: TimeInterval = 0.150  // 150ms
    static let restoreLatencyTarget: TimeInterval = 0.100  // 100ms
    
    // MARK: - Annotation
    
    static let defaultPenColor = Theme.Colors.penDefault
    static let defaultHighlighterColor = Theme.Colors.highlighterDefault
    static let defaultHighlighterOpacity: CGFloat = 0.5
    
    static let penSizes: [CGFloat] = [2, 4, 8]  // thin, medium, thick
    // Highlighter: Small (12), Normal (18 = 1.5x), Large (24 = 2x)
    static let highlighterSizes: [CGFloat] = [12, 18, 24]
    
    static let maxUndoLevels = 20
    
    // MARK: - Zoom
    
    static let zoomLevels: [CGFloat] = [0.5, 1.0, 1.5, 2.0, 3.0]
    static let defaultZoom: CGFloat = 1.0
    
    // MARK: - Haptics
    
    struct Haptics {
        /// Subtle click feedback
        static let click: NSHapticFeedbackManager.FeedbackPattern = .alignment
        /// Success feedback
        static let success: NSHapticFeedbackManager.FeedbackPattern = .levelChange
    }
    
    // MARK: - Directories
    
    static var applicationSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(appName)
    }
    
    static var cacheURL: URL {
        applicationSupportURL.appendingPathComponent(cacheDirectoryName)
    }
    
    static var logsURL: URL {
        let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Logs").appendingPathComponent(appName)
    }

    // MARK: - Universal Shortcuts
    
    struct Shortcut {
        let key: String
        let modifiers: NSEvent.ModifierFlags
        
        // Tools
        static let pen = Shortcut(key: "p", modifiers: .control)
        static let highlighter = Shortcut(key: "h", modifiers: .control)
        static let eraser = Shortcut(key: "e", modifiers: .control)
        static let text = Shortcut(key: "t", modifiers: .control)
        static let blur = Shortcut(key: "b", modifiers: .control)
        static let crop = Shortcut(key: "x", modifiers: .control)
        static let lockDisplay = Shortcut(key: "d", modifiers: .control)
        static let move = Shortcut(key: "m", modifiers: [.control, .option])
        
        static let ghostMode = Shortcut(key: "g", modifiers: [.control, .option])
        
        // Advanced Tools
        static let stickyNote = Shortcut(key: "j", modifiers: .control)
        static let colorPicker = Shortcut(key: "i", modifiers: .control)
        static let ruler = Shortcut(key: "r", modifiers: .control)
        static let grayscale = Shortcut(key: "g", modifiers: .control)
        
        // Actions (Current)
        static let newCapture = Shortcut(key: "n", modifiers: .control)
        static let saveCurrent = Shortcut(key: "s", modifiers: .control)
        static let copyImage = Shortcut(key: "c", modifiers: .control)
        static let closeCurrent = Shortcut(key: "w", modifiers: .control)
        static let hideCurrent = Shortcut(key: "", modifiers: []) // No shortcut
        
        // Standard macOS Editing & App Lifecycle
        static let preferences = Shortcut(key: ",", modifiers: .command)
        static let hideApp = Shortcut(key: "h", modifiers: .command)
        static let hideOthers = Shortcut(key: "h", modifiers: [.command, .option])
        
        static let undo = Shortcut(key: "z", modifiers: .command)
        static let redo = Shortcut(key: "Z", modifiers: [.command, .shift])
        static let cut = Shortcut(key: "x", modifiers: .command)
        static let copy = Shortcut(key: "c", modifiers: .command)
        static let paste = Shortcut(key: "v", modifiers: .command)
        
        // Text Formatting (SilkyNotes)
        static let textBold = Shortcut(key: "b", modifiers: .command)
        static let textUnderline = Shortcut(key: "u", modifiers: .command)
        static let textStrikethrough = Shortcut(key: "x", modifiers: [.command, .shift])
        
        // Actions (Global / All)
        static let hideAll = Shortcut(key: "h", modifiers: [.control, .shift])
        static let unhideAll = Shortcut(key: " ", modifiers: [.control, .shift])
        
        static let closeAll = Shortcut(key: "w", modifiers: [.control, .shift])
        static let saveAll = Shortcut(key: "s", modifiers: [.control, .shift])
        static let restoreAll = Shortcut(key: "z", modifiers: [.control, .shift])
        
        // Backspace char for Delete
        static let clearCached = Shortcut(key: String(UnicodeScalar(8)), modifiers: [.control, .shift])
        
        static let findSilkySnips = Shortcut(key: "f", modifiers: .control)
        
        // Delayed Capture (Last Used)
        static let delayedCapture = Shortcut(key: "n", modifiers: [.control, .shift])
        
        // Quit
        static let quit = Shortcut(key: "q", modifiers: [.control, .shift])
        
        // Legacy/Other matches
        static let restoreLast = Shortcut(key: "z", modifiers: .control)
    }
}

extension Constants.Shortcut {
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += key.uppercased()
        return result
    }
}
