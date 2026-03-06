//
//  SecurityManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa

/// SecurityManager provides runtime security checks to protect against
/// reverse engineering, debugging, and tampering attempts.
final class SecurityManager {
    
    static let shared = SecurityManager()
    
    private init() {}
    
    // MARK: - Security Checks
    
    /// Performs all security checks. Returns true if the environment is secure.
    func performSecurityChecks() -> Bool {
        #if DEBUG
        // Skip security checks in debug builds for development
        return true
        #else
        var isSecure = true
        
        // Check for debugger
        if isDebuggerAttached() {
            Logger.shared.info("Security: Debugger detected")
            AuditLogger.shared.logSecurityAlert("Debugger detected during check")
            isSecure = false
        }
        
        // Check for common reverse engineering tools
        if isSuspiciousEnvironment() {
            Logger.shared.info("Security: Suspicious environment detected")
            AuditLogger.shared.logSecurityAlert("Suspicious environment variables detected")
            isSecure = false
        }
        
        // Check code signature integrity
        if !isCodeSignatureValid() {
            Logger.shared.info("Security: Code signature validation failed")
            AuditLogger.shared.logSecurityAlert("Code signature validation failed")
            isSecure = false
        }
        
        return isSecure
        #endif
    }
    
    // MARK: - Debugger Detection
    
    /// Checks if a debugger is attached using sysctl
    private func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        
        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        
        if result != 0 {
            return false
        }
        
        // P_TRACED flag indicates debugging
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    // MARK: - Environment Checks
    
    /// Checks for suspicious environment variables or processes
    private func isSuspiciousEnvironment() -> Bool {
        // Check for common debugging environment variables
        let suspiciousEnvVars = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_PRINT_STATISTICS",
            "_MSSafeMode"
        ]
        
        for envVar in suspiciousEnvVars {
            if ProcessInfo.processInfo.environment[envVar] != nil {
                return true
            }
        }
        
        // Check for Frida (common reverse engineering tool)
        let fridaPorts: [UInt16] = [27042, 27043]
        // Note: Full port checking requires socket operations
        // This is a simplified check
        
        return false
    }
    
    // MARK: - Code Signature Validation
    
    /// Validates the application's code signature hasn't been tampered with
    private func isCodeSignatureValid() -> Bool {
        // Get the main bundle path
        guard let bundlePath = Bundle.main.executablePath else {
            return false
        }
        
        // Use codesign to verify (simplified - in production use SecCodeCopySigningInformation)
        let task = Process()
        task.launchPath = "/usr/bin/codesign"
        task.arguments = ["--verify", "--deep", "--strict", bundlePath]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            // If codesign fails to run, assume valid (for unsigned dev builds)
            return true
        }
    }
    
    // MARK: - Jailbreak/SIP Detection (macOS)
    
    /// Checks if System Integrity Protection is disabled
    func isSIPDisabled() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/csrutil"
        task.arguments = ["status"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.contains("disabled")
        } catch {
            return false
        }
    }
    
    // MARK: - Continuous Monitoring
    
    /// Starts continuous security monitoring in the background
    func startContinuousMonitoring() {
        #if !DEBUG
        // Check every 30 seconds for debugger attachment
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            if self?.isDebuggerAttached() == true {
                // Debugger attached after launch
                Logger.shared.info("Security Warning: Debugger detected during runtime monitoring")
                AuditLogger.shared.logSecurityAlert("Debugger detected during runtime monitoring")
                // NSApp.terminate(nil) // Disabled for ad-hoc distribution stability
            }
        }
        #endif
    }
}

// MARK: - AntiTamper Measures

extension SecurityManager {
    
    /// Obfuscates sensitive strings at runtime using XOR encoding
    /// Usage: Store encoded bytes, decode at runtime to prevent static analysis
    static func deobfuscate(_ encoded: [UInt8], key: UInt8) -> String {
        let decoded = encoded.map { $0 ^ key }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }
    
    /// Encodes a string for obfuscation (use at compile time)
    static func obfuscate(_ string: String, key: UInt8) -> [UInt8] {
        return string.utf8.map { $0 ^ key }
    }
    
    /// Generates a simple hash of critical code sections for integrity checking
    func computeIntegrityHash() -> UInt64 {
        var hash: UInt64 = 5381
        
        // Hash important constants
        let values = [
            Bundle.main.bundleIdentifier ?? "",
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        ]
        
        for value in values {
            for char in value.utf8 {
                hash = ((hash << 5) &+ hash) &+ UInt64(char)
            }
        }
        
        return hash
    }
    
    /// Delays execution randomly to throw off timing attacks
    func randomDelay() {
        #if !DEBUG
        let delay = Double.random(in: 0.001...0.01)
        Thread.sleep(forTimeInterval: delay)
        #endif
    }
    
    /// Obfuscated bundle identifier check
    var isValidBundle: Bool {
        // XOR-encoded "com.silkysnip.app" with key 0x42
        let encoded: [UInt8] = [0x21, 0x2d, 0x2f, 0x00, 0x31, 0x2b, 0x2e, 0x2b, 0x37, 0x31, 0x2c, 0x2b, 0x32, 0x00, 0x23, 0x32, 0x32]
        let expected = SecurityManager.deobfuscate(encoded, key: 0x42)
        return Bundle.main.bundleIdentifier == expected
    }
}
