//
//  TextSelectionOverlay.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Cocoa
import Vision

/// Represents a recognized text region with its bounding box
struct TextRegion {
    let text: String
    let boundingBox: CGRect  // Normalized coordinates (0-1)
    var isSelected: Bool = false
    var detectedData: (type: NSTextCheckingResult.CheckingType, url: URL?)? // Data Detector result
}

/// Overlay view that displays recognized text regions and allows selection
class TextSelectionOverlay: NSView, NSDraggingSource, NSPasteboardItemDataProvider {
    
    // MARK: - Properties
    
    private var textRegions: [TextRegion] = []
    private var imageSize: CGSize = .zero
    private var onComplete: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    
    // Selection state
    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var dragCurrentPoint: CGPoint = .zero
    
    // Toolbar
    private var toolbarWindow: NSPanel?
    private var toolbarView: NSView?
    
    // UI Elements (Keep references for updates)
    private var copyButton: NSButton!
    private var openButton: NSButton! // New
    private var cancelButton: NSButton!
    private var selectAllButton: NSButton!
    private var statusLabel: NSTextField!
    
    // MARK: - Initialization
    
    init(frame: CGRect, image: CGImage, onComplete: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.imageSize = CGSize(width: image.width, height: image.height)
        self.onComplete = onComplete
        self.onCancel = onCancel
        
        super.init(frame: frame)
        
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        
        setupToolbar()
        recognizeText(from: image)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        toolbarWindow?.close()
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            toolbarWindow?.close()
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window, let _ = toolbarWindow {
            // Position external toolbar relative to window
            updateToolbarPosition()
            
            // Observe window movement to update toolbar
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove), name: NSWindow.didMoveNotification, object: window)
        }
    }
    
    @objc private func windowDidMove() {
        updateToolbarPosition()
    }
    
    private func updateToolbarPosition() {
        guard let window = window, let toolbarWindow = toolbarWindow else { return }
        
        // Center horizontally, place below the window
        let windowFrame = window.frame
        let toolbarSize = toolbarWindow.frame.size
        
        let x = windowFrame.midX - (toolbarSize.width / 2)
        var y = windowFrame.minY - toolbarSize.height - 10
        
        // If almost off screen at bottom, place above
        if y < 50 {
             y = windowFrame.maxY + 10
        }
        
        toolbarWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - Setup
    
    private func setupToolbar() {
        if bounds.width < 360 {
            setupExternalToolbar()
        } else {
            setupInternalToolbar()
        }
    }
    
    private func createToolbarContent() -> NSView {
        let width: CGFloat = 340
        let height: CGFloat = 44
        let lm = LanguageManager.shared
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        container.layer?.cornerRadius = 10
        
        // Status label
        statusLabel = NSTextField(labelWithString: lm.string("status_click_select"))
        statusLabel.frame = NSRect(x: 10, y: height - 20, width: width - 20, height: 16)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.drawsBackground = false
        statusLabel.isBordered = false
        statusLabel.isEditable = false
        container.addSubview(statusLabel)
        
        // Select All button
        selectAllButton = NSButton(title: lm.string("btn_select_all"), target: self, action: #selector(selectAllRegions))
        selectAllButton.frame = NSRect(x: 10, y: 6, width: 80, height: 24)
        selectAllButton.bezelStyle = .rounded
        container.addSubview(selectAllButton)
        
        // Open button (Hidden by default)
        openButton = NSButton(title: lm.string("btn_open"), target: self, action: #selector(openSelectedData))
        openButton.frame = NSRect(x: 100, y: 6, width: 60, height: 24)
        openButton.bezelStyle = .rounded
        openButton.isEnabled = false
        openButton.isHidden = true
        container.addSubview(openButton)
        
        // Cancel button
        cancelButton = NSButton(title: lm.string("btn_cancel"), target: self, action: #selector(cancelSelection))
        cancelButton.frame = NSRect(x: 170, y: 6, width: 60, height: 24) // Shifted right
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        container.addSubview(cancelButton)
        
        // Copy button
        copyButton = NSButton(title: lm.string("btn_copy"), target: self, action: #selector(copySelected))
        copyButton.frame = NSRect(x: 235, y: 6, width: 50, height: 24) // Shifted right
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        container.addSubview(copyButton)
        
        // Clear button
        let clearButton = NSButton(title: lm.string("btn_clear"), target: self, action: #selector(clearSelection))
        clearButton.frame = NSRect(x: 290, y: 6, width: 45, height: 24) // Shifted right
        clearButton.bezelStyle = .rounded
        container.addSubview(clearButton)
        
        return container
    }
    
    private func setupInternalToolbar() {
        let toolbar = createToolbarContent()
        
        // Center horizontally, near top
        let toolbarX = (bounds.width - toolbar.frame.width) / 2
        let toolbarY: CGFloat = 10
        toolbar.frame.origin = CGPoint(x: toolbarX, y: toolbarY)
        toolbar.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        
        addSubview(toolbar)
        self.toolbarView = toolbar
    }
    
    private func setupExternalToolbar() {
        let toolbarContentView = createToolbarContent()
        
        let panel = NSPanel(
            contentRect: toolbarContentView.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = toolbarContentView
        panel.orderFront(nil)
        
        self.toolbarWindow = panel
    }
    
    // MARK: - OCR
    
    private func recognizeText(from image: CGImage) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("OCR Error: \(error)")
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            // Convert observations to text regions
            DispatchQueue.main.async {
                // Initialize detector
                let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.date.rawValue)
                
                self.textRegions = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string
                    
                    var detectedData: (type: NSTextCheckingResult.CheckingType, url: URL?)? = nil
                    
                    if let detector = detector {
                        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                        if let match = matches.first {
                            detectedData = (type: match.resultType, url: match.url)
                            // If phone, construct tel URL
                            if match.resultType == .phoneNumber, let phone = match.phoneNumber {
                                if let url = URL(string: "tel://\(phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")") {
                                    detectedData = (type: .phoneNumber, url: url)
                                }
                            }
                        }
                    }
                    
                    return TextRegion(
                        text: text,
                        boundingBox: observation.boundingBox,
                        isSelected: false,
                        detectedData: detectedData
                    )
                }
                
                self.updateStatus()
                self.needsDisplay = true
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
        }
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw text regions
        for region in textRegions {
            let rect = convertNormalizedRect(region.boundingBox)
            
            // Background
            if region.isSelected {
                context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.3).cgColor)
                context.fill(rect)
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(2)
            } else if region.detectedData != nil {
                // Data detected (Link/Phone) - Highlight differently
                context.setFillColor(NSColor.systemGreen.withAlphaComponent(0.15).cgColor)
                context.fill(rect)
                context.setStrokeColor(NSColor.systemGreen.withAlphaComponent(0.6).cgColor)
                context.setLineWidth(1)
                // Optional: Draw underline?
            } else {
                context.setFillColor(NSColor.white.withAlphaComponent(0.1).cgColor)
                context.fill(rect)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
                context.setLineWidth(1)
            }
            
            context.stroke(rect)
        }
        
        // Draw drag selection rectangle
        if isDragging {
            let selectionRect = NSRect(
                x: min(dragStartPoint.x, dragCurrentPoint.x),
                y: min(dragStartPoint.y, dragCurrentPoint.y),
                width: abs(dragCurrentPoint.x - dragStartPoint.x),
                height: abs(dragCurrentPoint.y - dragStartPoint.y)
            )
            
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.2).cgColor)
            context.fill(selectionRect)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(selectionRect)
        }
    }
    
    private func convertNormalizedRect(_ normalized: CGRect) -> CGRect {
        // Vision uses bottom-left origin, convert to view coordinates
        let x = normalized.origin.x * bounds.width
        let y = normalized.origin.y * bounds.height
        let width = normalized.width * bounds.width
        let height = normalized.height * bounds.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check if clicking on a text region
        var clickedRegion = false
        for i in 0..<textRegions.count {
            let rect = convertNormalizedRect(textRegions[i].boundingBox)
            if rect.contains(point) {
                clickedRegion = true
                
                // If checking an already selected region, don't deselect yet - wait for drag or mouseUp
                if textRegions[i].isSelected {
                    potentialDrag = true
                    dragStartPoint = point
                    // Don't change selection yet
                    
                    // But if modifier is held (Command), we usually toggle immediately on click
                    if event.modifierFlags.contains(.command) {
                        textRegions[i].isSelected.toggle()
                        potentialDrag = false // Cannot drag if we just deselected it
                    }
                } else {
                    // Clicking unselected region
                    if event.modifierFlags.contains(.command) {
                        textRegions[i].isSelected.toggle()
                    } else {
                        // Clear others and select this one
                        for j in 0..<textRegions.count {
                            textRegions[j].isSelected = (j == i)
                        }
                    }
                    // Start immediate drag for this newly selected item?
                    // Typically not standard, but let's allow "pick up"
                    // potentialDrag = true
                    // dragStartPoint = point
                }
                break
            }
        }
        
        // If not clicking on a region, start drag selection
        if !clickedRegion {
            isDragging = true
            dragStartPoint = point
            dragCurrentPoint = point
            
            // Clear selection if not holding Command
            if !event.modifierFlags.contains(.command) {
                for i in 0..<textRegions.count {
                    textRegions[i].isSelected = false
                }
            }
        }
        
        updateStatus()
        needsDisplay = true
    }
    
    // MARK: - Drag & Drop Support
    
    private var potentialDrag = false
    
    override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)
        
        // Checklist for Data Drag:
        // 1. MouseDown was on a selected region (potentialDrag = true)
        // 2. We moved enough to count as a drag
        // 3. We are not currently rectangle-selecting (isDragging = false)
        if potentialDrag && !isDragging {
            let distance = hypot(currentPoint.x - dragStartPoint.x, currentPoint.y - dragStartPoint.y)
            if distance > 5 {
                startDragSession(with: event)
                return
            }
        }
        
        if isDragging {
            dragCurrentPoint = currentPoint
            
            // Select regions that intersect with drag rectangle
            let selectionRect = NSRect(
                x: min(dragStartPoint.x, dragCurrentPoint.x),
                y: min(dragStartPoint.y, dragCurrentPoint.y),
                width: abs(dragCurrentPoint.x - dragStartPoint.x),
                height: abs(dragCurrentPoint.y - dragStartPoint.y)
            )
            
            for i in 0..<textRegions.count {
                let rect = convertNormalizedRect(textRegions[i].boundingBox)
                textRegions[i].isSelected = selectionRect.intersects(rect)
            }
            
            updateStatus()
            needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        // If we were ready to drag but didn't drag, treat as a click on selected item
        if potentialDrag {
             // If modifiers are not held, click on selected item should leave ONLY that item selected
             if !event.modifierFlags.contains(.command) {
                 let point = convert(event.locationInWindow, from: nil)
                 for i in 0..<textRegions.count {
                     let rect = convertNormalizedRect(textRegions[i].boundingBox)
                     if rect.contains(point) {
                         // Select only this one
                         for j in 0..<textRegions.count {
                             textRegions[j].isSelected = (i == j)
                         }
                         break
                     }
                 }
                 needsDisplay = true
                 updateStatus()
             }
        }
        
        isDragging = false
        potentialDrag = false
        
        updateStatus()
        needsDisplay = true
    }
    
    private func startDragSession(with event: NSEvent) {
        potentialDrag = false // Consumed
        
        let selectedRegions = textRegions.filter { $0.isSelected }
        guard !selectedRegions.isEmpty else { return }
        
        let item = NSPasteboardItem()
        item.setDataProvider(self, forTypes: [.string])
        
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        
        // Calculate frame for drag image (union of selected regions)
        var unionRect: CGRect?
        for region in selectedRegions {
            let rect = convertNormalizedRect(region.boundingBox)
            if unionRect == nil {
                unionRect = rect
            } else {
                unionRect = unionRect?.union(rect)
            }
        }
        
        let dragFrame = unionRect ?? NSRect(origin: dragStartPoint, size: CGSize(width: 100, height: 20))
        
        // Create drag snapshot? For text, standard system drag often just shows cursor or text image.
        // We can capture the view content in that rect.
        let imageRep = bitmapImageRepForCachingDisplay(in: dragFrame)!
        cacheDisplay(in: dragFrame, to: imageRep)
        let dragImage = NSImage(size: dragFrame.size)
        dragImage.addRepresentation(imageRep)
        
        dragItem.setDraggingFrame(dragFrame, contents: dragImage)
        
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
    
    // MARK: - NSDraggingSource & NSPasteboardItemDataProvider
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .string {
            let text = getSelectedText()
            pasteboard?.setString(text, forType: .string)
        }
    }
    
    private func getSelectedText() -> String {
        let selectedRegions = textRegions.filter { $0.isSelected }
        guard !selectedRegions.isEmpty else { return "" }
        
        let sortedRegions = selectedRegions.sorted { r1, r2 in
            let yDiff = abs(r1.boundingBox.origin.y - r2.boundingBox.origin.y)
            if yDiff < 0.02 {
                return r1.boundingBox.origin.x < r2.boundingBox.origin.x
            }
            return r1.boundingBox.origin.y > r2.boundingBox.origin.y
        }
        
        return sortedRegions.map { $0.text }.joined(separator: "\n")
    }

    
    // MARK: - Actions
    
    @objc private func selectAllRegions() {
        for i in 0..<textRegions.count {
            textRegions[i].isSelected = true
        }
        updateStatus()
        needsDisplay = true
    }
    
    @objc private func clearSelection() {
        for i in 0..<textRegions.count {
            textRegions[i].isSelected = false
        }
        updateStatus()
        needsDisplay = true
    }
    
    @objc private func copySelected() {
        // Collect selected text
        // Vision text regions come in arbitrary order?
        // Ideally we should sort them by position (Top-Left to Bottom-Right)
        
        let selectedRegions = textRegions.filter { $0.isSelected }
        
        if selectedRegions.isEmpty {
            statusLabel.stringValue = LanguageManager.shared.string("error_no_text_selected")
            return
        }
        
        // Sort by Y (top to bottom), then X (left to right)
        // Remember Vision coordinates: Y is usually 0 at bottom?
        // 'boundingBox' in Vision is normalized with origin at bottom-left.
        // So higher Y is top of image with normal coordinates, but Vision might be different.
        // Actually VNRecognizedTextObservation boundingBox origin is bottom-left (0,0) to top-right (1,1).
        // So higher Y means higher up in the image.
        // We want to read top to bottom, so sort by Y descending.
        
        let sortedRegions = selectedRegions.sorted { r1, r2 in
            // Roughly same line (allow small tolerance)
            let yDiff = abs(r1.boundingBox.origin.y - r2.boundingBox.origin.y)
            if yDiff < 0.02 { // 2% tolerance for line height
                return r1.boundingBox.origin.x < r2.boundingBox.origin.x
            }
            return r1.boundingBox.origin.y > r2.boundingBox.origin.y
        }
        
        let text = sortedRegions.map { $0.text }.joined(separator: "\n")
        onComplete?(text)
    }
    
    @objc private func openSelectedData() {
        let selectedRegions = textRegions.filter { $0.isSelected }
        // Find first valid URL
        for region in selectedRegions {
            if let url = region.detectedData?.url {
                NSWorkspace.shared.open(url)
                break
            }
        }
    }
    
    @objc private func cancelSelection() {
        onCancel?()
    }
    
    private func updateStatus() {
        let lm = LanguageManager.shared
        let selectedRegions = textRegions.filter { $0.isSelected }
        let selectedCount = selectedRegions.count
        
        if selectedCount > 0 {
            // Check for data
            let dataRegions = selectedRegions.filter { $0.detectedData != nil }
            if let firstData = dataRegions.first?.detectedData {
                openButton.isHidden = false
                openButton.isEnabled = true
                
                let typeStr: String
                if firstData.type == .link {
                    typeStr = lm.string("data_link")
                } else if firstData.type == .phoneNumber {
                    typeStr = lm.string("data_phone")
                } else {
                    typeStr = lm.string("data_generic")
                }
                
                statusLabel.stringValue = String(format: lm.string("status_selected_type_format"), selectedCount, typeStr)
            } else {
                openButton.isHidden = true
                openButton.isEnabled = false
                statusLabel.stringValue = String(format: lm.string("status_selected_count_format"), selectedCount, textRegions.count)
            }
        } else {
            openButton.isHidden = true
            openButton.isEnabled = false
             statusLabel.stringValue = String(format: lm.string("status_regions_found_format"), textRegions.count)
        }
    }
    
    // MARK: - Keyboard
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancelSelection()
        } else if event.keyCode == 36 { // Return
            copySelected()
        } else if event.characters == "a" && event.modifierFlags.contains(.command) {
            selectAllRegions()
        }
    }
}
