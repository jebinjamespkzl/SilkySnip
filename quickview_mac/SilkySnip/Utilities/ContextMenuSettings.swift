//
//  ContextMenuSettings.swift
//  SilkySnip
//
//  Manages visibility settings for advanced context menu tools.
//

import Foundation

/// Manages which advanced tools are visible in the context menu.
/// Users can toggle these in Settings to customize their workflow.
class ContextMenuSettings {
    static let shared = ContextMenuSettings()
    
    // MARK: - Keys
    private let kShowSpeechBubble = "ShowTool_SpeechBubble"
    private let kShowMagnify = "ShowTool_Magnify"
    private let kShowFilters = "ShowTool_Filters"
    private let kShowRulers = "ShowTool_Rulers"
    private let kShowColorPicker = "ShowTool_ColorPicker"
    private let kShowGhostMode = "ShowTool_GhostMode"
    private let kShowNeonBorder = "ShowTool_NeonBorder"
    
    private let defaults = UserDefaults.standard
    
    private init() {
        // Set defaults for first launch - all advanced tools hidden by default
        registerDefaults()
    }
    
    private func registerDefaults() {
        defaults.register(defaults: [
            kShowSpeechBubble: false,
            kShowMagnify: false,
            kShowFilters: false,
            kShowRulers: false,
            kShowColorPicker: false,
            kShowGhostMode: false,
            kShowNeonBorder: false
        ])
    }
    
    // MARK: - Tool Visibility Properties
    
    var showSpeechBubble: Bool {
        get { defaults.bool(forKey: kShowSpeechBubble) }
        set { defaults.set(newValue, forKey: kShowSpeechBubble) }
    }
    
    var showMagnify: Bool {
        get { defaults.bool(forKey: kShowMagnify) }
        set { defaults.set(newValue, forKey: kShowMagnify) }
    }
    
    var showFilters: Bool {
        get { defaults.bool(forKey: kShowFilters) }
        set { defaults.set(newValue, forKey: kShowFilters) }
    }
    
    var showRulers: Bool {
        get { defaults.bool(forKey: kShowRulers) }
        set { defaults.set(newValue, forKey: kShowRulers) }
    }
    
    var showColorPicker: Bool {
        get { defaults.bool(forKey: kShowColorPicker) }
        set { defaults.set(newValue, forKey: kShowColorPicker) }
    }
    
    var showGhostMode: Bool {
        get { defaults.bool(forKey: kShowGhostMode) }
        set { defaults.set(newValue, forKey: kShowGhostMode) }
    }
    
    var showNeonBorder: Bool {
        get { defaults.bool(forKey: kShowNeonBorder) }
        set { defaults.set(newValue, forKey: kShowNeonBorder) }
    }
}
