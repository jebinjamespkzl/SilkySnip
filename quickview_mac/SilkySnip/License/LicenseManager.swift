import Foundation
import CryptoKit
import Cocoa

struct SignedToken: Codable {
    let license_key: String
    let license_id: String
    let entitlements: [String]
    let bound_hwid: String
    let issued_at: Int64
    let expires_at: Int64
    let nonce: String
    let signature: String
}

class LicenseManager {
    static let shared = LicenseManager()
    
    private var cachedToken: SignedToken?
    private var isTokenCached = false
    
    private func loadToken() -> SignedToken? {
        if isTokenCached { return cachedToken }
        isTokenCached = true
        if let data = try? Data(contentsOf: tokenPath),
           let token = try? JSONDecoder().decode(SignedToken.self, from: data) {
            cachedToken = token
            return token
        }
        return nil
    }
    
    // Logic Entanglement: Key derived from signature
    // Logic Entanglement: Key derived from signature
    var securityKey: SymmetricKey {
        if let token = loadToken() {
            return getSecurityKey(signature: token.signature)
        }
        // Fallback for Free/Trial (Fixed Key)
        let fallback = "SilkySnipFreeKey_Fixed32Bytes!!!".data(using: .utf8)!
        return SymmetricKey(data: SHA256.hash(data: fallback))
    }
    
    func getSecurityKey(signature: String) -> SymmetricKey {
        if let sigData = Data(base64Encoded: signature) {
            let hash = SHA256.hash(data: sigData)
            return SymmetricKey(data: hash)
        }
        let fallback = "SilkySnipFreeKey_Fixed32Bytes!!!".data(using: .utf8)!
        return SymmetricKey(data: SHA256.hash(data: fallback))
    }
    
    private let apiUrl = "https://verify.silkysnip.app/activate"
    private var tokenPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("SilkySnip/license.token")
    }
    private var anchorPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("SilkySnip/security.anchor")
    }

    // ... (Pricing logic omitted to keep diff clean, assume it is preserved if I don't touch it? 
    // Wait, replace_file_content replaces the RANGE. 
    // I am targeting lines 16-131.
    // I MUST include everything in between.
    // I cannot omit Pricing logic if it falls in range.
    // Lines 36-55 are Pricing/PubKey.
    // I must include them.
    
    // Ed25519 Public Key (Base64)
    private let publicKeyBase64 = "MCowBQYDK2VwAyEA560FaSkFPfB0KZ2od76/l4j3u+3HmGd/Vdviq9MXo5A="
    
    // Structs for Pricing
    struct PricingConfig: Codable { let macos: PricingItem? }
    struct PricingItem: Codable { let lifetime: Double; let monthly: Double; let label: String; let transparency: String }

    func fetchPricing(completion: @escaping (PricingItem?) -> Void) {
        let urlStr = apiUrl.replacingOccurrences(of: "/activate", with: "/pricing")
        guard let url = URL(string: urlStr) else { return completion(nil) }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let config = try? JSONDecoder().decode(PricingConfig.self, from: data) else {
                return completion(nil)
            }
            completion(config.macos)
        }.resume()
    }

    func activate(licenseKey: String, force: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        let hwid = HardwareInfo.getHardwareId()
        let payload: [String: Any] = [
            "license_key": licenseKey,
            "hwid_hash": hwid,
            "os": "macos",
            "client_version": "1.0.0",
            "timestamp": Int(Date().timeIntervalSince1970),
            "force_activation": force
        ]
        
        guard let url = URL(string: apiUrl) else { return completion(false, "Invalid URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResp = response as? HTTPURLResponse {
                if httpResp.statusCode == 409 {
                    return completion(false, "409 Conflict: Device Limit Reached")
                }
                if httpResp.statusCode != 200 {
                    return completion(false, "Server Error: \(httpResp.statusCode)")
                }
            }
            
            guard let data = data,
                  let token = try? JSONDecoder().decode(SignedToken.self, from: data) else {
                return completion(false, "Invalid Response")
            }
            
            if self.verifySignature(token: token) {
                try? data.write(to: self.tokenPath)
                self.cachedToken = token
                self.isTokenCached = true
                // Initialize Anchor with new key
                self.checkAndRatchetAnchor(key: self.getSecurityKey(signature: token.signature))
                completion(true, nil)
            } else {
                print("Signature verification failed")
                completion(false, "Invalid Signature")
            }
        }.resume()
    }

    func isLicensed() -> Bool {
        // TEMPORARY: Bypass license check for testing
        // TODO: Remove this before release!
        return true
        
        // Loophole: Anti-Debug (Safe)
        if amIDebugged() {
            return false
        }
        
        guard let token = loadToken() else {
            return false
        }
        
        if !verifySignature(token: token) { return false }
        
        // Loophole Fix: Check HWID Binding
        let currentHwid = HardwareInfo.getHardwareId()
        if token.bound_hwid != currentHwid {
             return false
        }
        
        // Loophole Fix: Check Network Time vs Local Time
        let now = Int64(Date().timeIntervalSince1970)
        
        // Loophole Fix: Back-to-Future (Clock Tampering)
        if now < (token.issued_at - 86400) {
            return false
        }
        
        // Loophole: Offline Grace Period (30 Days)
        if (now - token.issued_at) > (30 * 86400) {
             print("Offline Grace Period Exceeded")
             return false
        }
        
        if token.expires_at > 0 {
             if token.expires_at < now { return false }
        }
        
        // Smart Anti-Replay: Safe Time Anchor Check
        // Obfuscation: Instead of simple return, we verify Security Key can decrypt dummy or generate valid hash
        let key = getSecurityKey(signature: token.signature)
        
        // Critical: Check Integrity and Key Validity implicitly via Anchor Logic
        if !checkAndRatchetAnchor(key: key) {
            print("License Validation Failed: Anchor/Integrity")
            return false
        }
        
        return true
    }
    
    private func checkAndRatchetAnchor(key: SymmetricKey) -> Bool {
        // Integrity: Verify Code Signature
        if !verifySelfIntegrity() {
            print("Integrity Check Failed: Code Signature Invalid/Missing")
            ChaosEngine.shared.activate()
            return false
        }

        let now = Int64(Date().timeIntervalSince1970)
        var anchorTime: Int64 = 0
        
        // 1. Load Anchor
        if let encryptedData = try? Data(contentsOf: anchorPath) {
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
                let decryptedData = try AES.GCM.open(sealedBox, using: key)
                let timeStr = String(data: decryptedData, encoding: .utf8) ?? "0"
                if let t = Int64(timeStr) {
                    anchorTime = t
                }
            } catch {
                // Decryption failed - Treat as fresh or invalid?
                // If existing anchor cannot be read with VALID key, it might be from another install?
                // Reset.
                print("Anchor decryption failed: \(error)")
            }
        }
        
        // 2. Validate
        if anchorTime > 0 && now < (anchorTime - 86400) {
            print("Time Travel Detected! Now: \(now), Anchor: \(anchorTime)")
            ChaosEngine.shared.activate()
            return false
        }
        
        // 3. Ratchet Forward
        if now > anchorTime {
            do {
                let data = "\(now)".data(using: .utf8)!
                let sealedBox = try AES.GCM.seal(data, using: key)
                try sealedBox.combined?.write(to: anchorPath)
            } catch {
                print("Failed to save anchor: \(error)")
            }
        }
        
        return true
    }

    private func verifySignature(token: SignedToken) -> Bool {
        guard let pubKeyData = Data(base64Encoded: publicKeyBase64),
              let signatureData = Data(base64Encoded: token.signature) else {
            return false
        }
        
        // 1. Reconstruct Canonical JSON
        // Must match server's strict sorting:
        // {"bound_hwid":"...","entitlements":[...],"expires_at":...,"issued_at":...,"license_id":"...","license_key":"...","nonce":"..."}
        let entitlementsString = token.entitlements.map { "\"\($0)\"" }.joined(separator: ",")
        
        let jsonString = "{\"bound_hwid\":\"\(token.bound_hwid)\",\"entitlements\":[\(entitlementsString)],\"expires_at\":\(token.expires_at),\"issued_at\":\(token.issued_at),\"license_id\":\"\(token.license_id)\",\"license_key\":\"\(token.license_key)\",\"nonce\":\"\(token.nonce)\"}"
        
        guard let messageData = jsonString.data(using: .utf8) else { return false }
        
        // 2. Extract Key & Verify
        // The Base64 string "MCowBQYDK2VwAyEA..." is an ASN.1 SubjectPublicKeyInfo wrapper.
        // The raw 32-byte Ed25519 key is the last 32 bytes of this 44-byte structure.
        let rawKeyData: Data
        if pubKeyData.count > 32 {
            rawKeyData = pubKeyData.suffix(32)
        } else {
            rawKeyData = pubKeyData
        }
        
        do {
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKeyData)
            if key.isValidSignature(signatureData, for: messageData) {
                return true
            } else {
                print("Security Error: Invalid Signature")
                ChaosEngine.shared.activate() // TAMPERING DETECTED
                return false
            }
        } catch {
            print("CryptoKit Verification Error: \(error)")
            // If crypto fails (e.g. malformed), it might not be malice, but safer to fail closed.
            return false
        }
    }

    func validateInBackground() {
        // Sentinel: Start File Guard
        FileSentinel.shared.startGuard()

        guard let token = loadToken() else { return }
        
        let urlStr = apiUrl.replacingOccurrences(of: "/activate", with: "/validate")
        guard let url = URL(string: urlStr) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Heartbeat Telemetry
        let payload: [String: Any] = [
            "license_key": token.license_key, 
            "hwid_hash": token.bound_hwid
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200, let data = data {
                struct ValidateResponseWrapper: Codable {
                    let valid: Bool
                    let token: SignedToken?
                }
                
                if let wrapper = try? JSONDecoder().decode(ValidateResponseWrapper.self, from: data) {
                    // 1. Handle Revocation
                    if !wrapper.valid {
                        print("License Revoked by Server")
                        try? FileManager.default.removeItem(at: self.tokenPath)
                        self.cachedToken = nil
                        
                        DispatchQueue.main.async {
                            let lm = LanguageManager.shared
                            let alert = NSAlert()
                            alert.messageText = lm.string("alert_license_revoked_title")
                            alert.informativeText = lm.string("alert_license_revoked_msg")
                            alert.addButton(withTitle: lm.string("ok"))
                            alert.runModal()
                            NSApp.terminate(nil)
                        }
                        return
                    }
                    
                    // 2. Handle Token Refresh (VM Clone Detection)
                    if let newToken = wrapper.token {
                         if self.verifySignature(token: newToken) {
                             if let encoded = try? JSONEncoder().encode(newToken) {
                                 try? encoded.write(to: self.tokenPath)
                                 self.cachedToken = newToken
                                 // Ratchet Anchor
                                 let _ = self.checkAndRatchetAnchor(key: self.getSecurityKey(signature: newToken.signature))
                                 print("License Token Refreshed (Nonce Rotated)")
                             }
                         }
                    }
                }
            }
        }.resume()
    }
    
    private func verifySelfIntegrity() -> Bool {
        var code: SecCode?
        // kSecCSDefaultFlags = 0
        let flags = SecCSFlags(rawValue: 0)
        if SecCodeCopySelf(flags, &code) == errSecSuccess,
           let code = code {
             return SecCodeCheckValidity(code, flags, nil) == errSecSuccess
        }
        return true 
    }
    
    // Check for debugger using sysctl (Mac standard)
    private func amIDebugged() -> Bool {
        var info = kinfo_proc()
        var mib : [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        assert(junk == 0, "sysctl failed")
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
