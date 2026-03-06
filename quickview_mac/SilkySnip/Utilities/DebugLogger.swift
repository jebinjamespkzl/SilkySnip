//
//  DebugLogger.swift
//  SilkySnip
//
//  Compatibility wrapper for the new Logger class.
//

import Foundation

final class DebugLogger {
    static let shared = DebugLogger()
    
    private init() {}
    
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        // Forward legacy DebugLogger calls to the new Logger as debug logs
        Logger.shared.debug(message, file: file, function: function, line: line)
    }
}
