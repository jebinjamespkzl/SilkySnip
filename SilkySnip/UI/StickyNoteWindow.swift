//
//  StickyNoteWindow.swift
//  SilkySnip
//
//  Created by SilkySnip Team on 2026-01-31.
//

import Cocoa

// MARK: - List Style Enum

enum ListStyle: String {
    case none = "none"
    case bullet = "bullet"
    case numbered = "numbered"
}

enum FontSize: CGFloat {
    case small = 11
    case normal = 15
    case large = 19
    
    var displayName: String {
        switch self {
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }
}

// MARK: - StickyNoteWindow

class StickyNoteWindow: NSPanel, NSTextViewDelegate {
    
    // MARK: - Data Export/Import
    
    func rtfData() -> Data? {
        guard let storage = textView.textStorage else { return nil }
        let range = NSRange(location: 0, length: storage.length)
        return try? storage.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
    
    func restoreText(from data: Data) {
        textView.replaceCharacters(in: NSRange(location: 0, length: textView.string.count), withRTF: data)
    }
    
    // MARK: - Properties
    
    let id: UUID = UUID()
    
    private let stickyView = StickyNoteView()
    let textView = NSTextView() // Made internal for menu validation
    private let scrollView = NSScrollView()
    private let closeButton = NSButton()
    
    // Current list style
    var listStyle: ListStyle = .none
    
    // Current font size
    var fontSize: FontSize = .small
    
    // Lock to display constraint
    @objc dynamic var isLockedToDisplay: Bool = false {
        didSet {
            if isLockedToDisplay {
                self.collectionBehavior = self.collectionBehavior.subtracting(.canJoinAllSpaces)
            } else {
                self.collectionBehavior.insert(.canJoinAllSpaces)
            }
        }
    }
    
    // Default Color
    var noteColor: NSColor = NSColor(hex: "#FFEB3B") {
        didSet {
            Logger.shared.info("[StickyNote] Color changed to: \(noteColor.hexString)")
            stickyView.backgroundColor = noteColor
            stickyView.needsDisplay = true
        }
    }
    
    // MARK: - Initialization
    
    init(point: NSPoint) {
        let styleMask: NSWindow.StyleMask = [.borderless, .resizable, .nonactivatingPanel, .utilityWindow]
        let initialFrame = NSRect(origin: point, size: NSSize(width: 220, height: 220))
        
        super.init(contentRect: initialFrame, styleMask: styleMask, backing: .buffered, defer: false)
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .modalPanel 
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.minSize = NSSize(width: 120, height: 120)
        self.isReleasedWhenClosed = false
        
        setupUI()
        setupCloseButton()
        setupTracking()
    }

    // MARK: - Window Status
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    
    // MARK: - Setup
    
    private func setupUI() {
        // Background View (Custom Shape)
        stickyView.frame = contentView?.bounds ?? .zero
        stickyView.autoresizingMask = [.width, .height]
        self.contentView = stickyView
        
        // ScrollView Setup
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // TextView Setup
        textView.drawsBackground = false
        textView.isRichText = true // Required for Bold/Italics/Underline, but we must restrict content
        
        // SECURITY HARDENING: Prevent macro/code execution and graphic embedding
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticDataDetectionEnabled = false 
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        
        textView.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        textView.textColor = .black
        
        // Paragraph Style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 20
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 20, options: [:])]
        
        textView.defaultParagraphStyle = paragraphStyle
        
        textView.typingAttributes = [
             .foregroundColor: NSColor.black,
             .font: textView.font ?? NSFont.systemFont(ofSize: 16),
             .paragraphStyle: paragraphStyle
        ]
        
        // Start empty (no bullet by default)
        textView.string = ""
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.allowsUndo = true
        textView.delegate = self

        scrollView.documentView = textView
        
        // Position ScrollView with padding
        scrollView.frame = stickyView.bounds.insetBy(dx: 8, dy: 8).offsetBy(dx: 0, dy: -5)
        scrollView.autoresizingMask = [.width, .height]
        
        stickyView.addSubview(scrollView)
        
        // Context Menu
        setupContextMenu()
    }
    
    private func setupCloseButton() {
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeNote)
        closeButton.frame = NSRect(x: 5, y: stickyView.bounds.height - 25, width: 20, height: 20)
        closeButton.autoresizingMask = [.maxXMargin, .minYMargin]
        closeButton.isHidden = true
        closeButton.contentTintColor = .darkGray
        
        stickyView.addSubview(closeButton)
    }
    
    private func setupTracking() {
        let trackingArea = NSTrackingArea(
            rect: stickyView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        stickyView.addTrackingArea(trackingArea)
    }
    
    private func setupContextMenu() {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // 1. Text Format Section
        let formatHeader = NSMenuItem(title: lm.string("menu.text.format"), action: nil, keyEquivalent: "")
        formatHeader.isEnabled = false
        menu.addItem(formatHeader)
        
        let boldItem = NSMenuItem(title: lm.string("format_bold"), action: #selector(toggleBold), keyEquivalent: Constants.Shortcut.textBold.key)
        boldItem.keyEquivalentModifierMask = Constants.Shortcut.textBold.modifiers
        boldItem.target = self
        boldItem.tag = 1
        let boldDescriptor = NSFont.systemFont(ofSize: 14).fontDescriptor.withSymbolicTraits(.bold)
        if let boldFont = NSFont(descriptor: boldDescriptor, size: 14) {
             boldItem.attributedTitle = NSAttributedString(string: lm.string("format_bold"), attributes: [.font: boldFont])
        }
        menu.addItem(boldItem)
        
        let underlineItem = NSMenuItem(title: lm.string("format_underline"), action: #selector(toggleUnderline), keyEquivalent: Constants.Shortcut.textUnderline.key)
        underlineItem.keyEquivalentModifierMask = Constants.Shortcut.textUnderline.modifiers
        underlineItem.target = self
        underlineItem.tag = 3
        underlineItem.attributedTitle = NSAttributedString(string: lm.string("format_underline"), attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 14)
        ])
        menu.addItem(underlineItem)
        
        let strikeItem = NSMenuItem(title: lm.string("format_strikethrough"), action: #selector(toggleStrikethrough), keyEquivalent: Constants.Shortcut.textStrikethrough.key)
        strikeItem.keyEquivalentModifierMask = Constants.Shortcut.textStrikethrough.modifiers
        strikeItem.target = self
        strikeItem.tag = 4
        strikeItem.attributedTitle = NSAttributedString(string: lm.string("format_strikethrough"), attributes: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 14)
        ])
        menu.addItem(strikeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Font Size
        let sizeHeader = NSMenuItem(title: lm.string("menu.font.size"), action: nil, keyEquivalent: "")
        sizeHeader.isEnabled = false
        menu.addItem(sizeHeader)
        
        // Localized Font Display Names
        let fontSizes: [(String, FontSize)] = [
            (lm.string("sticky_font_small"), .small),
            (lm.string("sticky_font_normal"), .normal),
            (lm.string("sticky_font_large"), .large)
        ]
        
        for (name, size) in fontSizes {
            let sizeItem = NSMenuItem(title: name, action: #selector(setFontSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = size
            if size == fontSize { // Changed from currentFontSize to fontSize
                sizeItem.state = .on
            }
            menu.addItem(sizeItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // List Style
        let listHeader = NSMenuItem(title: lm.string("menu.list.style"), action: nil, keyEquivalent: "")
        listHeader.isEnabled = false
        menu.addItem(listHeader)
        
        let listStyles: [(String, ListStyle)] = [
            (lm.string("list_none"), .none),
            (lm.string("list_bullet"), .bullet),
            (lm.string("list_numbered"), .numbered)
        ]
        
        for (name, style) in listStyles {
            let listItem = NSMenuItem(title: name, action: #selector(setListStyle(_:)), keyEquivalent: "")
            listItem.representedObject = style
            if style == listStyle { // Changed from currentListStyle to listStyle
                listItem.state = .on
            }
            menu.addItem(listItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Colors
        let colorHeader = NSMenuItem(title: lm.string("menu.sticky.color"), action: nil, keyEquivalent: "")
        colorHeader.isEnabled = false
        menu.addItem(colorHeader)
        
        let colors = [
            ("#FFEB3B", lm.string("color_select_yellow")),
            ("#FF4081", lm.string("color_select_pink")),
            ("#00E5FF", lm.string("color_select_cyan")),
            ("#76FF03", lm.string("color_select_green")), // Using hex from original code but name from my list, might mismatch color perception but consistent with keys
            ("#FFFFFF", lm.string("color_select_white"))
        ]
        
        for (hex, name) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(selectColor(_:)), keyEquivalent: "")
            colorItem.representedObject = hex
            colorItem.target = self
            
            // Create a colored swatch image
            let swatchSize = NSSize(width: 16, height: 16)
            let swatchImage = NSImage(size: swatchSize, flipped: false) { rect in
                let color = NSColor(hex: hex)
                color.setFill()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
                path.fill()
                // Add border for white color visibility
                NSColor.lightGray.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                return true
            }
            colorItem.image = swatchImage
            
            // Add checkmark for current color
            if hex.uppercased() == noteColor.hexString.uppercased() {
                colorItem.state = .on
            }
            menu.addItem(colorItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Lock to Display
        let lockItem = NSMenuItem(title: LanguageManager.shared.string("menu.lock.display") ?? "Lock to Display", action: #selector(toggleLockToDisplay), keyEquivalent: "")
        lockItem.target = self
        lockItem.tag = 100
        menu.addItem(lockItem)
        
        // 4. Hide
        let hideItem = NSMenuItem(title: "Hide Note", action: #selector(hideNote), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
        
        // 5. Close
        let closeItem = NSMenuItem(title: lm.string("menu.close.note"), action: #selector(closeNote), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        
        // Set menu delegate for dynamic state updates
        menu.delegate = self
        
        stickyView.menu = menu
        textView.menu = menu
    }
    
    // M6: Lightweight checkmark update without full menu rebuild
    private func updateContextMenuCheckmarks() {
        guard let menu = textView.menu else { return }
        for item in menu.items {
            // Font size checkmarks
            if let size = item.representedObject as? FontSize {
                item.state = (size == fontSize) ? .on : .off
            }
            // List style checkmarks
            if let style = item.representedObject as? ListStyle {
                item.state = (style == listStyle) ? .on : .off
            }
            // Color checkmarks
            if let hex = item.representedObject as? String, hex.hasPrefix("#") {
                item.state = (hex.uppercased() == noteColor.hexString.uppercased()) ? .on : .off
            }
            // Lock to Display checkmark
            if item.tag == 100 {
                item.state = isLockedToDisplay ? .on : .off
            }
        }
    }
    
    // MARK: - Color Selection
    
    @objc func selectColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else {
            Logger.shared.error("[StickyNote] selectColor: No hex in representedObject")
            return
        }
        Logger.shared.debug("[StickyNote] selectColor called with: \(hex)")
        self.noteColor = NSColor(hex: hex)
        // M6: Update checkmarks without rebuilding entire menu
        updateContextMenuCheckmarks()
    }
    
    // MARK: - Font Size Selection
    
    @objc func setFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? FontSize else {
            Logger.shared.error("[StickyNote] setFontSize: No size in representedObject")
            return
        }
        Logger.shared.debug("[StickyNote] setFontSize called with: \(size.displayName) (\(size.rawValue)pt)")
        self.fontSize = size
        
        // Apply new font size to all text
        applyFontSize(size.rawValue)
        
        // M6: Update checkmarks without rebuilding entire menu
        updateContextMenuCheckmarks()
    }
    
    private func applyFontSize(_ pointSize: CGFloat) {
        guard let textStorage = textView.textStorage else { return }
        
        // Update typing attributes
        var typingAttrs = textView.typingAttributes
        if let currentFont = typingAttrs[.font] as? NSFont {
            let newFont = NSFont(name: currentFont.fontName, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
            typingAttrs[.font] = newFont
            textView.typingAttributes = typingAttrs
        }
        
        // Apply to existing text
        let fullRange = NSRange(location: 0, length: textStorage.length)
        if fullRange.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                if let font = value as? NSFont {
                    let newFont = NSFont(name: font.fontName, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
                    textStorage.addAttribute(.font, value: newFont, range: range)
                }
            }
            textStorage.endEditing()
        }
        
        Logger.shared.debug("[StickyNote] Font size applied: \(pointSize)pt")
    }
    
    // MARK: - Formatting Actions
    
    @objc func toggleBold() {
        Logger.shared.debug("[StickyNote] toggleBold called")
        let range = textView.selectedRange()
        
        if range.length == 0 {
            // No selection - modify typing attributes
            var attributes = textView.typingAttributes
            if let font = attributes[.font] as? NSFont {
                let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                let newFont: NSFont
                if isBold {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                attributes[.font] = newFont
                textView.typingAttributes = attributes
                Logger.shared.debug("[StickyNote] Bold toggled in typing attributes. Now bold: \(!isBold)")
            }
            return
        }
        
        // Has selection - apply to selected text
        guard let textStorage = textView.textStorage else { return }
        
        // Check if all selected text is bold
        var allBold = true
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
            if let font = value as? NSFont {
                if !font.fontDescriptor.symbolicTraits.contains(.bold) {
                    allBold = false
                }
            }
        }
        
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            if let font = value as? NSFont {
                let newFont: NSFont
                if allBold {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                textStorage.addAttribute(.font, value: newFont, range: r)
            }
        }
        textStorage.endEditing()
        Logger.shared.debug("[StickyNote] Bold toggled on selection. Was all bold: \(allBold)")
    }
    
    @objc func toggleItalic() {
        Logger.shared.debug("[StickyNote] toggleItalic called")
        let range = textView.selectedRange()
        
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if let font = attributes[.font] as? NSFont {
                // Check for italic trait or font name containing "italic/oblique"
                let fontName = font.fontName.lowercased()
                let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic) || 
                               fontName.contains("italic") || fontName.contains("oblique")
                
                Logger.shared.debug("[StickyNote] Current font: \(font.fontName), isItalic: \(isItalic)")
                
                let newFont: NSFont
                if isItalic {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                
                Logger.shared.debug("[StickyNote] New font after toggle: \(newFont.fontName)")
                attributes[.font] = newFont
                textView.typingAttributes = attributes
            }
            return
        }
        
        guard let textStorage = textView.textStorage else { return }
        
        // Check first character for italic state
        var firstFont: NSFont?
        if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            firstFont = font
        }
        
        let fontName = firstFont?.fontName.lowercased() ?? ""
        let allItalic = firstFont?.fontDescriptor.symbolicTraits.contains(.italic) == true ||
                        fontName.contains("italic") || fontName.contains("oblique")
        
        Logger.shared.debug("[StickyNote] Selection font: \(firstFont?.fontName ?? "nil"), allItalic: \(allItalic)")
        
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            if let font = value as? NSFont {
                let newFont: NSFont
                if allItalic {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                textStorage.addAttribute(.font, value: newFont, range: r)
            }
        }
        textStorage.endEditing()
        Logger.shared.debug("[StickyNote] Italic toggled on selection. Was italic: \(allItalic)")
    }
    
    @objc func toggleUnderline() {
        Logger.shared.debug("[StickyNote] toggleUnderline called")
        let range = textView.selectedRange()
        
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if attributes[.underlineStyle] != nil {
                attributes.removeValue(forKey: .underlineStyle)
            } else {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            textView.typingAttributes = attributes
            return
        }
        
        guard let textStorage = textView.textStorage else { return }
        
        // Check if any part has underline
        var hasUnderline = false
        textStorage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
            if value != nil {
                hasUnderline = true
            }
        }
        
        textStorage.beginEditing()
        if hasUnderline {
            textStorage.removeAttribute(.underlineStyle, range: range)
        } else {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        textStorage.endEditing()
    }
    
    @objc func toggleStrikethrough() {
        Logger.shared.debug("[StickyNote] toggleStrikethrough called")
        let range = textView.selectedRange()
        
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if attributes[.strikethroughStyle] != nil {
                attributes.removeValue(forKey: .strikethroughStyle)
            } else {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            textView.typingAttributes = attributes
            return
        }
        
        guard let textStorage = textView.textStorage else { return }
        
        var hasStrike = false
        textStorage.enumerateAttribute(.strikethroughStyle, in: range, options: []) { value, _, _ in
            if value != nil {
                hasStrike = true
            }
        }
        
        textStorage.beginEditing()
        if hasStrike {
            textStorage.removeAttribute(.strikethroughStyle, range: range)
        } else {
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        textStorage.endEditing()
    }
    
    // MARK: - Mouse Events
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().isHidden = false
            closeButton.animator().alphaValue = 1.0
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.closeButton.isHidden = true
        }
    }
    
    // MARK: - Actions
    
    @objc func closeNote() {
        Logger.shared.info("[StickyNote] Close requested")
        self.close()
    }
    
    @objc func hideNote() {
        Logger.shared.info("[StickyNote] Hide requested")
        self.orderOut(nil)
    }
    
    deinit {
        Logger.shared.info("[StickyNote] Deinitialized")
    }
    
    @objc func setListStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? ListStyle else { return }
        Logger.shared.debug("[StickyNote] setListStyle: \(style.rawValue)")
        
        // Save cursor position BEFORE changes
        let savedCursorLocation = textView.selectedRange().location
        
        self.listStyle = style
        applyListStyle(preservingCursorAt: savedCursorLocation)
    }
    
    // MARK: - List Logic (Simplified - No Cursor Jump)
    
    private func applyListStyle(preservingCursorAt originalCursor: Int) {
        guard let textStorage = textView.textStorage else { return }
        
        let originalText = textStorage.string
        let lines = originalText.components(separatedBy: "\n")
        var newLines: [String] = []
        
        // Track character offset changes for cursor adjustment
        var cursorAdjustment = 0
        var cursorProcessed = false
        var runningOriginalIndex = 0
        
        for (index, line) in lines.enumerated() {
            var cleanLine = line
            var oldPrefixLength = 0
            
            // Remove existing markers
            if cleanLine.hasPrefix("• ") {
                cleanLine = String(cleanLine.dropFirst(2))
                oldPrefixLength = 2
            } else if let range = cleanLine.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                oldPrefixLength = cleanLine.distance(from: cleanLine.startIndex, to: range.upperBound)
                cleanLine = String(cleanLine[range.upperBound...])
            }
            
            // Determine new prefix
            var newPrefix = ""
            switch listStyle {
            case .none: newPrefix = ""
            case .bullet: newPrefix = "• "
            case .numbered: newPrefix = "\(index + 1). "
            }
            
            let newLine = newPrefix + cleanLine
            newLines.append(newLine)
            
            // Track cursor adjustment
            let lineStartInOriginal = runningOriginalIndex
            let lineEndInOriginal = lineStartInOriginal + line.count
            
            if !cursorProcessed && originalCursor <= lineEndInOriginal {
                // Cursor is in this line
                let cursorOffsetInLine = originalCursor - lineStartInOriginal
                
                // If cursor was in the old prefix, move it to start of content
                let newCursorOffsetInLine: Int
                if cursorOffsetInLine <= oldPrefixLength {
                    newCursorOffsetInLine = newPrefix.count
                } else {
                    // Cursor was in content, keep relative position
                    newCursorOffsetInLine = newPrefix.count + (cursorOffsetInLine - oldPrefixLength)
                }
                
                // Calculate running offset in new text
                var newRunningIndex = 0
                for i in 0..<index {
                    newRunningIndex += newLines[i].count + 1 // +1 for newline
                }
                cursorAdjustment = (newRunningIndex + newCursorOffsetInLine) - originalCursor
                cursorProcessed = true
            }
            
            // Move to next line (add 1 for the newline character)
            runningOriginalIndex = lineEndInOriginal + 1
        }
        
        let newText = newLines.joined(separator: "\n")
        
        // Replace text while preserving attributes as much as possible
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: newText)
        
        // Apply paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 20
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: 20, options: [:])]
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttributes([
            .font: textView.font ?? NSFont.systemFont(ofSize: 16),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ], range: fullRange)
        textStorage.endEditing()
        
        // Restore cursor with adjustment
        let newCursorLocation = max(0, min(originalCursor + cursorAdjustment, textStorage.length))
        textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
        
        Logger.shared.debug("[StickyNote] applyListStyle complete. Cursor: \(originalCursor) -> \(newCursorLocation)")
    }
    
    @objc func toggleLockToDisplay() {
        isLockedToDisplay.toggle()
    }
    
    // MARK: - NSTextViewDelegate (Bullet Logic)
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            if listStyle == .bullet {
                textView.insertText("\n• ", replacementRange: textView.selectedRange())
                return true
            } else if listStyle == .numbered {
                // Count current line number
                let text = textView.string
                let cursorLocation = textView.selectedRange().location
                let textUpToCursor = String(text.prefix(cursorLocation))
                let lineCount = textUpToCursor.components(separatedBy: "\n").count
                textView.insertText("\n\(lineCount + 1). ", replacementRange: textView.selectedRange())
                return true
            }
        }
        return false
    }
    
    // MARK: - Menu Validation (For Checkmarks)
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Format checkmarks based on current selection/typing attributes
        switch menuItem.tag {
        case 1: // Bold
            menuItem.state = checkFormatTrait(.bold) ? .on : .off
            return true
        case 2: // Italic
            menuItem.state = checkFormatTrait(.italic) ? .on : .off
            return true
        case 3: // Underline
            menuItem.state = checkFormatAttribute(.underlineStyle) ? .on : .off
            return true
        case 4: // Strikethrough
            menuItem.state = checkFormatAttribute(.strikethroughStyle) ? .on : .off
            return true
        case 10: // No List
            menuItem.state = listStyle == .none ? .on : .off
            return true
        case 11: // Bullet
            menuItem.state = listStyle == .bullet ? .on : .off
            return true
        case 12: // Numbered
            menuItem.state = listStyle == .numbered ? .on : .off
            return true
        case 100: // Lock to display
            menuItem.state = isLockedToDisplay ? .on : .off
            return true
        default:
            break
        }
        return super.validateMenuItem(menuItem)
    }
    
    private func checkFormatTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> Bool {
        let range = textView.selectedRange()
        
        if range.length == 0 {
            // Check typing attributes
            if let font = textView.typingAttributes[.font] as? NSFont {
                var result = font.fontDescriptor.symbolicTraits.contains(trait)
                // For italic, also check if font name contains "Italic" or "Oblique"
                if trait == .italic && !result {
                    let fontName = font.fontName.lowercased()
                    result = fontName.contains("italic") || fontName.contains("oblique")
                }
                Logger.shared.debug("[StickyNote] checkFormatTrait(\(trait)) from typing attrs: \(result), font: \(font.fontName)")
                return result
            }
            return false
        }
        
        // Check first character of selection
        guard let textStorage = textView.textStorage else { return false }
        if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            var result = font.fontDescriptor.symbolicTraits.contains(trait)
            // For italic, also check if font name contains "Italic" or "Oblique"
            if trait == .italic && !result {
                let fontName = font.fontName.lowercased()
                result = fontName.contains("italic") || fontName.contains("oblique")
            }
            Logger.shared.debug("[StickyNote] checkFormatTrait(\(trait)) from selection: \(result), font: \(font.fontName)")
            return result
        }
        return false
    }
    
    private func checkFormatAttribute(_ key: NSAttributedString.Key) -> Bool {
        let range = textView.selectedRange()
        
        if range.length == 0 {
            let result = textView.typingAttributes[key] != nil
            Logger.shared.debug("[StickyNote] checkFormatAttribute(\(key)) from typing attrs: \(result)")
            return result
        }
        
        guard let textStorage = textView.textStorage else { return false }
        let result = textStorage.attribute(key, at: range.location, effectiveRange: nil) != nil
        Logger.shared.debug("[StickyNote] checkFormatAttribute(\(key)) from selection: \(result)")
        return result
    }
}

// MARK: - NSMenuDelegate

extension StickyNoteWindow: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Force update checkmarks when menu is about to display
        print("[StickyNote] menuNeedsUpdate - refreshing checkmarks")
        
        for item in menu.items {
            // This triggers validateMenuItem for each item
            _ = validateMenuItem(item)
        }
        
        // Update color palette selection
        if let paletteItem = menu.items.first(where: { $0.view is ColorPaletteView }),
           let paletteView = paletteItem.view as? ColorPaletteView {
            paletteView.selectedColorHex = noteColor.hexString
            paletteView.needsDisplay = true
        }
    }
}


// MARK: - StickyNoteView (Custom Drawing)

class StickyNoteView: NSView {
    
    var backgroundColor: NSColor = NSColor(hex: "#FFEB3B")
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let foldSize: CGFloat = 20.0
        let rect = bounds
        
        // Main shape with folded corner
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - foldSize, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + foldSize))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        
        backgroundColor.setFill()
        path.fill()
        
        // Fold triangle (darker shade)
        let foldPath = NSBezierPath()
        foldPath.move(to: NSPoint(x: rect.maxX - foldSize, y: rect.minY))
        foldPath.line(to: NSPoint(x: rect.maxX, y: rect.minY + foldSize))
        foldPath.line(to: NSPoint(x: rect.maxX - foldSize, y: rect.minY + foldSize))
        foldPath.close()
        
        if let foldColor = backgroundColor.shadow(withLevel: 0.25) {
            foldColor.setFill()
        } else {
            NSColor.darkGray.setFill()
        }
        foldPath.fill()
    }
    
    override var isFlipped: Bool { false }
}

// MARK: - Color Palette Delegate

protocol ColorPaletteDelegate: AnyObject {
    func didSelectColor(_ hex: String)
}

// MARK: - Color Palette View (Custom Menu Item View)

class ColorPaletteView: NSView {
    
    weak var delegate: ColorPaletteDelegate?
    var selectedColorHex: String = "" {
        didSet {
            updateButtonSelection()
        }
    }
    
    private let colors = [
        ("#FFEB3B", "Yellow"),
        ("#F48FB1", "Pink"),
        ("#81D4FA", "Blue"),
        ("#A5D6A7", "Green"),
        ("#FFFFFF", "White"),
        ("#E1BEE7", "Purple"),
        ("#FFCC80", "Orange")
    ]
    
    private let buttonSize: CGFloat = 24
    private let padding: CGFloat = 6
    private let startX: CGFloat = 16
    
    private var colorButtons: [NSButton] = []
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButtons()
    }
    
    private func setupButtons() {
        for (index, (hex, name)) in colors.enumerated() {
            let button = NSButton(frame: rectForIndex(index))
            button.bezelStyle = .circular
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(hex: hex).cgColor
            button.layer?.cornerRadius = buttonSize / 2
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.5).cgColor
            button.tag = index
            button.target = self
            button.action = #selector(colorButtonClicked(_:))
            button.toolTip = name
            
            // Make it focusable
            button.focusRingType = .none
            
            addSubview(button)
            colorButtons.append(button)
        }
    }
    
    @objc private func colorButtonClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < colors.count else { return }
        
        let (hex, name) = colors[index]
        print("[ColorPalette] Button clicked: \(name) (\(hex))")
        
        selectedColorHex = hex
        delegate?.didSelectColor(hex)
    }
    
    private func updateButtonSelection() {
        for (index, button) in colorButtons.enumerated() {
            let (hex, _) = colors[index]
            let isSelected = hex.uppercased() == selectedColorHex.uppercased()
            
            if isSelected {
                button.layer?.borderWidth = 3
                button.layer?.borderColor = NSColor.controlAccentColor.cgColor
            } else {
                button.layer?.borderWidth = 1
                button.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.5).cgColor
            }
        }
    }
    
    private func rectForIndex(_ index: Int) -> NSRect {
        return NSRect(
            x: startX + CGFloat(index) * (buttonSize + padding),
            y: (self.bounds.height - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )
    }
}
