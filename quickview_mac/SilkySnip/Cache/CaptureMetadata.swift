//
//  CaptureMetadata.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Foundation
import CoreGraphics

struct CaptureMetadata: Codable {
    let id: UUID
    let captureRect: CGRect
    let displayID: UInt32
    let timestamp: Date
    var zoom: CGFloat
    var scaleFactor: CGFloat // Persist scale factor (e.g. 2.0 for Retina)
    var cropRect: CGRect?
    var annotations: [Stroke]
    
    init(
        id: UUID = UUID(),
        captureRect: CGRect,
        displayID: CGDirectDisplayID,
        timestamp: Date = Date(),
        zoom: CGFloat = 1.0,
        scaleFactor: CGFloat = 2.0, // Default to Retina for safely
        cropRect: CGRect? = nil,
        annotations: [Stroke] = []
    ) {
        self.id = id
        self.captureRect = captureRect
        self.displayID = displayID
        self.timestamp = timestamp
        self.zoom = zoom
        self.scaleFactor = scaleFactor
        self.cropRect = cropRect
        self.annotations = annotations
    }
}
