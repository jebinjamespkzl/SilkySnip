import Foundation
import Cocoa

/// The Chaos Engine introduces subtle friction for unlicensed/tampered sessions.
class ChaosEngine {
    static let shared = ChaosEngine()
    private init() {}
    
    var isActive: Bool = false
    
    func activate() {
        isActive = true
        Logger.shared.warning("CHAOS ENGINE ACTIVATED")
    }
    
    // 1. Random Delay (non-blocking)
    func injectFriction(then action: (() -> Void)? = nil) {
        guard isActive else {
            action?()
            return
        }
        let delay = Double.random(in: 0.5...2.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action?()
        }
    }
    
    // 2. Glitch Probability (30%)
    func shouldDegradeUX() -> Bool {
        guard isActive else { return false }
        return Double.random(in: 0...1) < 0.3
    }
    
    // 3. OCR Noise
    func applyOCRNoise(original: String) -> String {
        guard isActive, !original.isEmpty else { return original }
        
        var chars = Array(original)
        let noiseCount = max(1, chars.count / 10) // 10%
        
        for _ in 0..<noiseCount {
            let idx = Int.random(in: 0..<chars.count)
            // Random ASCII printable
            let randomChar = UnicodeScalar(Int.random(in: 33...126))!
            chars[idx] = Character(randomChar)
        }
        return String(chars)
    }
}
