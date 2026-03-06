import Foundation

class FileSentinel {
    static let shared = FileSentinel()
    private var baseline: Date?
    private var source: DispatchSourceFileSystemObject?
    private var running = false
    
    // We monitor the Main Bundle executable
    private let targetURL = Bundle.main.executableURL
    
    func startGuard() {
        if running { return }
        running = true
        
        guard let url = targetURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return
        }
        
        self.baseline = date
        
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )
        
        source.setEventHandler { [weak self] in
            self?.check()
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        self.source = source
    }
    
    private func check() {
        guard let url = targetURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let current = attrs[.modificationDate] as? Date else {
             // File missing?
             triggerTamper()
             return
        }
        
        if let base = baseline, current != base {
            Logger.shared.critical("Sentinel: File Modified Runtime! \(base) vs \(current)")
            triggerTamper()
            return
        }
        
        // Future Check: Removed to allow system clock corrections without penalty.
        // We focus solely on runtime modification (injection attempts).
    }
    
    private func triggerTamper() {
        running = false
        source?.cancel()
        source = nil
        // Log critical security event
        AuditLogger.shared.logSecurityAlert("FileSentinel detected executable modification")
        ChaosEngine.shared.activate()
    }
}
