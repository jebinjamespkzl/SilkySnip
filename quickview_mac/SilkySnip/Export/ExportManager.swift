//
//  ExportManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa

class ExportManager {
    
    static let shared = ExportManager()
    
    private init() {}
    
    // MARK: - Save
    
    // MARK: - Save & Copy
    
    func saveOverlay(_ overlay: OverlayWindow, completion: ((Bool) -> Void)? = nil) {
        let savePanel = NSSavePanel()
        
        // Generate default filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let defaultName = "SilkySnip-\(timestamp)"
        
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [.png, .jpeg, .tiff, .pdf]
        savePanel.allowsOtherFileTypes = false
        savePanel.canCreateDirectories = true
        savePanel.title = LanguageManager.shared.string("title_save_screenshot")
        savePanel.message = LanguageManager.shared.string("msg_save_location")
        
        // Add format accessory view
        let accessoryView = createFormatAccessoryView(savePanel: savePanel)
        savePanel.accessoryView = accessoryView
        
        // Highlight the window being saved
        overlay.setSavingHighlight(true)
        
        // Fix Z-index: Elevate the save panel above the overlay window 
        // instead of lowering the overlay behind other desktop applications.
        savePanel.level = NSWindow.Level(rawValue: overlay.level.rawValue + 1)
        
        savePanel.begin { [weak self] response in
            
            // Remove highlight
            overlay.setSavingHighlight(false)
            
            let saved = (response == .OK)
            if saved, let url = savePanel.url {
                 // Ensure crop handles are hidden before export
                 overlay.endCropMode()
                 let captured = overlay.capturedImage
                 let annotations = overlay.metadata.annotations
                 
                 DispatchQueue.global(qos: .userInitiated).async {
                     self?.exportToFile(capturedImage: captured, annotations: annotations, url: url) { success in
                         DispatchQueue.main.async {
                             completion?(success)
                         }
                     }
                 }
            } else {
                 // Call completion with result immediately if cancelled
                 completion?(saved)
            }
        }
    }
    
    func copyOverlayToClipboard(_ overlay: OverlayWindow) {
        // Ensure crop handles are hidden before copy
        overlay.endCropMode()
        
        let captured = overlay.capturedImage
        let annotations = overlay.metadata.annotations
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let flattenedImage = self?.flattenOverlay(capturedImage: captured, annotations: annotations) else {
                DispatchQueue.main.async {
                    self?.showExportError(LanguageManager.shared.string("err_clipboard_image"))
                }
                return
            }
            
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([flattenedImage])
                // overlay.showCopiedFeedback is handled upstream
            }
        }
    }
    
    func autoSaveOverlay(_ overlay: OverlayWindow) {
        let savePath = UserDefaults.standard.string(forKey: "AutoSavePath") ?? NSHomeDirectory().appending("/Documents")
        let url = URL(fileURLWithPath: savePath)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        
        let formatExtension = UserDefaults.standard.string(forKey: "AutoSaveFormat") ?? "png"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "SilkySnip-\(timestamp).\(formatExtension)"
        
        let fileURL = url.appendingPathComponent(filename)
        let captured = overlay.capturedImage
        let annotations = overlay.metadata.annotations
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.exportToFile(capturedImage: captured, annotations: annotations, url: fileURL, completion: nil)
        }
    }
    
    // MARK: - Export
    
    private func exportToFile(capturedImage: CGImage, annotations: [Stroke], url: URL, completion: ((Bool) -> Void)? = nil) {
        // Flatten the image with annotations
        guard let flattenedImage = flattenOverlay(capturedImage: capturedImage, annotations: annotations) else {
            DispatchQueue.main.async {
                self.showExportError(LanguageManager.shared.string("err_create_image"))
                completion?(false)
            }
            return
        }
        
        let pathExtension = url.pathExtension.lowercased()
        
        if pathExtension == "pdf" {
            // PDF Export
            let pdfData = NSMutableData()
            
            // Create PDF Context
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
                DispatchQueue.main.async { self.showExportError(LanguageManager.shared.string("err_pdf_consumer")); completion?(false) }
                return
            }
            
            var mediaBox = CGRect(origin: .zero, size: flattenedImage.size)
            
            guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                DispatchQueue.main.async { self.showExportError(LanguageManager.shared.string("err_pdf_context")); completion?(false) }
                return
            }
            
            pdfContext.beginPDFPage(nil)
            
            // Draw image into PDF
            if let cgImage = flattenedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                pdfContext.draw(cgImage, in: mediaBox)
            }
            
            pdfContext.endPDFPage()
            pdfContext.closePDF()
            
            // Save
            do {
                try pdfData.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    Logger.shared.info("Saved PDF to: \(url.path)")
                    NSSound(named: "Glass")?.play()
                    completion?(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showExportError(String(format: "%@: %@", LanguageManager.shared.string("err_save_pdf"), error.localizedDescription))
                    completion?(false)
                }
            }
            
        } else {
            // Image Export
            // Determine format from extension
            let format: NSBitmapImageRep.FileType
            switch pathExtension {
            case "jpg", "jpeg":
                format = .jpeg
            case "tiff", "tif":
                format = .tiff
            default:
                format = .png
            }
            
            // Save to file
            guard let data = imageData(from: flattenedImage, format: format) else {
                DispatchQueue.main.async { self.showExportError(LanguageManager.shared.string("err_encode_image")); completion?(false) }
                return
            }
            
            do {
                try data.write(to: url)
                DispatchQueue.main.async {
                    Logger.shared.info("Saved screenshot to: \(url.path)")
                    NSSound(named: "Glass")?.play()
                    completion?(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showExportError(String(format: "%@: %@", LanguageManager.shared.string("err_save"), error.localizedDescription))
                    completion?(false)
                }
            }
        }
    }
    
    private func flattenOverlay(capturedImage: CGImage, annotations: [Stroke]) -> NSImage? {
        // Get original image size
        let imageSize = NSSize(
            width: capturedImage.width,
            height: capturedImage.height
        )
        
        // Create composite image
        let image = NSImage(size: imageSize)
        
        image.lockFocus()
        
        // Draw background image
        let nsImage = NSImage(cgImage: capturedImage, size: imageSize)
        nsImage.draw(in: NSRect(origin: .zero, size: imageSize))
        
        // Draw annotations
        // Get the annotation layer and render it
        if let context = NSGraphicsContext.current?.cgContext {
            // Scale annotations from normalized to image coordinates
            for stroke in annotations {
                drawStroke(stroke, in: context, size: imageSize)
            }
        }
        
        image.unlockFocus()
        
        return image
    }
    
    private func drawStroke(_ stroke: Stroke, in context: CGContext, size: NSSize) {
        // Convert normalized points to image coordinates
        let points = stroke.points.map { point in
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }
        
        guard points.count > 0 else { return }
        
        context.saveGState()
        
        // Set stroke properties
        context.setStrokeColor(stroke.color.cgColor)
        context.setLineWidth(stroke.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setAlpha(stroke.opacity)
        
        // Apply blend mode for highlighter
        if stroke.toolType == .highlighter {
            context.setBlendMode(.multiply)
        }
        
        // Draw path
        context.move(to: points[0])
        
        if points.count == 1 {
            // Single dot
            let rect = CGRect(
                x: points[0].x - stroke.lineWidth / 2,
                y: points[0].y - stroke.lineWidth / 2,
                width: stroke.lineWidth,
                height: stroke.lineWidth
            )
            context.fillEllipse(in: rect)
        } else {
            // Draw smooth path
            for i in 1..<points.count {
                let midPoint = CGPoint(
                    x: (points[i - 1].x + points[i].x) / 2,
                    y: (points[i - 1].y + points[i].y) / 2
                )
                context.addQuadCurve(to: midPoint, control: points[i - 1])
            }
            context.addLine(to: points.last ?? points[0])
            context.strokePath()
        }
        
        context.restoreGState()
    }
    
    private func imageData(from image: NSImage, format: NSBitmapImageRep.FileType) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        
        if format == .jpeg {
            properties[.compressionFactor] = 0.9  // High quality JPEG
        }
        
        return bitmapRep.representation(using: format, properties: properties)
    }
    
    // MARK: - Accessory View
    
    private weak var currentSavePanel: NSSavePanel?
    
    private func createFormatAccessoryView(savePanel: NSSavePanel) -> NSView {
        // Store reference to update extension
        self.currentSavePanel = savePanel
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        
        // Dynamically insert the colon
        let labelText = String(format: "%@:", LanguageManager.shared.string("label_format"))
        let label = NSTextField(labelWithString: labelText)
        label.frame = NSRect(x: 10, y: 10, width: 50, height: 20)
        
        let popup = NSPopUpButton(frame: NSRect(x: 65, y: 7, width: 140, height: 26))
        popup.addItems(withTitles: [
            LanguageManager.shared.string("format_png_default"),
            LanguageManager.shared.string("format_jpg_compact"),
            LanguageManager.shared.string("format_tiff_high_quality"),
            LanguageManager.shared.string("format_pdf_document")
        ])
        popup.selectItem(at: 0)
        
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        
        containerView.addSubview(label)
        containerView.addSubview(popup)
        
        return containerView
    }
    
    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let savePanel = currentSavePanel else { return }
        
        // Get the current filename without extension
        let currentName = savePanel.nameFieldStringValue
        let baseName = (currentName as NSString).deletingPathExtension
        
        // Update extension based on selection
        let newExtension: String
        switch sender.indexOfSelectedItem {
        case 0:
            newExtension = "png"
            savePanel.allowedContentTypes = [.png]
        case 1:
            newExtension = "jpg"
            savePanel.allowedContentTypes = [.jpeg]
        case 2:
            newExtension = "tiff"
            savePanel.allowedContentTypes = [.tiff]
        case 3:
            newExtension = "pdf"
            savePanel.allowedContentTypes = [.pdf]
        default:
            newExtension = "png"
            savePanel.allowedContentTypes = [.png]
        }
        
        // Update the filename with new extension
        savePanel.nameFieldStringValue = baseName + "." + newExtension
    }
    
    // MARK: - Error Handling
    
    private func showExportError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.string("title_export_failed")
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: LanguageManager.shared.string("ok"))
        alert.runModal()
    }
}
