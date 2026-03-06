import Foundation
import Cocoa

class LogManager {
    static let shared = LogManager()
    
    private let fileManager = FileManager.default
    private let logFileName = "silkysnip_log.txt"
    private var logFileURL: URL?
    
    // System Info Cache
    private var systemInfo: String = ""
    
    private init() {
        setupLogFile()
        generateSystemReport()
        log("App Launched: SilkySnip \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
        log(systemInfo)
    }
    
    private func setupLogFile() {
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            logFileURL = documentsURL.appendingPathComponent(logFileName)
            
            // Optional: Rotate logs if too large, for now just append
        }
    }
    
    private func generateSystemReport() {
        var report = "\n=== SYSTEM REPORT ===\n"
        
        // 1. App Info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        report += "App Version: \(appVersion) (Build \(buildNumber))\n"
        
        // 2. System & OS
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        report += "OS Version: macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)\n"
        report += "Locale: \(Locale.current.identifier)\n"
        
        // 3. Device Hardware
        report += "Model: \(getMacModel())\n"
        report += "Processors: \(ProcessInfo.processInfo.activeProcessorCount)\n"
        report += "Physical Memory: \(ProcessInfo.processInfo.physicalMemory / 1024 / 1024) MB\n"
        
        // 4. Runtime Resources
        report += "Disk Space (Free): \(getFreeDiskSpace()) MB\n"
        
        report += "=====================\n"
        self.systemInfo = report
    }
    
    func log(_ message: String, type: LogType = .info) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let logEntry = "[\(timestamp)] [\(type.rawValue.uppercased())] \(message)\n"
        
        // Print to console (Debug)
        #if DEBUG
        print(logEntry)
        #endif
        
        // Write to file
        writeToFile(logEntry)
    }
    
    private func writeToFile(_ text: String) {
        guard let fileURL = logFileURL, let data = text.data(using: .utf8) else { return }
        
        if fileManager.fileExists(atPath: fileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }
    
    // MARK: - Helpers
    
    private func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private func getFreeDiskSpace() -> Int64 {
        if let home = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            if let freeSize = home[.systemFreeSize] as? Int64 {
                return freeSize / 1024 / 1024 // MB
            }
        }
        return 0
    }
}

enum LogType: String {
    case info
    case warning
    case error
    case crash
}

// Global helper for easy access
func QVLog(_ message: String, type: LogType = .info) {
    LogManager.shared.log(message, type: type)
}
