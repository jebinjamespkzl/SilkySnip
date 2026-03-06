//
//  StickyNoteManager.swift
//  SilkySnip
//
//  Created by SilkySnip Team on 2026-01-31.
//

import Cocoa

class StickyNoteManager {
    
    static let shared = StickyNoteManager()
    
    private var activeNotes: [StickyNoteWindow] = []
    
    // MARK: - Restore Logic
    
    struct ClosedNote: Codable {
        let text: Data // RTF Data
        let colorHex: String
        let frameX: Double
        let frameY: Double
        let frameWidth: Double
        let frameHeight: Double
        let timestamp: Date
        
        var frame: NSRect {
            return NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        }
        
        init(text: Data, colorHex: String, frame: NSRect, timestamp: Date) {
            self.text = text
            self.colorHex = colorHex
            self.frameX = Double(frame.origin.x)
            self.frameY = Double(frame.origin.y)
            self.frameWidth = Double(frame.size.width)
            self.frameHeight = Double(frame.size.height)
            self.timestamp = timestamp
        }
    }
    
    private var closedNotesHistory: [ClosedNote] = []
    private let maxHistorySize = 5
    
    // Cache file path
    private var cacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
        let silkySnipDir = appSupport.appendingPathComponent("SilkySnip", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: silkySnipDir, withIntermediateDirectories: true, attributes: nil)
        
        return silkySnipDir.appendingPathComponent("sticky_notes_history.json")
    }
    
    // MARK: - Initialization
    
    private init() {
        loadHistoryFromDisk()
    }
    
    // MARK: - API
    
    /// Returns the frontmost (key) sticky note, if any
    var frontmostNote: StickyNoteWindow? {
        return activeNotes.first(where: { $0.isKeyWindow }) ?? activeNotes.last
    }
    
    func createNote(_ closedNote: ClosedNote? = nil) {
        let point: NSPoint
        let initialTextData: Data?
        let colorHex: String?
        
        if let restored = closedNote {
            point = restored.frame.origin
            initialTextData = restored.text
            colorHex = restored.colorHex
            print("[StickyNoteManager] Restoring note at \(point) with color \(colorHex ?? "default")")
        } else {
            // Calculate position (Cascade or Random) on active monitor
            let mouseLoc = NSEvent.mouseLocation
            let screenRect = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect.zero
            let x = CGFloat.random(in: screenRect.minX + 100...max(screenRect.minX + 100, screenRect.maxX - 300))
            let y = CGFloat.random(in: screenRect.minY + 100...max(screenRect.minY + 100, screenRect.maxY - 300))
            point = NSPoint(x: x, y: y)
            initialTextData = nil
            colorHex = nil
            print("[StickyNoteManager] Creating new note at \(point)")
        }
        
        let note = StickyNoteWindow(point: point)
        
        if let data = initialTextData {
            note.restoreText(from: data)
        }
        if let hex = colorHex {
            note.noteColor = NSColor(hex: hex)
        }
        
        note.makeKeyAndOrderFront(nil)
        
        activeNotes.append(note)
        
        // Auto-cleanup when window closes
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: note)
        
        // Ensure it's active
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        guard let note = notification.object as? StickyNoteWindow else { return }
        print("[StickyNoteManager] Window closing")
        
        // Check if note has actual content (not blank)
        let noteText = note.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if noteText.isEmpty {
            print("[StickyNoteManager] Note is blank - not saving to history")
        } else if let rtfData = note.rtfData() {
            // Save to History before removing
            let closedNote = ClosedNote(
                text: rtfData,
                colorHex: note.noteColor.hexString,
                frame: note.frame,
                timestamp: Date()
            )
            addToHistory(closedNote)
            print("[StickyNoteManager] Saved note to history. Color: \(closedNote.colorHex), text length: \(noteText.count)")
        } else {
            print("[StickyNoteManager] Warning: Could not get RTF data from note")
        }
        
        removeNote(note)
    }
    
    func removeNote(_ note: StickyNoteWindow) {
        if let index = activeNotes.firstIndex(of: note) {
            activeNotes.remove(at: index)
            print("[StickyNoteManager] Note removed. Remaining active: \(activeNotes.count)")
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: note)
        }
    }
    
    func closeAllNotes() {
        print("[StickyNoteManager] Closing all \(activeNotes.count) notes")
        let notes = activeNotes
        for note in notes {
            note.close()
        }
        activeNotes.removeAll()
    }
    
    func showAllNotes() {
        print("[StickyNoteManager] Showing all \(activeNotes.count) notes")
        for note in activeNotes {
            note.makeKeyAndOrderFront(nil)
        }
        if !activeNotes.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func hideAllNotes() {
        print("[StickyNoteManager] Hiding all \(activeNotes.count) notes")
        for note in activeNotes {
            note.orderOut(nil)
        }
    }
    
    func unhideAllNotes() {
        showAllNotes()
    }
    
    var hasActiveNotes: Bool {
        return !activeNotes.isEmpty
    }
    
    var hasVisibleNotes: Bool {
        return activeNotes.contains(where: { $0.isVisible })
    }
    
    var hasHiddenNotes: Bool {
        return activeNotes.contains(where: { !$0.isVisible })
    }
    
    // MARK: - History Management
    
    private func addToHistory(_ note: ClosedNote) {
        closedNotesHistory.insert(note, at: 0)
        if closedNotesHistory.count > maxHistorySize {
            closedNotesHistory.removeLast()
        }
        
        // Persist to disk
        saveHistoryToDisk()
        
        // Notify listeners
        NotificationCenter.default.post(name: Notification.Name("StickyNoteHistoryChanged"), object: nil)
        print("[StickyNoteManager] History updated. Count: \(closedNotesHistory.count)")
    }
    
    func getHistory() -> [ClosedNote] {
        return closedNotesHistory
    }
    
    func restoreMostRecent() {
        guard !closedNotesHistory.isEmpty else {
            print("[StickyNoteManager] No notes in history to restore")
            return
        }
        
        let note = closedNotesHistory.removeFirst()
        print("[StickyNoteManager] Restoring most recent note. Color: \(note.colorHex)")
        
        // Persist updated history
        saveHistoryToDisk()
        
        createNote(note)
        NotificationCenter.default.post(name: Notification.Name("StickyNoteHistoryChanged"), object: nil)
    }
    
    func clearHistory() {
        print("[StickyNoteManager] Clearing note history")
        closedNotesHistory.removeAll()
        saveHistoryToDisk()
        NotificationCenter.default.post(name: Notification.Name("StickyNoteHistoryChanged"), object: nil)
    }
    
    // MARK: - Disk Persistence
    
    private func saveHistoryToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(closedNotesHistory)
            try data.write(to: cacheURL)
            print("[StickyNoteManager] History saved to disk at \(cacheURL.path)")
        } catch {
            print("[StickyNoteManager] Error saving history: \(error)")
        }
    }
    
    private func loadHistoryFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            print("[StickyNoteManager] No history file found at \(cacheURL.path)")
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            closedNotesHistory = try decoder.decode([ClosedNote].self, from: data)
            print("[StickyNoteManager] Loaded \(closedNotesHistory.count) notes from history")
        } catch {
            print("[StickyNoteManager] Error loading history: \(error)")
            closedNotesHistory = []
        }
    }
    
    // MARK: - Debug
    
    func printDebugInfo() {
        print("=== StickyNoteManager Debug ===")
        print("Active Notes: \(activeNotes.count)")
        print("History Count: \(closedNotesHistory.count)")
        for (index, note) in closedNotesHistory.enumerated() {
            print("  [\(index)] Color: \(note.colorHex), Timestamp: \(note.timestamp)")
        }
        print("Cache Path: \(cacheURL.path)")
        print("===============================")
    }
}
