//
//  Extensions.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa

// MARK: - NSImage Extensions

extension NSImage {
    /// Creates a CGImage from the NSImage
    func cgImage(forProposedRect proposedRect: UnsafeMutablePointer<NSRect>?, context: NSGraphicsContext?, hints: [NSImageRep.HintKey: Any]?) -> CGImage? {
        guard let imageData = tiffRepresentation,
              let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }
}

// MARK: - NSColor Extensions

extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        
        let red = Int(rgbColor.redComponent * 255)
        let green = Int(rgbColor.greenComponent * 255)
        let blue = Int(rgbColor.blueComponent * 255)
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// MARK: - CGRect Extensions

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
    
    func scaled(by factor: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: origin.y,
            width: width * factor,
            height: height * factor
        )
    }
}

// MARK: - Date Extensions

extension Date {
    private static let sharedISO8601Formatter = ISO8601DateFormatter()
    
    var iso8601String: String {
        Date.sharedISO8601Formatter.string(from: self)
    }
    
    var filenameSafeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: self)
    }
}

// MARK: - FileManager Extensions

extension FileManager {
    func sizeOfDirectory(at url: URL) -> Int64 {
        var totalSize: Int64 = 0
        
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        
        return totalSize
    }
}
