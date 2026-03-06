//
//  CrashHandler.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Foundation
import Cocoa

final class CrashHandler {
    static let shared = CrashHandler()
    
    private let fileManager = FileManager.default
    private let crashMarkerFile: URL
    
    private init() {
        guard let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            crashMarkerFile = URL(fileURLWithPath: "/tmp/silkysnip_crash_marker")
            return
        }
        let crashDir = libraryDir.appendingPathComponent("Logs/SilkyApple/SilkySnip/Crashes")
        crashMarkerFile = crashDir.appendingPathComponent(".crash_marker")
        
        try? fileManager.createDirectory(at: crashDir, withIntermediateDirectories: true, attributes: nil)
    }
    
    func setup() {
        // Handle uncaught exceptions
        NSSetUncaughtExceptionHandler { exception in
            CrashHandler.shared.handleException(exception)
        }
        
        // Handle signals (SIGABRT, SIGSEGV, etc.)
        signal(SIGABRT) { signal in CrashHandler.shared.handleSignal(signal) }
        signal(SIGSEGV) { signal in CrashHandler.shared.handleSignal(signal) }
        signal(SIGBUS) { signal in CrashHandler.shared.handleSignal(signal) }
        signal(SIGTRAP) { signal in CrashHandler.shared.handleSignal(signal) }
        signal(SIGILL) { signal in CrashHandler.shared.handleSignal(signal) }
        
        Logger.shared.info("CrashHandler installed")
    }
    
    func hasPendingCrashReport() -> Bool {
        return fileManager.fileExists(atPath: crashMarkerFile.path)
    }
    
    func clearPendingCrashReport() {
        try? fileManager.removeItem(at: crashMarkerFile)
    }
    
    // MARK: - Handling
    
    private func handleException(_ exception: NSException) {
        let stackTrace = exception.callStackSymbols.joined(separator: "\n")
        let message = "CRASH: Uncaught Exception: \(exception.name.rawValue)\nReason: \(exception.reason ?? "Unknown")\nStack Trace:\n\(stackTrace)"
        
        saveCrashReport(message)
    }
    
    private func handleSignal(_ signal: Int32) {
        // CRITICAL: Signal handlers must be async-signal-safe.
        // Only POSIX async-signal-safe functions are allowed here.
        // No Swift String, no closures, no ObjC runtime, no memory allocation.
        
        // Write a fixed message to stderr using only write() syscall
        let msg: StaticString = "CRASH: Fatal signal received. See macOS crash reporter for details.\n"
        msg.withUTF8Buffer { buf in
            _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
        }
        
        // Re-raise signal with default handler so macOS crash reporter captures it
        Darwin.signal(signal, SIG_DFL)
        Darwin.kill(Darwin.getpid(), signal)
    }
    
    private func saveCrashReport(_ message: String) {
        // Log to standard logger
        Logger.shared.critical(message)
        
        // Also log to persistent AuditLogger
        AuditLogger.shared.logCrash(message: message)
        
        // Force flush logger if possible (Logger handles this by simple append, but we are crashing so it might be racy. 
        // We'll trust the OS to flush the file handle or minimal loss)
        
        // Create marker
        try? "crash_occurred".write(to: crashMarkerFile, atomically: true, encoding: .utf8)
        
        // Also write a discrete crash file
        let crashDir = crashMarkerFile.deletingLastPathComponent()
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileURL = crashDir.appendingPathComponent("crash_\(timestamp).txt")
        try? message.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
