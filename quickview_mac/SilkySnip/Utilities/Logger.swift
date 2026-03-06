//
//  Logger.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Foundation
import os.log

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var icon: String {
        switch self {
        case .debug: return "🐞"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

final class Logger {
    static let shared = Logger()
    
    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let currentLogFileURL: URL
    private let logQueue = DispatchQueue(label: "com.silkyapple.silkysnip.logger", qos: .utility)
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    private init() {
        // Setup log directory: ~/Library/Logs/SilkyApple/SilkySnip/
        let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = libraryDir.appendingPathComponent("Logs")
        let vendorDir = logsDir.appendingPathComponent("SilkyApple")
        logDirectory = vendorDir.appendingPathComponent("SilkySnip")
        
        currentLogFileURL = logDirectory.appendingPathComponent("silkysnip.log")
        
        setupLogDirectory()
        rotateLogsIfNeeded()
        
        log(.info, "=== Logger Session Started ===")
        logSystemInfo()
    }
    
    private func setupLogDirectory() {
        if !fileManager.fileExists(atPath: logDirectory.path) {
            do {
                try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create log directory: \(error)")
            }
        }
    }
    
    private func logSystemInfo() {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        log(.info, "App Version: \(appVersion) (\(buildNumber))")
        log(.info, "OS Version: \(osVersion)")
        log(.info, "Device: \(Host.current().localizedName ?? "Unknown Mac")")
    }
    
    // MARK: - Public API
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.critical, message, file: file, function: function, line: line)
    }
    
    func logEvent(category: String, action: String, label: String? = nil) {
        var message = "Event: [\(category)] \(action)"
        if let label = label {
            message += " - \(label)"
        }
        log(.info, message)
    }
    
    // MARK: - Internal Logging Logic
    
    private func log(_ level: LogLevel, _ message: String, file: String? = nil, function: String? = nil, line: Int? = nil) {
        let timestamp = dateFormatter.string(from: Date())
        var logMessage = "\(timestamp) [\(level.rawValue)] \(level.icon) "
        
        if let file = file, let function = function, let line = line {
            let fileName = (file as NSString).lastPathComponent
            logMessage += "[\(fileName):\(line) \(function)] "
        }
        
        logMessage += message
        
        // Print to Xcode console
        #if DEBUG
        print(logMessage)
        #endif
        
        // Write to file asynchronously
        logQueue.async { [weak self] in
            self?.writeToFile(logMessage)
        }
    }
    
    private func writeToFile(_ message: String) {
        let entry = message + "\n"
        guard let data = entry.data(using: .utf8) else { return }
        
        if fileManager.fileExists(atPath: currentLogFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: currentLogFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: currentLogFileURL)
        }
    }
    
    // MARK: - Log Rotation
    
    private func rotateLogsIfNeeded() {
        let maxFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
        
        guard let attrs = try? fileManager.attributesOfItem(atPath: currentLogFileURL.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize > maxFileSize else {
            return
        }
        
        // Rotate: silkysnip.log -> silkysnip.1.log, etc.
        // We'll keep up to 5 archived logs.
        
        let maxArchives = 5
        
        // delete the oldest
        let oldestLog = logDirectory.appendingPathComponent("silkysnip.\(maxArchives).log")
        try? fileManager.removeItem(at: oldestLog)
        
        // shift others
        for i in (1..<maxArchives).reversed() {
            let src = logDirectory.appendingPathComponent("silkysnip.\(i).log")
            let dst = logDirectory.appendingPathComponent("silkysnip.\(i+1).log")
            if fileManager.fileExists(atPath: src.path) {
                try? fileManager.moveItem(at: src, to: dst)
            }
        }
        
        // move current to .1
        let archive1 = logDirectory.appendingPathComponent("silkysnip.1.log")
        try? fileManager.moveItem(at: currentLogFileURL, to: archive1)
        
        // Start fresh
        log(.info, "Log rotated. Previous log archived.")
    }
    
    // MARK: - Export
    
    func getLogFileURL() -> URL {
        return currentLogFileURL
    }
    
    func getAllLogFiles() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.lastPathComponent.contains("silkysnip") && $0.pathExtension == "log" }
    }
}
