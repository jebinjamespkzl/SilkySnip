//
//  Theme.swift
//  SilkySnip
//
//  Copyright © 2026 Silky Apple Technologies. All rights reserved.
//

import Cocoa

struct Theme {
    
    // MARK: - Colors
    
    struct Colors {
        // Standard Palette
        static let black = "#000000"
        static let white = "#FFFFFF"
        static let red = "#FF3B30"
        static let blue = "#007AFF"
        static let green = "#34C759"
        static let orange = "#FF9500"
        static let yellow = "#FFFF00"
        static let pink = "#FF69B4"
        static let cyan = "#00FFFF"
        static let purple = "#AF52DE"
        
        // Semantic aliases
        static let penDefault = black
        static let highlighterDefault = yellow
    }
    
    // MARK: - Typography
    
    struct Fonts {
        // We use system fonts to match macOS Human Interface Guidelines
        
        /// Hero title, used in About/Welcome screens (Size: 24, Bold)
        static let heroTitle = NSFont.systemFont(ofSize: 24, weight: .bold)
        
        /// Large text (Size: 19)
        static let large = NSFont.systemFont(ofSize: 19)
        
        /// Standard body text (Size: 15)
        static let body = NSFont.systemFont(ofSize: 15)
        
        /// Secondary label / Version info (Size: 13)
        static let secondaryLabel = NSFont.systemFont(ofSize: 13, weight: .regular)
        
        /// Small text / Captions (Size: 11)
        static let caption = NSFont.systemFont(ofSize: 11)
        
        /// Welcome Screen Title (Size: 26, Bold)
        static let welcomeTitle = NSFont.systemFont(ofSize: 26, weight: .bold)
        
        /// Features List Title (Size: 13, Semibold)
        static let featureTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        
        /// Legal text (Size: 10)
        static let legal = NSFont.systemFont(ofSize: 10)
    }
    
    // MARK: - Layout
    
    struct Layout {
        /// Standard small spacing (8-10px)
        static let small: CGFloat = 10
        
        /// Standard medium spacing (20px)
        static let medium: CGFloat = 20
        
        /// Large spacing (40px)
        static let large: CGFloat = 40
        
        /// Icon size for About/Welcome windows (128x128)
        static let largeIconSize: CGFloat = 128
    }
}
