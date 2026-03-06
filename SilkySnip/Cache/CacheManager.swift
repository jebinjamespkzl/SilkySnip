//
//  CacheManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import CryptoKit
import UniformTypeIdentifiers

class CacheManager {
    
    static let shared = CacheManager()
    
    // MARK: - Properties
    
    private let cacheURL: URL
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    /// Background queue for async disk I/O
    private let diskQueue = DispatchQueue(label: "com.silkysnip.cache.disk", qos: .utility)
    
    private var lastClosedID: UUID?
    
    /// In-memory cache for pending saves to fix race conditions
    private var pendingSaves: [UUID: CacheEntry] = [:]
    
    /// Use HEIC format for ~50% smaller cache files with same quality
    private let useHEIC: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        cacheURL = Constants.cacheURL
        
        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Save (Async)
    
    // Entanglement: Require Key
    func save(_ metadata: CaptureMetadata, image: CGImage, key: SymmetricKey) {
        let fileExtension = useHEIC ? "heic" : "png"
        let imageURL = cacheURL.appendingPathComponent("\(metadata.id.uuidString).\(fileExtension)")
        let metadataURL = cacheURL.appendingPathComponent("\(metadata.id.uuidString).json")
        
        // Fix Race Condition: Store in pending saves immediately on Main Thread
        let entry = CacheEntry(metadata: metadata, image: image)
        self.pendingSaves[metadata.id] = entry
        self.lastClosedID = metadata.id
        
        // Save on background queue for performance
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Save image as HEIC (or PNG fallback)
            self.saveImage(image, to: imageURL)
            
            // Save metadata as JSON (Encrypted)
            do {
                let jsonData = try self.encoder.encode(metadata)
                
                // AES-GCM Encryption
                let sealedBox = try AES.GCM.seal(jsonData, using: key)
                guard let combined = sealedBox.combined else { throw NSError(domain: "Crypto", code: -1) }
                
                try combined.write(to: metadataURL)
                
                DispatchQueue.main.async {
                    // Remove from pending saves now that it's persisted
                    // (Optional: keep it as MRU cache, but for now just clear to save memory)
                    // We delay removal slightly to ensure filesystem flush? No need.
                    if self.pendingSaves[metadata.id] != nil {
                         // Actually, keep it for a bit? No, restore will load from disk if missing.
                         // But for perf, maybe keep it? Use strict cleanup.
                         // For now, remove it to avoid double memory usage if user doesn't restore.
                         self.pendingSaves.removeValue(forKey: metadata.id)
                    }
                }
                print("Cached screenshot: \(metadata.id) (Encrypted)")
                
                // Enforce 50-file limit
                self.pruneCache()
                
            } catch {
                print("Failed to save cache metadata: \(error)")
                DispatchQueue.main.async {
                    self.pendingSaves.removeValue(forKey: metadata.id)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func saveImage(_ image: CGImage, to url: URL) {
        if useHEIC {
            // Save as HEIC
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                if !CGImageDestinationFinalize(dest) {
                    // Fallback to PNG on HEIC failure
                    savePNG(image, to: url)
                }
            } else {
                savePNG(image, to: url)
            }
        } else {
            savePNG(image, to: url)
        }
    }
    
    private func savePNG(_ image: CGImage, to url: URL) {
        let pngURL = url.deletingPathExtension().appendingPathExtension("png")
        if let dest = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }
    
    private func pruneCache() {
        // Keep only most recent 50 files
        guard let files = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: [.creationDateKey]) else { return }
        
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        if jsonFiles.count <= 50 { return }
        
        let sortedFiles = jsonFiles.sorted { file1, file2 in
            let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2 // Newest first
        }
        
        // Remove oldest files beyond limit
        for file in sortedFiles.dropFirst(50) {
            // H3: Try both formats to avoid orphaned files when preference changes
            let heicURL = file.deletingPathExtension().appendingPathExtension("heic")
            let pngURL = file.deletingPathExtension().appendingPathExtension("png")
            try? fileManager.removeItem(at: file)
            try? fileManager.removeItem(at: heicURL)
            try? fileManager.removeItem(at: pngURL)
        }
    }

    // MARK: - Restore
    
    func restoreLastClosed(key: SymmetricKey) -> CacheEntry? {
        // Check pending saves first (Fast Path)
        if let lastId = lastClosedID, let pending = pendingSaves[lastId] {
            // Clear last ID so next restore gets previous one? 
            // Logic: restoreLastClosed implies stack behavior?
            // Current logic just restores "the" last closed.
            // If we want stack, we need a stack of IDs.
            // For now, preserve existing behavior: toggle behavior or single-level?
            // "restoreLastClosed" name implies one.
            print("Restored from pending saves: \(lastId)")
            lastClosedID = nil 
            return pending
        }
        
        guard let id = lastClosedID else {
            // Try to find the most recent cached entry
            return getMostRecentEntry(key: key)
        }
        
        return restore(id: id, key: key)
    }
    
    func restore(id: UUID, key: SymmetricKey) -> CacheEntry? {
        // Check pending saves
        if let pending = pendingSaves[id] {
             return pending
        }

        // Try HEIC first, then PNG for backwards compatibility
        var imageURL = cacheURL.appendingPathComponent("\(id.uuidString).heic")
        if !fileManager.fileExists(atPath: imageURL.path) {
            imageURL = cacheURL.appendingPathComponent("\(id.uuidString).png")
        }
        let metadataURL = cacheURL.appendingPathComponent("\(id.uuidString).json")
        
        guard fileManager.fileExists(atPath: imageURL.path),
              fileManager.fileExists(atPath: metadataURL.path) else {
            print("Cache entry not found: \(id)")
            return nil
        }
        
        do {
            let encryptedData = try Data(contentsOf: metadataURL)
            
            // AES-GCM Decryption (Entanglement Check)
            // If key is wrong (cracked app), this throws and fails.
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let jsonData = try AES.GCM.open(sealedBox, using: key)
            
            let metadata = try decoder.decode(CaptureMetadata.self, from: jsonData)
            
            // Use CGImageSource for better HEIC/PNG compatibility
            guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                print("Failed to load cached image")
                return nil
            }
            
            // IMPORTANT: Keep files in cache for multiple restores
            // Files will only be removed by pruneCache() (50 file limit)
            // or cleanup() (12 hour expiry)
            
            // Clear lastClosedID if we just restored it
            if id == lastClosedID {
                lastClosedID = nil
            }
            
            print("Restored screenshot: \(id) (kept in cache)")
            return CacheEntry(metadata: metadata, image: cgImage)
            
        } catch {
            print("Failed to restore cache entry (Decryption Failed?): \(error)")
            return nil
        }
    }
    
    private func getMostRecentEntry(key: SymmetricKey) -> CacheEntry? {
        // Check pending saves first
        // Sort by timestamp
        if let pendingRecent = pendingSaves.values.sorted(by: { $0.metadata.timestamp > $1.metadata.timestamp }).first {
            return pendingRecent
        }
    
        let entries = getAllEntries(key: key)
        
        guard let mostRecent = entries.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }
        
        return restore(id: mostRecent.id, key: key)
    }
    
    private func getAllEntries(key: SymmetricKey) -> [(id: UUID, timestamp: Date)] {
        var entries: [(id: UUID, timestamp: Date)] = []
        
        // Add pending saves
        for (_, entry) in pendingSaves {
            entries.append((id: entry.metadata.id, timestamp: entry.metadata.timestamp))
        }
        
        guard let files = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil) else {
            return entries
        }
        
        for file in files where file.pathExtension == "json" {
            guard let encryptedData = try? Data(contentsOf: file) else { continue }
            
            // Try decrypt
            do {
                let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
                let jsonData = try AES.GCM.open(sealedBox, using: key)
                let metadata = try decoder.decode(CaptureMetadata.self, from: jsonData)
                entries.append((id: metadata.id, timestamp: metadata.timestamp))
            } catch {
                // Ignore failures (e.g. wrong key, unencrypted old file)
            }
        }
        
        return entries
    }
    
    // MARK: - Restore All
    
    /// Returns headers only (lightweight) to avoid memory spikes
    func getAllCachedMetadata(key: SymmetricKey) -> [CaptureMetadata] {
        var metadatas: [CaptureMetadata] = []
        // No time limit, rely on pruneCache (50 items)
        // let cutOffDate = ...
        
        // Add pending saves
        for entry in pendingSaves.values {
            metadatas.append(entry.metadata)
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: [.contentModificationDateKey])
            let metadataFiles = files.filter { $0.pathExtension == "json" }
            
            for url in metadataFiles {
                // Skip date check, return all valid metadata files
                /*
                if let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                   let date = attrs.contentModificationDate,
                   date < cutOffDate {
                    continue
                }
                */
                
                if let encryptedData = try? Data(contentsOf: url),
                   let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
                   let jsonData = try? AES.GCM.open(sealedBox, using: key),
                   let metadata = try? decoder.decode(CaptureMetadata.self, from: jsonData) {
                    metadatas.append(metadata)
                }
            }
        } catch {
            print("Failed to list cache directory: \(error)")
        }
        
        return metadatas.sorted { $0.timestamp > $1.timestamp }
    }
    
    func getCachedImage(for id: UUID) -> CGImage? {
        // Check pending
        if let pending = pendingSaves[id] {
            return pending.image
        }
        
        // Try HEIC first, then PNG
        var imageURL = cacheURL.appendingPathComponent("\(id.uuidString).heic")
        if !fileManager.fileExists(atPath: imageURL.path) {
            imageURL = cacheURL.appendingPathComponent("\(id.uuidString).png")
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        return image
    }
    
    // Deprecated: Uses too much memory for large sets
    func getAllCachedEntries(key: SymmetricKey) -> [CacheEntry] {
        // ... (kept for backward compatibility if needed, using new methods)
        let metadatas = getAllCachedMetadata(key: key)
        var entries: [CacheEntry] = []
        for meta in metadatas {
            if let image = getCachedImage(for: meta.id) {
                entries.append(CacheEntry(metadata: meta, image: image))
            }
        }
        return entries
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Remove files older than 30 days - DISABLED as per user request (Keep last 50)
        // let cutOffDate = Date().addingTimeInterval(-30 * 24 * 3600)
        
        // We rely on pruneCache() called during save to keep size in check
        // do { ... } catch { ... }
    }
    
    func clearAll() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        
        lastClosedID = nil
        print("Cache cleared")
    }
    
    // MARK: - Info
    
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        guard let files = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        for file in files {
            if let size = try? fileManager.attributesOfItem(atPath: file.path)[.size] as? Int64 {
                totalSize += size
            }
        }
        
        return totalSize
    }
    
    func getCacheEntryCount() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil) else {
            return 0
        }
        
        return files.filter { $0.pathExtension == "json" }.count
    }
}

// MARK: - Cache Entry

struct CacheEntry {
    let metadata: CaptureMetadata
    let image: CGImage
}
