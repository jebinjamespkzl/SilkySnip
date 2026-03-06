//
//  AuditLogger.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Foundation

/// AuditLogger provides enterprise-grade logging for security and compliance
/// Logs all export, copy, and sensitive actions with timestamps
final class AuditLogger {
    
    static let shared = AuditLogger()
    
    private let logURL: URL
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.silkysnip.audit", qos: .utility)
    
    // MARK: - Audit Event Types
    
    enum EventType: String, Codable {
        case capture = "CAPTURE"
        case save = "SAVE"
        case copy = "COPY"
        case restore = "RESTORE"
        case delete = "DELETE"
        case export = "EXPORT"
        case appLaunch = "APP_LAUNCH"
        case appTerminate = "APP_TERMINATE"
        case securityAlert = "SECURITY_ALERT"
        case failure = "FAILURE"
        case crash = "CRASH"
    }
    
    struct AuditEntry: Codable {
        let timestamp: Date
        let eventType: EventType
        let details: String
        let screenshotID: String?
        let userInfo: [String: String]?
    }
    
    // MARK: - Initialization
    
    private init() {
        // Store audit log in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("SilkySnip")
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        logURL = appDir.appendingPathComponent("audit.log")
        
        rotateLogIfNeeded()
    }
    
    // MARK: - Logging
    
    /// Log an audit event
    func log(_ eventType: EventType, details: String, screenshotID: UUID? = nil, userInfo: [String: String]? = nil) {
        let entry = AuditEntry(
            timestamp: Date(),
            eventType: eventType,
            details: details,
            screenshotID: screenshotID?.uuidString,
            userInfo: userInfo
        )
        
        logQueue.async { [weak self] in
            self?.writeEntry(entry)
        }
    }
    
    private func writeEntry(_ entry: AuditEntry) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: entry.timestamp)
        
        var logLine = "[\(timestamp)] [\(entry.eventType.rawValue)]"
        
        if let id = entry.screenshotID {
            logLine += " [ID:\(id)]"
        }
        
        logLine += " \(entry.details)"
        
        if let info = entry.userInfo {
            let infoStr = info.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            logLine += " {\(infoStr)}"
        }
        
        logLine += "\n"
        
        // Append to log file
        if let data = logLine.data(using: .utf8) {
            if fileManager.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    func logCapture(screenshotID: UUID, size: CGSize) {
        log(.capture, details: "Screenshot captured", screenshotID: screenshotID, userInfo: [
            "width": "\(Int(size.width))",
            "height": "\(Int(size.height))"
        ])
    }
    
    func logSave(screenshotID: UUID, path: String, format: String) {
        log(.save, details: "Screenshot saved to \(path)", screenshotID: screenshotID, userInfo: [
            "format": format
        ])
    }
    
    func logCopy(screenshotID: UUID) {
        log(.copy, details: "Screenshot copied to clipboard", screenshotID: screenshotID)
    }
    
    func logExport(screenshotID: UUID, destination: String) {
        log(.export, details: "Screenshot exported", screenshotID: screenshotID, userInfo: [
            "destination": destination
        ])
    }
    
    func logSecurityAlert(_ message: String) {
        log(.securityAlert, details: message)
    }

    func logFailure(action: String, error: Error) {
        log(.failure, details: "Action failed: \(action)", userInfo: [
            "error": error.localizedDescription
        ])
    }

    func logCrash(exception: NSException) {
        let stackTrace = exception.callStackSymbols.joined(separator: "|")
        log(.crash, details: "App Crashed", userInfo: [
            "name": exception.name.rawValue,
            "reason": exception.reason ?? "Unknown",
            "stack": stackTrace
        ])
    }
    
    func logCrash(message: String) {
        log(.crash, details: message)
    }
    
    // MARK: - Log Management
    
    /// Get the audit log file path
    var logPath: String {
        return logURL.path
    }
    
    /// Get total log size in bytes
    func getLogSize() -> Int64 {
        guard let attrs = try? fileManager.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
    
    /// Rotate log if it exceeds 10MB
    func rotateLogIfNeeded() {
        let maxSize: Int64 = 10 * 1024 * 1024 // 10MB
        
        if getLogSize() > maxSize {
            let timestamp = Int(Date().timeIntervalSince1970)
            let archiveName = "audit-\(timestamp).log"
            let archiveURL = logURL.deletingLastPathComponent().appendingPathComponent(archiveName)
            
            try? fileManager.moveItem(at: logURL, to: archiveURL)
            
            // Cleanup old logs
            cleanupOldLogs()
            
            log(.appLaunch, details: "Audit log rotated")
        }
    }
    
    private func cleanupOldLogs() {
        let logDir = logURL.deletingLastPathComponent()
        guard let files = try? fileManager.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }
        
        // Filter for audit archives (exclude current active log)
        let archives = files.filter { $0.lastPathComponent.hasPrefix("audit-") && $0.pathExtension == "log" }
        
        // Sort by creation date descending (newest first)
        let sorted = archives.sorted {
            let date1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let date2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return date1 > date2
        }
        
        // Keep max 5 archives
        if sorted.count > 5 {
            let toDelete = sorted.suffix(from: 5)
            for fileURL in toDelete {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
