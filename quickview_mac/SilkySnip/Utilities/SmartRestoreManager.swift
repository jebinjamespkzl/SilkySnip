//
//  SmartRestoreManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Cocoa

class SmartRestoreManager {
    
    static let shared = SmartRestoreManager()
    
    private init() {
        startMonitoring()
    }
    
    // MARK: - Properties
    
    /// Map of Screenshot ID -> Set of Bundle IDs to pin to
    private var pinnedApps: [UUID: Set<String>] = [:]
    
    /// Whether Smart Restore is enabled globally
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "SmartRestoreEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "SmartRestoreEnabled") }
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidHide(_:)),
            name: NSWorkspace.didHideApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidUnhide(_:)),
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil
        )
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - Pinning API
    
    func pinOverlay(_ overlayID: UUID, toAppBundleID bundleID: String) {
        if pinnedApps[overlayID] == nil {
            pinnedApps[overlayID] = []
        }
        pinnedApps[overlayID]?.insert(bundleID)
        Logger.shared.info("Pinned overlay \(overlayID) to \(bundleID)")
        
        // Immediately update visibility?
        // Maybe. If the app is active, it stays visible. If not, it might hide?
        // Logic: Pinning means "Show ONLY when this app is active" or "Show ALSO when this app is active"?
        // Usually, pinning means "Associate with".
        // If I pin to Xcode, I want it to be visible when Xcode is key.
        // If I switch to Chrome (not pinned), should it hide?
        // Only if "Smart Restore" implies exclusive visibility.
        // Let's assume: If an overlay is pinned to ANY app, it hides if NONE of those apps are active.
        updateOverlayVisibility(overlayID: overlayID)
    }
    
    func unpinOverlay(_ overlayID: UUID, fromAppBundleID bundleID: String) {
        pinnedApps[overlayID]?.remove(bundleID)
        if pinnedApps[overlayID]?.isEmpty == true {
            pinnedApps.removeValue(forKey: overlayID)
        }
        Logger.shared.info("Unpinned overlay \(overlayID) from \(bundleID)")
    }
    
    func isPinned(_ overlayID: UUID) -> Bool {
        return pinnedApps[overlayID] != nil && !pinnedApps[overlayID]!.isEmpty
    }
    
    func getPinnedApps(for overlayID: UUID) -> Set<String> {
        return pinnedApps[overlayID] ?? []
    }
    
    func clearPins(for overlayID: UUID) {
        pinnedApps.removeValue(forKey: overlayID)
    }
    
    // MARK: - Logic
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard isEnabled else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        Logger.shared.info("App Activated: \(bundleID)")
        checkVisibilityForAllOverlays(activeBundleID: bundleID)
    }
    
    @objc private func appDidHide(_ notification: Notification) {
        // If hidden, we might need to re-evaluate what's visible?
        // Usually didActivate fires for the new app.
        // But if we hide an app, Finder might become active.
    }
    
    @objc private func appDidUnhide(_ notification: Notification) {
        // Similar to activate
    }
    
    private func checkVisibilityForAllOverlays(activeBundleID: String) {
        // We need access to active overlays. This manager doesn't track OverlayWindows directly.
        // We can use a delegate or notification?
        // Or simply post a notification "SmartRestoreUpdate" and let OverlayWindow handle it?
        // Or we pass the list of overlays to check?
        
        // Better: Maintain weak refs? Or just use NotificationCenter.
        NotificationCenter.default.post(name: .smartRestoreCheckVisibility, object: nil, userInfo: ["activeBundleID": activeBundleID])
    }
    
    private func updateOverlayVisibility(overlayID: UUID) {
         if let activeApp = NSWorkspace.shared.frontmostApplication,
            let bundleID = activeApp.bundleIdentifier {
             checkVisibilityForAllOverlays(activeBundleID: bundleID)
         }
    }
}

extension Notification.Name {
    static let smartRestoreCheckVisibility = Notification.Name("smartRestoreCheckVisibility")
}
