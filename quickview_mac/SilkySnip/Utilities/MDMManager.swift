//
//  MDMManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Foundation

/// MDMManager provides Mobile Device Management (MDM) support for enterprise deployment
/// Settings can be configured via MDM profiles or managed preferences
final class MDMManager {
    
    static let shared = MDMManager()
    
    // MDM Configuration Keys
    private let mdmDomain = "com.silkysnip.app.managed"
    
    private init() {
        // Load MDM settings on init
        loadManagedConfiguration()
    }
    
    // MARK: - MDM Settings Keys
    
    struct Keys {
        static let disableExport = "DisableExport"
        static let disableCopy = "DisableCopy"
        static let disableAnnotations = "DisableAnnotations"
        static let auditLoggingRequired = "AuditLoggingRequired"
        static let maxCacheAgeDays = "MaxCacheAgeDays"
        static let allowedExportFormats = "AllowedExportFormats"
        static let enforceWatermark = "EnforceWatermark"
        static let watermarkText = "WatermarkText"
        static let disableOCR = "DisableOCR"
        static let requireAutoCopy = "RequireAutoCopy"
    }
    
    // MARK: - Configuration Values
    
    /// Whether export functionality is disabled by MDM
    var isExportDisabled: Bool {
        return UserDefaults.standard.bool(forKey: mdmKey(Keys.disableExport))
    }
    
    /// Whether copy to clipboard is disabled by MDM
    var isCopyDisabled: Bool {
        return UserDefaults.standard.bool(forKey: mdmKey(Keys.disableCopy))
    }
    
    /// Whether annotation tools are disabled by MDM
    var areAnnotationsDisabled: Bool {
        return UserDefaults.standard.bool(forKey: mdmKey(Keys.disableAnnotations))
    }
    
    /// Whether audit logging is required (cannot be disabled)
    var isAuditLoggingRequired: Bool {
        return UserDefaults.standard.bool(forKey: mdmKey(Keys.auditLoggingRequired))
    }
    
    /// Maximum cache age in days (0 = use default)
    var maxCacheAgeDays: Int {
        let days = UserDefaults.standard.integer(forKey: mdmKey(Keys.maxCacheAgeDays))
        return days > 0 ? days : 2 // Default: 2 days
    }
    
    /// Allowed export formats (empty = all allowed)
    var allowedExportFormats: [String] {
        return UserDefaults.standard.stringArray(forKey: mdmKey(Keys.allowedExportFormats)) ?? []
    }
    
    /// Whether watermarks are enforced
    var isWatermarkEnforced: Bool {
        return UserDefaults.standard.bool(forKey: mdmKey(Keys.enforceWatermark))
    }
    
    /// Custom watermark text
    var watermarkText: String? {
        return UserDefaults.standard.string(forKey: mdmKey(Keys.watermarkText))
    }
    
    /// Whether OCR is disabled
    var isOCRDisabled: Bool {
        return UserDefaults.standard.bool(forKey: mdmKey(Keys.disableOCR))
    }
    
    // MARK: - Helper Methods
    
    private func mdmKey(_ key: String) -> String {
        return "\(mdmDomain).\(key)"
    }
    
    private func loadManagedConfiguration() {
        // Check for managed app configuration (MDM profile)
        if let managedConfig = UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed") {
            // Apply managed configuration
            for (key, value) in managedConfig {
                UserDefaults.standard.set(value, forKey: mdmKey(key))
            }
            Logger.shared.info("Loaded MDM configuration")
        }
    }
    
    /// Check if a specific action is allowed by MDM policy
    func isActionAllowed(_ action: MDMAction) -> Bool {
        switch action {
        case .export:
            return !isExportDisabled
        case .copy:
            return !isCopyDisabled
        case .annotate:
            return !areAnnotationsDisabled
        case .ocr:
            return !isOCRDisabled
        }
    }
    
    /// Check if an export format is allowed
    func isExportFormatAllowed(_ format: String) -> Bool {
        let allowed = allowedExportFormats
        return allowed.isEmpty || allowed.contains(format.uppercased())
    }
    
    // MARK: - MDM Actions
    
    enum MDMAction {
        case export
        case copy
        case annotate
        case ocr
    }
}
