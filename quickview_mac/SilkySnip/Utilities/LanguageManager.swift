//
//  LanguageManager.swift
//  SilkySnip
//
//  Created by SilkySnip Assistant on 2026-01-28.
//

import Foundation

class LanguageManager {
    static let shared = LanguageManager()
    
    private let kAppLanguage = "AppLanguage"
    private let kAppleLanguages = "AppleLanguages"
    
    struct Language {
        let code: String
        let name: String
    }
    
    let availableLanguages: [Language] = [
        Language(code: "system", name: "System Default"),
        Language(code: "ar", name: "العربية (Arabic)"),
        Language(code: "zh-Hans", name: "简体中文 (Chinese Simplified)"),
        Language(code: "en", name: "English"),
        Language(code: "fr", name: "Français (French)"),
        Language(code: "de", name: "Deutsch (German)"),
        Language(code: "hi", name: "हिन्दी (Hindi)"),
        Language(code: "ja", name: "日本語 (Japanese)"),
        Language(code: "pt", name: "Português (Portuguese)"),
        Language(code: "ru", name: "Русский (Russian)"),
        Language(code: "es", name: "Español (Spanish)")
    ]
    
    var currentLanguageCode: String {
        get {
            return UserDefaults.standard.string(forKey: kAppLanguage) ?? "system"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kAppLanguage)
            setAppleLanguages(newValue)
            
            // Reload bundle
            loadBundle(for: newValue)
            
            // Notify observers
            NotificationCenter.default.post(name: Notification.Name("LanguageChanged"), object: nil)
        }
    }
    
    private var bundle: Bundle?
    
    private init() {
        // Load initial bundle
        let code = UserDefaults.standard.string(forKey: kAppLanguage) ?? "system"
        loadBundle(for: code)
        
        // Listen for system language changes
        NotificationCenter.default.addObserver(self, selector: #selector(systemLocaleDidChange), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func systemLocaleDidChange() {
        // Only update if we are in "system" mode
        if currentLanguageCode == "system" {
            loadBundle(for: "system")
            // Notify app to refresh strings
            NotificationCenter.default.post(name: Notification.Name("LanguageChanged"), object: nil)
        }
    }
    
    // MARK: - Core Logic
    
    private func loadBundle(for code: String) {
        if code == "system" {
            // Real-time System Sync:
            // Instead of setting bundle = nil (which relies on static launch-time NSLocalizedString),
            // we actively find the best matching bundle for the CURRENT system language.
            
            // Get user's preferred languages from the system
            let preferredLanguages = Locale.preferredLanguages
            
            // Find the best match among our available languages
            // We use the available language codes to filter against system preferences
            let appCodes = availableLanguages.map { $0.code }.filter { $0 != "system" }
            
            // Bundle.preferredLocalizations returns the best match from the list we provide
            // matching the user's system preferences.
            let bestMatch = Bundle.preferredLocalizations(from: appCodes, forPreferences: preferredLanguages).first
            
            if let match = bestMatch,
               let path = Bundle.main.path(forResource: match, ofType: "lproj"),
               let languageBundle = Bundle(path: path) {
                bundle = languageBundle
                // DebugLogger.shared.log("System language changed. Loaded bundle: \(match)")
            } else {
                // Fallback to English if no match found
                if let path = Bundle.main.path(forResource: "en", ofType: "lproj") {
                     bundle = Bundle(path: path)
                } else {
                    bundle = nil
                }
            }
            return
        }
        
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            bundle = languageBundle
        } else {
            // Fallback to English or Base
            if let path = Bundle.main.path(forResource: "en", ofType: "lproj") {
                 bundle = Bundle(path: path)
            } else {
                bundle = nil
            }
        }
    }
    
    func string(_ key: String) -> String {
        if let bundle = bundle {
            let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key {
                return localized
            }
        }
        
        // Fallback to English bundle if string is missing in current language
        if let engPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let engBundle = Bundle(path: engPath) {
            let engLocalized = engBundle.localizedString(forKey: key, value: nil, table: nil)
            if engLocalized != key {
                return engLocalized
            }
        }
        
        // Final fallback (system behavior)
        return NSLocalizedString(key, comment: "")
    }
    
    func setLanguage(_ code: String) {
        // Trigger property observer
        self.currentLanguageCode = code
    }
    
    private func setAppleLanguages(_ code: String) {
        // We still set this for next launch, but our realtime logic overrides it for current session
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: kAppleLanguages)
        } else {
            UserDefaults.standard.set([code], forKey: kAppleLanguages)
        }
        UserDefaults.standard.synchronize()
    }
}

