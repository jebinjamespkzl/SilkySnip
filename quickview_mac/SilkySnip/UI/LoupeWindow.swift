//
//  LoupeWindow.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Cocoa

class LoupeWindow: NSPanel {
    
    private var imageView: NSImageView!
    private var reticleOverlayView: NSView! // New
    private var maskLayer: CAShapeLayer!
    
    init() {
        // Create circular window
        let size: CGFloat = 200 // Default, can be updated
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        
        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver  // Above fullscreen apps
        self.hasShadow = true
        self.ignoresMouseEvents = true // Important: Click through
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        setupContentView()
    }
    
    private let gridLayer = CAShapeLayer()
    private let centerHighlightLayer = CAShapeLayer() // The Box
    private let crosshairLayer = CAShapeLayer()       // The Crosshair (On Top)
    
    private func setupContentView() {
        let container = NSView(frame: self.frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12 // Slightly rounded rectangle
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 3
        container.layer?.borderColor = NSColor.white.cgColor
        container.layer?.backgroundColor = NSColor.black.cgColor
        
        imageView = NSImageView(frame: container.bounds)
        imageView.imageScaling = .scaleAxesIndependently
        
        // Critical for "Pixelated" look
        imageView.layer = CALayer()
        imageView.layer?.contentsGravity = .resize
        imageView.layer?.magnificationFilter = .nearest
        
        container.addSubview(imageView)
        
        // Reticle Overlay View (Z-Order Fix: Sits ON TOP of imageView)
        let reticleView = NSView(frame: container.bounds)
        reticleView.wantsLayer = true
        container.addSubview(reticleView)
        self.reticleOverlayView = reticleView // Save reference
        
        // Grid Overlay
        gridLayer.lineWidth = 1
        gridLayer.strokeColor = NSColor.gray.withAlphaComponent(0.3).cgColor
        gridLayer.fillColor = nil
        reticleView.layer?.addSublayer(gridLayer)
        
        // Center Highlight (The Box)
        centerHighlightLayer.lineWidth = 1
        centerHighlightLayer.strokeColor = NSColor.red.cgColor
        centerHighlightLayer.fillColor = nil
        reticleView.layer?.addSublayer(centerHighlightLayer)
        
        // Crosshair (The specific required element)
        crosshairLayer.lineWidth = 1
        crosshairLayer.strokeColor = NSColor.red.cgColor
        crosshairLayer.fillColor = nil
        reticleView.layer?.addSublayer(crosshairLayer)
        
        self.contentView = container
        
        // Initial Grid Draw
        drawGrid()
    }
    
    private func drawGrid() {
        // Assuming we show roughly 15x15 pixels in the view?
        // We need to know the 'zoom' effectively.
        // Let's assume fixed grid for now, updated in updateContent if needed.
    }
    
    func updateContent(image: CGImage, from rect: CGRect) {
        if let cropped = image.cropping(to: rect) {
             imageView.layer?.contents = cropped
             let pixelCountX = rect.width
             let pixelCountY = rect.height
             drawDynamicGrid(pixelCountX: pixelCountX, pixelCountY: pixelCountY)
        }
    }
    
    /// Fixed-grid variant: always draws exactly gridSize x gridSize cells,
    /// regardless of the actual captured image dimensions.
    func updateContent(image: CGImage, gridSize: Int) {
        // Crop the image to exactly gridSize x gridSize pixels from the center
        let imgW = image.width
        let imgH = image.height
        let cropSize = min(imgW, imgH, gridSize)
        let cropRect = CGRect(
            x: (imgW - cropSize) / 2,
            y: (imgH - cropSize) / 2,
            width: cropSize,
            height: cropSize
        )
        
        if let cropped = image.cropping(to: cropRect) {
            imageView.layer?.contents = cropped
        } else {
            imageView.layer?.contents = image
        }
        
        // Always draw the grid as gridSize x gridSize
        drawDynamicGrid(pixelCountX: CGFloat(gridSize), pixelCountY: CGFloat(gridSize))
    }
    
    private func drawDynamicGrid(pixelCountX: CGFloat, pixelCountY: CGFloat) {
        // We are mapped to view size (e.g. 200x200)
        let viewWidth = self.frame.width
        let viewHeight = self.frame.height
        
        let cellWidth = viewWidth / pixelCountX
        let cellHeight = viewHeight / pixelCountY
        
        let path = CGMutablePath()
        
        // Vertical lines
        for x in 0...Int(pixelCountX) {
            let xPos = CGFloat(x) * cellWidth
            path.move(to: CGPoint(x: xPos, y: 0))
            path.addLine(to: CGPoint(x: xPos, y: viewHeight))
        }
        
        // Horizontal lines
        for y in 0...Int(pixelCountY) {
            let yPos = CGFloat(y) * cellHeight
            path.move(to: CGPoint(x: 0, y: yPos))
            path.addLine(to: CGPoint(x: viewWidth, y: yPos))
        }
        
        gridLayer.path = path
        
        // Center Highlight Reticle
        let centerX = Int(pixelCountX / 2)
        let centerY = Int(pixelCountY / 2)
        
        let originX = CGFloat(centerX) * cellWidth
        let originY = CGFloat(centerY) * cellHeight
        
        // 1. Red Square Outline
        let boxPath = CGMutablePath()
        let boxRect = CGRect(x: originX, y: originY, width: cellWidth, height: cellHeight)
        boxPath.addRect(boxRect)
        
        centerHighlightLayer.path = boxPath
        centerHighlightLayer.shadowOpacity = 0.0
        centerHighlightLayer.lineWidth = 1.0
        
        // 2. Crosshair (Extended)
        let crossPath = CGMutablePath()
        
        let midX = originX + cellWidth / 2
        let midY = originY + cellHeight / 2
        
        // Extension length: 20% beyond the cell on each side
        let extensionLen = cellWidth * 0.7 
        
        // Horizontal Line
        crossPath.move(to: CGPoint(x: midX - extensionLen, y: midY))
        crossPath.addLine(to: CGPoint(x: midX + extensionLen, y: midY))
        
        // Vertical Line
        crossPath.move(to: CGPoint(x: midX, y: midY - extensionLen))
        crossPath.addLine(to: CGPoint(x: midX, y: midY + extensionLen))
        
        crosshairLayer.path = crossPath
        crosshairLayer.shadowOpacity = 0.0
        crosshairLayer.lineWidth = 1.0
        crosshairLayer.lineCap = .butt
    }
    
    func updatePosition(center: CGPoint) {
        // Center the window on the point
        let origin = CGPoint(
            x: center.x - self.frame.width / 2,
            y: center.y - self.frame.height / 2
        )
        self.setFrameOrigin(origin)
    }
}
