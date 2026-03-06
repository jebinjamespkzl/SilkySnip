import Foundation
import IOKit
import CryptoKit

class HardwareInfo {
    static func getHardwareId() -> String {
        let platformUUID = getIOPlatformUUID() ?? "UNKNOWN_UUID"
        let serialNumber = getSerialNumber() ?? "UNKNOWN_SERIAL"
        
        let rawId = "\(platformUUID)|\(serialNumber)|silkysnip-mac"
        
        // SHA256 Hash
        if let data = rawId.data(using: .utf8) {
            let digest = SHA256.hash(data: data)
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        }
        
        return "ERROR_HASH_GENERATION"
    }

    private static func getIOPlatformUUID() -> String? {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        defer { IOObjectRelease(root) }
        
        if let uuid = IORegistryEntryCreateCFProperty(root, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return uuid
        }
        return nil
    }

    private static func getSerialNumber() -> String? {
        let root = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/")
        defer { IOObjectRelease(root) }
        
        if let serial = IORegistryEntryCreateCFProperty(root, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return serial
        }
        return nil
    }
}
