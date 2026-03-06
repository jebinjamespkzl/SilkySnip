//
//  AppDelegate.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import AudioToolbox
import UserNotifications
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    
    // MARK: - Properties
    
    // Onboarding windows
    private var welcomeWindow: WelcomeWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var preferencesWindow: PreferencesWindowController? // New
    private var aboutWindow: AboutWindowController? // New
    private var activationWindow: ActivationWindowController?
    private var isOnboardingComplete = false
    private var areScreenshotsStacked = false
    private var lastStackGroupOrigin: CGPoint?
    private var toolsMenu: NSMenu?  // Phase 31: Dynamic Tools menu



    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var regionSelector: RegionSelector?
    private var activeOverlays: [UUID: OverlayWindow] = [:]
    var lastInteractedOverlayID: UUID?

    // ... 
    
    private func showActivationWindow() {
        activationWindow = ActivationWindowController()
        activationWindow?.showWindow(self)
        // Make sure it comes to front
        NSApp.activate(ignoringOtherApps: true)
        activationWindow?.window?.makeKeyAndOrderFront(nil)
    }


    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("App Launched")
        
        // Initialize CrashHandler
        CrashHandler.shared.setup()
        
        // Check for previous crashes
        checkForPreviousCrash()
        
        // Perform security checks (anti-debugging, code signature validation)
        // Perform security checks (anti-debugging, code signature validation)
        if !SecurityManager.shared.performSecurityChecks() {
            Logger.shared.info("Security check failed - Proceeding with warning")
            // For ad-hoc builds, we allow proceeding even if strict signature checks fail
            // NSApp.terminate(nil)
        }
        
        // Start continuous security monitoring
        Logger.shared.info("Starting Security Monitoring")
        SecurityManager.shared.startContinuousMonitoring()
        Logger.shared.info("Security Monitoring Started")
        
        // Check if we need to show onboarding
        
        // Apply Dock Visibility Preference
        // Apply Dock Visibility Preference
        if UserDefaults.standard.bool(forKey: "ShowInDock") {
            NSApp.setActivationPolicy(.regular)
            // Build main menu asynchronously to ensure policy is applied
            DispatchQueue.main.async {
                self.setupMainMenu()
            }
        } else {
             NSApp.setActivationPolicy(.accessory)
             NSApp.mainMenu = nil // Clear main menu in accessory mode
        }
        
        // Check Screen Recording Permission
        // PermissionManager.shared.checkAndPromptForScreenRecording()

        // 0.5 LICENSE CHECK (BLOCKING)
        Logger.shared.info("Checking License")
        if !LicenseManager.shared.isLicensed() {
            Logger.shared.info("License not found - Showing Activation")
            showActivationWindow()
            return
        }
        Logger.shared.info("License Verified")
        
        // 0.6 Silent Heartbeat
        LicenseManager.shared.validateInBackground()

        if shouldShowOnboarding() {
            Logger.shared.info("Showing Onboarding/Welcome Window")
            showWelcomeWindow()
        } else {
            Logger.shared.info("Skipping Onboarding - Completing Setup")
            completeSetup()
        }
        
        // Listen for monitor disconnects to rescue stranded windows
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenConfigurationChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        // Prevent activeOverlays dictionary growth if windows close unexpectedly
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            if let window = notification.object as? OverlayWindow {
                self?.activeOverlays.removeValue(forKey: window.metadata.id)
            }
        }
    }
    
    @objc private func handleScreenConfigurationChange() {
        Logger.shared.info("Screen parameters changed - Checking for stranded windows")
        
        let screenRects = NSScreen.screens.map { $0.frame }
        if screenRects.isEmpty { return } // Failsafe
        
        // Target screen to move stranded windows to (Main screen with menubar)
        let targetScreen = NSScreen.main?.visibleFrame ?? screenRects[0]
        
        for window in NSApp.windows {
            // Ignore invisible windows or the menu bar status window itself
            if !window.isVisible || window.className == "NSStatusBarWindow" { continue }
            
            // Check if window is completely off all active screen regions
            let isStranded = !screenRects.contains { $0.intersects(window.frame) }
            
            if isStranded {
                Logger.shared.info("Rescuing stranded window of type: \(type(of: window))")
                let newOrigin = CGPoint(
                    x: targetScreen.midX - window.frame.width / 2,
                    y: targetScreen.midY - window.frame.height / 2
                )
                window.setFrameOrigin(newOrigin)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("App Terminating")
        hotkeyManager?.unregisterAll()
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var unsavedCount = 0
        
        // Only count overlays with actual modifications (annotations)
        for overlay in activeOverlays.values {
            if overlay.hasAnnotations {
                unsavedCount += 1
            }
        }
        
        if unsavedCount > 0 {
            let lm = LanguageManager.shared
            let alert = NSAlert()
            let autoSaveEnabled = UserDefaults.standard.bool(forKey: "AutoSaveEnabled")
            alert.messageText = autoSaveEnabled ? lm.string("alert_unsaved_title_annotations") : lm.string("alert_unsaved_title_screenshots")
            let messageFormat = lm.string("alert_unsaved_message_format")
            alert.informativeText = String(format: messageFormat, unsavedCount, unsavedCount > 1 ? "s" : "")
            alert.addButton(withTitle: lm.string("btn_review"))
            alert.addButton(withTitle: lm.string("btn_discard"))
            alert.addButton(withTitle: lm.string("btn_cancel"))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Review -> Cancel quit and bring windows to front
                NSApp.activate(ignoringOtherApps: true)
                return .terminateCancel
            } else if response == .alertSecondButtonReturn {
                // Discard -> Quit
                return .terminateNow
            } else {
                // Cancel
                return .terminateCancel
            }
        }
        
        return .terminateNow
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Prevent app from quitting when all overlays/windows are closed
        // This keeps the menu bar icon active
        return false
    }
    
    // MARK: - Crash Reporting
    
    private func checkForPreviousCrash() {
        if CrashHandler.shared.hasPendingCrashReport() {
            DispatchQueue.main.async {
                let alert = NSAlert()
                let lm = LanguageManager.shared
                alert.messageText = lm.string("crash_dialog_title")
                alert.informativeText = lm.string("alert_crash_message")
                alert.alertStyle = .critical
                alert.addButton(withTitle: lm.string("btn_send_report"))
                alert.addButton(withTitle: lm.string("crash_dialog_cancel"))
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    self.sendCrashReport()
                }
                
                CrashHandler.shared.clearPendingCrashReport()
            }
        }
    }
    
    private func sendCrashReport() {
        guard let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let crashDir = libraryDir.appendingPathComponent("Logs/SilkyApple/SilkySnip/Crashes")
        
        let crashFiles = (try? FileManager.default.contentsOfDirectory(at: crashDir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.contains("crash") && $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        
        var items: [Any] = ["Please describe what you were doing before the crash:\n\n"]
        
        // Attach latest log
        items.append(Logger.shared.getLogFileURL())
        
        // Attach latest crash dump
        if let latestCrash = crashFiles?.first {
            items.append(latestCrash)
        }
        
        let service = NSSharingService(named: .composeEmail)
        
        if service?.canPerform(withItems: items) == true {
            service?.recipients = ["techsupport@silkyapple.com"]
            service?.subject = "SilkySnip Mac Crash Report"
            service?.perform(withItems: items)
        } else {
            // Fallback: Show alert with instructions
            let alert = NSAlert()
            let lm = LanguageManager.shared
            alert.messageText = lm.string("email_client_not_found")
            alert.informativeText = lm.string("email_client_not_found_msg")
            alert.alertStyle = .warning
            alert.addButton(withTitle: lm.string("btn_copy_email"))
            alert.addButton(withTitle: lm.string("ok"))
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("techsupport@silkyapple.com", forType: .string)
            }
        }
    }
    
    // MARK: - Status Bar
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Use template image for proper dark/light mode support
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else {
                // Fallback to SF Symbol if custom image not found
                button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SilkySnip")
            }
            let captureShortcut = Constants.Shortcut.newCapture.displayString
            button.toolTip = "SilkySnip (\(captureShortcut))"
        }
        
        updateStatusMenu()
        
        // Listen for language changes
        // Listen for language changes
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusMenu), name: Notification.Name("LanguageChanged"), object: nil)
        
        // Phase 27: Refresh Menu immediately when Ghost Mode toggles
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusMenu), name: Notification.Name("GhostModeToggled"), object: nil)
    }
    
    // exitGhostMode removed in favor of existing turnOffGhostMode
    
    @objc private func openSettings() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
        }
        preferencesWindow?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func updateStatusMenu() {
        statusItem?.menu = createStatusMenu()
    }
    
    // MARK: - Menu Builders
    
    private func buildTimerCaptureMenuItem() -> NSMenuItem {
        let lm = LanguageManager.shared
        let timerItem = NSMenuItem(title: lm.string("menu.capture.delayed"), action: nil, keyEquivalent: "")
        timerItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer Capture")
        
        let timerMenu = NSMenu()
        let delays = [3, 5, 10]
        for delay in delays {
            let item = NSMenuItem(title: "\(delay) " + lm.string("menu.seconds"), action: #selector(startDelayedCapture(_:)), keyEquivalent: "")
            item.tag = delay
            timerMenu.addItem(item)
        }
        timerItem.submenu = timerMenu
        return timerItem
    }
    
    private func buildGlobalHotkeysMenuItem() -> NSMenuItem {
        let lm = LanguageManager.shared
        let globalHotkeysEnabled = UserDefaults.standard.object(forKey: "GlobalHotkeysEnabled") as? Bool ?? true
        let toggleItem = NSMenuItem(title: lm.string("menu.enable.hotkeys"), action: #selector(toggleGlobalHotkeys), keyEquivalent: "")
        toggleItem.state = globalHotkeysEnabled ? .on : .off
        toggleItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Hotkeys")
        return toggleItem
    }
    
    private func buildAutoCopyMenuItem() -> NSMenuItem {
        let lm = LanguageManager.shared
        let autoCopyEnabled = UserDefaults.standard.bool(forKey: "AutoCopyEnabled")
        let autoCopyItem = NSMenuItem(title: lm.string("menu.auto.copy"), action: #selector(toggleAutoCopy), keyEquivalent: "")
        autoCopyItem.state = autoCopyEnabled ? .on : .off
        autoCopyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Auto Copy")
        return autoCopyItem
    }
    
    private func buildShowInDockMenuItem() -> NSMenuItem {
        let lm = LanguageManager.shared
        let showInDock = UserDefaults.standard.bool(forKey: "ShowInDock")
        let dockItem = NSMenuItem(title: lm.string("menu.show.dock"), action: #selector(toggleShowInDock), keyEquivalent: "")
        dockItem.state = showInDock ? .on : .off
        dockItem.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Dock")
        return dockItem
    }

    private func createStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let lm = LanguageManager.shared
        
        // REMOVED: Duplicate/Misplaced Ghost Mode check at top.
        // It will be added below Hide/Unhide as requested.

        // ------------------------
        // lm already defined above
        
        // New: Ctrl+N
        let newItem = NSMenuItem(title: lm.string("menu.new"), action: #selector(startNewCaptureAction(_:)), keyEquivalent: Constants.Shortcut.newCapture.key)
        newItem.target = self
        newItem.keyEquivalentModifierMask = Constants.Shortcut.newCapture.modifiers
        newItem.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "New Capture")
        menu.addItem(newItem)
        
        // New Sticky Note (Ctrl+J)
        // Check if key exists (added recently)
        let newStickyTitle = lm.string("menu.new.sticky") 
        let noteItem = NSMenuItem(title: newStickyTitle.isEmpty ? "New SilkyNote" : newStickyTitle, action: #selector(startNewStickyNote), keyEquivalent: Constants.Shortcut.stickyNote.key)
        noteItem.keyEquivalentModifierMask = Constants.Shortcut.stickyNote.modifiers
        noteItem.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Sticky Note")
        menu.addItem(noteItem)
        
        // Timer Capture Submenu
        menu.addItem(buildTimerCaptureMenuItem())
        
        // Global Hotkeys Toggle
        menu.addItem(buildGlobalHotkeysMenuItem())
        
        menu.addItem(NSMenuItem.separator())
        
        if !activeOverlays.isEmpty {
            // Save and Copy Items
            
            let saveAllItem = NSMenuItem(title: lm.string("menu.save.all"), action: #selector(saveAllScreenshots), keyEquivalent: Constants.Shortcut.saveAll.key)
            saveAllItem.keyEquivalentModifierMask = Constants.Shortcut.saveAll.modifiers
            saveAllItem.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square", accessibilityDescription: "Save All")
            menu.addItem(saveAllItem)
            
            // Removed: Save Current (User Request)
            
            // Copy
            let copyItem = NSMenuItem(title: lm.string("menu.copy.image"), action: #selector(copyCurrentOverlay), keyEquivalent: Constants.Shortcut.copyImage.key)
            copyItem.keyEquivalentModifierMask = Constants.Shortcut.copyImage.modifiers
            copyItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy")
            menu.addItem(copyItem)
                        
            // Removed: Close Current (User Request)
            
            let closeAllItem = NSMenuItem(title: lm.string("menu.close.all"), action: #selector(closeAllScreenshots), keyEquivalent: Constants.Shortcut.closeAll.key)
            closeAllItem.keyEquivalentModifierMask = Constants.Shortcut.closeAll.modifiers
            closeAllItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Close All")
            menu.addItem(closeAllItem)
            menu.addItem(NSMenuItem.separator())
            
            if activeOverlays.count > 1 {
                if areScreenshotsStacked {
                    let ungroup = NSMenuItem(title: lm.string("menu.ungroup.all"), action: #selector(ungroupAllScreenshots), keyEquivalent: "")
                    ungroup.image = NSImage(systemSymbolName: "square.on.square.dashed", accessibilityDescription: "Ungroup")
                    menu.addItem(ungroup)
                } else {
                    let group = NSMenuItem(title: lm.string("menu.group.all"), action: #selector(groupAllScreenshots), keyEquivalent: "")
                    group.image = NSImage(systemSymbolName: "square.stack.3d.down.forward", accessibilityDescription: "Group")
                    menu.addItem(group)
                }
            }
            
            // \"Hide All\" - visible if there are visible windows
            if activeOverlays.values.contains(where: { $0.isVisible }) {
                let hideItem = NSMenuItem(title: lm.string("menu.hide.all"), action: #selector(hideAllScreenshots), keyEquivalent: Constants.Shortcut.hideAll.key)
                hideItem.keyEquivalentModifierMask = Constants.Shortcut.hideAll.modifiers
                hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide")
                menu.addItem(hideItem)
            }
            
            // "Unhide" - visible if there are hidden windows
            if activeOverlays.values.contains(where: { !$0.isVisible }) {
                let unhideItem = NSMenuItem(title: lm.string("menu.unhide"), action: #selector(unhideAllScreenshots), keyEquivalent: Constants.Shortcut.unhideAll.key)
                unhideItem.keyEquivalentModifierMask = Constants.Shortcut.unhideAll.modifiers
                unhideItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Unhide")
                menu.addItem(unhideItem)
            }
            
            // Ghost Mode Controls (in Hide/Unhide section)
            let anyGhostModeOn = activeOverlays.values.contains { $0.isGhostMode }
            
            if anyGhostModeOn {
                let turnOffItem = NSMenuItem(title: lm.string("menu.ghost.mode.off"), action: #selector(turnOffGhostMode), keyEquivalent: Constants.Shortcut.ghostMode.key)
                turnOffItem.keyEquivalentModifierMask = Constants.Shortcut.ghostMode.modifiers
                turnOffItem.image = NSImage(systemSymbolName: "hand.raised.slash", accessibilityDescription: "Exit Ghost Mode")
                menu.addItem(turnOffItem)
            } else {
                let turnOnItem = NSMenuItem(title: lm.string("menu.ghost.mode.on"), action: #selector(turnOnGhostMode), keyEquivalent: Constants.Shortcut.ghostMode.key)
                turnOnItem.keyEquivalentModifierMask = Constants.Shortcut.ghostMode.modifiers
                turnOnItem.image = NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "Enter Ghost Mode")
                menu.addItem(turnOnItem)
            }
            
            // Find SilkySnips - blink all screenshots to help locate them (in Hide/Unhide section)
            let findItem = NSMenuItem(title: lm.string("menu.find.silkysnips"), action: #selector(findSilkySnips), keyEquivalent: Constants.Shortcut.findSilkySnips.key)
            findItem.keyEquivalentModifierMask = Constants.Shortcut.findSilkySnips.modifiers
            findItem.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "Find")
            menu.addItem(findItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // Restore Last
        let restoreItem = NSMenuItem(title: lm.string("menu.restore.last"), action: #selector(restoreLastClosed), keyEquivalent: Constants.Shortcut.restoreLast.key)
        restoreItem.keyEquivalentModifierMask = Constants.Shortcut.restoreLast.modifiers
        restoreItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Restore")
        menu.addItem(restoreItem)
        
        let restoreAllItem = NSMenuItem(title: lm.string("menu.restore.all"), action: #selector(restoreAllCached), keyEquivalent: Constants.Shortcut.restoreAll.key)
        restoreAllItem.keyEquivalentModifierMask = Constants.Shortcut.restoreAll.modifiers
        restoreAllItem.image = NSImage(systemSymbolName: "clock.arrow.2.circlepath", accessibilityDescription: "Restore All")
        menu.addItem(restoreAllItem)
        
        let clearCacheItem = NSMenuItem(title: lm.string("menu.clear.cached"), action: #selector(confirmClearCache), keyEquivalent: Constants.Shortcut.clearCached.key)
        clearCacheItem.keyEquivalentModifierMask = Constants.Shortcut.clearCached.modifiers
        clearCacheItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear Cache")
        menu.addItem(clearCacheItem)
        menu.addItem(NSMenuItem.separator())
        
        // Restore Sticky Note
        let history = StickyNoteManager.shared.getHistory()
        let restoreStickyItem = NSMenuItem(title: lm.string("menu.restore.sticky"), action: #selector(restoreLastStickyNote), keyEquivalent: "")
        restoreStickyItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Restore")
        if history.isEmpty {
            restoreStickyItem.isEnabled = false
        }
        menu.addItem(restoreStickyItem)
        menu.addItem(NSMenuItem.separator())
        
        // About & Quit
        let settingsItem = NSMenuItem(title: lm.string("menu.settings"), action: #selector(showPreferences), keyEquivalent: Constants.Shortcut.preferences.key)
        settingsItem.keyEquivalentModifierMask = Constants.Shortcut.preferences.modifiers
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: lm.string("menu.about"), action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: lm.string("menu.quit"), action: #selector(confirmQuit), keyEquivalent: Constants.Shortcut.quit.key)
        quitItem.keyEquivalentModifierMask = Constants.Shortcut.quit.modifiers
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
        
        return menu
    }
    
    // MARK: - Tool Submenus
    
    // Fix: Helper to get the truly active overlay for menu state
    private func currentActiveOverlay() -> OverlayWindow? {
        // Return explicitly interacted overlay if it is still active
        if let id = lastInteractedOverlayID, let overlay = activeOverlays[id] {
            return overlay
        }
        
        // Otherwise grab frontmost system-level window
        if let activeWindow = NSApp.orderedWindows.first(where: { $0 is OverlayWindow }) as? OverlayWindow {
            return activeWindow
        }
        
        // Final fallback: the newest created overlay
        return activeOverlays.values.max { $0.metadata.timestamp < $1.metadata.timestamp }
    }
    
    private func createPenSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let lm = LanguageManager.shared
        
        // Check if pen is currently active
        let isPenActive = currentActiveOverlay()?.currentTool == .pen
        let currentPenHex = ToolManager.shared.penColor.hexString.uppercased()
        
        // Colors
        let colors = [
            (lm.string("color_black"), "#000000"),
            (lm.string("color_red"), "#FF3B30"),
            (lm.string("color_blue"), "#007AFF"),
            (lm.string("color_green"), "#34C759"),
            (lm.string("color_orange"), "#FF9500")
        ]
        
        for (name, hex) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(menuSetPenColor(_:)), keyEquivalent: "")
            colorItem.representedObject = hex
            // Only checkmark if pen is active AND color matches
            colorItem.state = (isPenActive && currentPenHex == hex.uppercased()) ? .on : .off
            submenu.addItem(colorItem)
        }
        
        submenu.addItem(NSMenuItem.separator())
        
        // Sizes
        let sizes = [lm.string("menu.pen.thin"), lm.string("menu.pen.medium"), lm.string("menu.pen.thick")]
        let currentPenSize = ToolManager.shared.penSize
        for (index, size) in sizes.enumerated() {
            let sizeItem = NSMenuItem(title: size, action: #selector(menuSetPenSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = index
            // Only checkmark if pen is active AND size matches
            sizeItem.state = (isPenActive && currentPenSize == Constants.penSizes[index]) ? .on : .off
            submenu.addItem(sizeItem)
        }
        
        return submenu
    }
    
    private func createHighlighterSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let lm = LanguageManager.shared
        
        // Check if highlighter is currently active
        let isHighlighterActive = currentActiveOverlay()?.currentTool == .highlighter
        let currentHighlighterHex = ToolManager.shared.highlighterColor.hexString.uppercased()
        
        // Colors
        let colors = [
            (lm.string("color_yellow"), "#FFFF00"),
            (lm.string("color_pink"), "#FF69B4"),
            (lm.string("color_cyan"), "#00FFFF"),
            (lm.string("color_lime"), "#00FF00"),
            (lm.string("color_orange"), "#FFA500")
        ]
        
        for (name, hex) in colors {
            let colorItem = NSMenuItem(title: name, action: #selector(menuSetHighlighterColor(_:)), keyEquivalent: "")
            colorItem.representedObject = hex
            // Only checkmark if highlighter is active AND color matches
            colorItem.state = (isHighlighterActive && currentHighlighterHex == hex.uppercased()) ? .on : .off
            submenu.addItem(colorItem)
        }
        
        return submenu
    }
    
    private func createEraserSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let lm = LanguageManager.shared
        
        // Check if eraser is currently active
        let isEraserActive = currentActiveOverlay()?.currentTool == .eraser
        let currentEraserSize = Int(ToolManager.shared.eraserSize)
        
        // Sizes
        let sizes = [(lm.string("menu.eraser.small"), 10), (lm.string("menu.eraser.medium"), 20), (lm.string("menu.eraser.large"), 40)]
        
        for (name, size) in sizes {
            let sizeItem = NSMenuItem(title: name, action: #selector(menuSetEraserSize(_:)), keyEquivalent: "")
            sizeItem.representedObject = size
            // Only checkmark if eraser is active AND size matches
            sizeItem.state = (isEraserActive && currentEraserSize == size) ? .on : .off
            submenu.addItem(sizeItem)
        }
        
        return submenu
    }
    
    // MARK: - Hotkeys
    
    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()
        registerHotkeys()
    }
    
    private func registerHotkeys() {
        // Check if global hotkeys are enabled (default is true)
        let isEnabled = UserDefaults.standard.object(forKey: "GlobalHotkeysEnabled") as? Bool ?? true
        guard isEnabled else {
            Logger.shared.info("Global hotkeys disabled by user preference")
            return
        }

        do {
            // Ctrl + N - New capture
            try hotkeyManager?.register(
                Hotkey(key: .n, modifiers: [.control]),
                handler: { [weak self] in self?.startNewCapture() }
            )
            
            // Ctrl + Shift + N - Delayed Capture (Last Used)
            try hotkeyManager?.register(
                Hotkey(key: .n, modifiers: [.control, .shift]),
                handler: { [weak self] in self?.startLastUsedDelayedCapture() }
            )
            
            // Ctrl + Z - Restore last closed
            try hotkeyManager?.register(
                Hotkey(key: .z, modifiers: [.control]),
                handler: { [weak self] in self?.restoreLastClosed() }
            )
            
            // Ctrl + S - Save
            try hotkeyManager?.register(
                Hotkey(key: .s, modifiers: [.control]),
                handler: { [weak self] in self?.saveCurrentOverlay() }
            )
            
            // Ctrl + W - Close
            try hotkeyManager?.register(
                Hotkey(key: .w, modifiers: [.control]),
                handler: { [weak self] in self?.closeCurrentOverlay() }
            )
            
            // Ctrl + Shift + C - Copy
            try hotkeyManager?.register(
                Hotkey(key: .c, modifiers: [.control, .shift]),
                handler: { [weak self] in self?.copyCurrentOverlay() }
            )
            
            // Ctrl + L - Lock/Unlock screenshot
            try hotkeyManager?.register(
                Hotkey(key: .l, modifiers: [.control]),
                handler: { [weak self] in self?.toggleLockCurrentOverlay() }
            )
            
            // Ctrl + F - Find SilkySnips
            try hotkeyManager?.register(
                Hotkey(key: .f, modifiers: [.control]),
                handler: { [weak self] in self?.findSilkySnips() }
            )
            
            // Ctrl + Shift + T - OCR Select Text
            try hotkeyManager?.register(
                Hotkey(key: .t, modifiers: [.control, .shift]),
                handler: { [weak self] in self?.selectTextCurrentOverlay() }
            )
            
            Logger.shared.info("All hotkeys registered successfully")
            
        } catch {
            Logger.shared.info("Hotkey registration failed: \(error)")
            showHotkeyConflictAlert()
        }
    }
    
    private func unregisterHotkeys() {
        hotkeyManager?.unregisterAll()
        Logger.shared.info("Hotkeys unregistered")
    }
    
    @objc func toggleGlobalHotkeys() {
        let current = UserDefaults.standard.object(forKey: "GlobalHotkeysEnabled") as? Bool ?? true
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "GlobalHotkeysEnabled")
        
        if newValue {
            registerHotkeys()
        } else {
            unregisterHotkeys()
        }
        
        // Update menu
        statusItem?.menu = createStatusMenu()
    }
    
    @objc func toggleAutoCopy() {
        let current = UserDefaults.standard.bool(forKey: "AutoCopyEnabled")
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "AutoCopyEnabled")
        
        // Update menu
        statusItem?.menu = createStatusMenu()
        Logger.shared.info("Auto Copy \(newValue ? "enabled" : "disabled")")
    }
    
    private func showHotkeyConflictAlert() {
        let alert = NSAlert()
        let lm = LanguageManager.shared
        alert.messageText = lm.string("error_hotkey_conflict")
        alert.informativeText = lm.string("alert_hotkey_conflict")
        alert.alertStyle = .warning
        alert.addButton(withTitle: lm.string("ok"))
        alert.runModal()
    }

    // MARK: - About & Appearance

    @objc func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
        }
        preferencesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAboutWindow() {
        if aboutWindow == nil {
            aboutWindow = AboutWindowController()
        }
        aboutWindow?.show()
    }

    // MARK: - Main Menu (Dock Mode)

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let lm = LanguageManager.shared
        
        // 1. App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        // About SilkySnip
        let aboutItem = NSMenuItem(title: lm.string("menu.about"), action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        appMenu.addItem(aboutItem)
        
        // Quick Toggles (from Tray Parity)
        appMenu.addItem(buildGlobalHotkeysMenuItem())
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: lm.string("menu.settings"), action: #selector(showPreferences), keyEquivalent: Constants.Shortcut.preferences.key)
        settingsItem.keyEquivalentModifierMask = Constants.Shortcut.preferences.modifiers
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        appMenu.addItem(settingsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Services
        let servicesItem = NSMenuItem(title: LanguageManager.shared.string("menu_services"), action: nil, keyEquivalent: "")
        appMenu.addItem(servicesItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Check for Updates
        let updateItem = NSMenuItem(title: lm.string("btn_check_updates"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Check for Updates")
        appMenu.addItem(updateItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Hide SilkySnip
        let hideItem = NSMenuItem(title: lm.string("menu.hide") + " SilkySnip", action: #selector(NSApplication.hide(_:)), keyEquivalent: Constants.Shortcut.hideApp.key)
        hideItem.keyEquivalentModifierMask = Constants.Shortcut.hideApp.modifiers
        hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide")
        appMenu.addItem(hideItem)
        
        // Hide Others
        let hideOthersItem = NSMenuItem(title: lm.string("menu.hide.others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: Constants.Shortcut.hideOthers.key)
        hideOthersItem.keyEquivalentModifierMask = Constants.Shortcut.hideOthers.modifiers
        hideOthersItem.image = NSImage(systemSymbolName: "rectangle.stack.badge.minus", accessibilityDescription: "Hide Others")
        appMenu.addItem(hideOthersItem)
        
        // Show All
        let showAllItem = NSMenuItem(title: lm.string("menu.show.all"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Show All")
        appMenu.addItem(showAllItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Quit SilkySnip
        let quitItem = NSMenuItem(title: lm.string("menu.quit"), action: #selector(confirmQuit), keyEquivalent: Constants.Shortcut.quit.key)
        quitItem.keyEquivalentModifierMask = Constants.Shortcut.quit.modifiers
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        appMenu.addItem(quitItem)
        
        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: lm.string("menu.file"))
        fileMenuItem.submenu = fileMenu
        
        // New Capture
        let newMenuItem = NSMenuItem(title: lm.string("menu.new"), action: #selector(startNewCaptureAction(_:)), keyEquivalent: Constants.Shortcut.newCapture.key)
        newMenuItem.target = self
        newMenuItem.keyEquivalentModifierMask = Constants.Shortcut.newCapture.modifiers
        fileMenu.addItem(newMenuItem)
        
        // Timer Capture (from Tray Parity)
        fileMenu.addItem(buildTimerCaptureMenuItem())
        
        // New Sticky Note (Advanced)
        let newStickyItem = NSMenuItem(title: LanguageManager.shared.string("menu_new_sticky_note"), action: #selector(startNewStickyNote), keyEquivalent: Constants.Shortcut.stickyNote.key)
        newStickyItem.keyEquivalentModifierMask = Constants.Shortcut.stickyNote.modifiers
        fileMenu.addItem(newStickyItem)
        
        // Save Current
        let saveMenuItem = NSMenuItem(title: lm.string("menu.save.current"), action: #selector(saveCurrentOverlay), keyEquivalent: Constants.Shortcut.saveCurrent.key)
        saveMenuItem.keyEquivalentModifierMask = Constants.Shortcut.saveCurrent.modifiers
        fileMenu.addItem(saveMenuItem)
        
        let saveAllItem = NSMenuItem(title: lm.string("menu.save.all"), action: #selector(saveAllScreenshots), keyEquivalent: Constants.Shortcut.saveAll.key)
        saveAllItem.keyEquivalentModifierMask = Constants.Shortcut.saveAll.modifiers
        fileMenu.addItem(saveAllItem)
        fileMenu.addItem(NSMenuItem.separator())
        
        // Close Current
        let closeMenuItem = NSMenuItem(title: lm.string("menu.close.current"), action: #selector(closeCurrentOverlay), keyEquivalent: Constants.Shortcut.closeCurrent.key)
        closeMenuItem.keyEquivalentModifierMask = Constants.Shortcut.closeCurrent.modifiers
        fileMenu.addItem(closeMenuItem)
        
        let closeAllItem = NSMenuItem(title: lm.string("menu.close.all"), action: #selector(closeAllScreenshots), keyEquivalent: Constants.Shortcut.closeAll.key)
        closeAllItem.keyEquivalentModifierMask = Constants.Shortcut.closeAll.modifiers
        fileMenu.addItem(closeAllItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        // Restore Last
        let restoreLastItem = NSMenuItem(title: lm.string("menu.restore.last"), action: #selector(restoreLastClosed), keyEquivalent: Constants.Shortcut.restoreLast.key)
        restoreLastItem.keyEquivalentModifierMask = Constants.Shortcut.restoreLast.modifiers
        fileMenu.addItem(restoreLastItem)
        
        // Restore All
        let restoreAllItem = NSMenuItem(title: lm.string("menu.restore.all"), action: #selector(restoreAllCached), keyEquivalent: Constants.Shortcut.restoreAll.key)
        restoreAllItem.keyEquivalentModifierMask = Constants.Shortcut.restoreAll.modifiers
        fileMenu.addItem(restoreAllItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        // Clear Cached
        let clearCacheItem = NSMenuItem(title: lm.string("menu.clear.cached"), action: #selector(confirmClearCache), keyEquivalent: Constants.Shortcut.clearCached.key)
        clearCacheItem.keyEquivalentModifierMask = Constants.Shortcut.clearCached.modifiers
        fileMenu.addItem(clearCacheItem)
        
        // 3. Edit Menu (Standard)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: lm.string("menu.edit"))
        editMenuItem.submenu = editMenu
        
        let undoItem = NSMenuItem(title: lm.string("menu.undo"), action: Selector("undo:"), keyEquivalent: Constants.Shortcut.undo.key)
        undoItem.keyEquivalentModifierMask = Constants.Shortcut.undo.modifiers
        editMenu.addItem(undoItem)
        
        let redoItem = NSMenuItem(title: lm.string("menu.redo"), action: Selector("redo:"), keyEquivalent: Constants.Shortcut.redo.key)
        redoItem.keyEquivalentModifierMask = Constants.Shortcut.redo.modifiers
        editMenu.addItem(redoItem)
        
        editMenu.addItem(NSMenuItem.separator())
        
        let cutItem = NSMenuItem(title: lm.string("menu.cut"), action: Selector("cut:"), keyEquivalent: Constants.Shortcut.cut.key)
        cutItem.keyEquivalentModifierMask = Constants.Shortcut.cut.modifiers
        editMenu.addItem(cutItem)
        
        let copyItem = NSMenuItem(title: lm.string("menu.copy"), action: Selector("copy:"), keyEquivalent: Constants.Shortcut.copy.key)
        copyItem.keyEquivalentModifierMask = Constants.Shortcut.copy.modifiers
        editMenu.addItem(copyItem)
        
        let pasteItem = NSMenuItem(title: lm.string("menu.paste"), action: Selector("paste:"), keyEquivalent: Constants.Shortcut.paste.key)
        pasteItem.keyEquivalentModifierMask = Constants.Shortcut.paste.modifiers
        editMenu.addItem(pasteItem)
        editMenu.addItem(withTitle: lm.string("menu.select.all"), action: Selector("selectAll:"), keyEquivalent: "a")

        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: lm.string("menu.view"))
        viewMenuItem.submenu = viewMenu
        
        // Find SilkySnips
        let findMenuItem = NSMenuItem(title: lm.string("menu.find.silkysnips"), action: #selector(findSilkySnips), keyEquivalent: Constants.Shortcut.findSilkySnips.key)
        findMenuItem.keyEquivalentModifierMask = Constants.Shortcut.findSilkySnips.modifiers
        viewMenu.addItem(findMenuItem)
        
        viewMenu.addItem(NSMenuItem.separator())
        
        // Hide All
        let hideAllItem = NSMenuItem(title: lm.string("menu.hide.all"), action: #selector(hideAllScreenshots), keyEquivalent: Constants.Shortcut.hideAll.key)
        hideAllItem.keyEquivalentModifierMask = Constants.Shortcut.hideAll.modifiers
        viewMenu.addItem(hideAllItem)
        
        // Unhide All
        let unhideAllItem = NSMenuItem(title: lm.string("menu.unhide"), action: #selector(unhideAllScreenshots), keyEquivalent: Constants.Shortcut.unhideAll.key)
        unhideAllItem.keyEquivalentModifierMask = Constants.Shortcut.unhideAll.modifiers
        viewMenu.addItem(unhideAllItem)
        
        // Tools Menu (Dynamic — rebuilt on open via NSMenuDelegate)
        let toolsMenuItem = NSMenuItem()
        mainMenu.addItem(toolsMenuItem)
        let toolsMenu = NSMenu(title: lm.string("menu.tools"))
        toolsMenuItem.submenu = toolsMenu
        toolsMenu.delegate = self  // Phase 31: Dynamic rebuild
        self.toolsMenu = toolsMenu
        populateToolsMenu(toolsMenu) // Initial populate


        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: lm.string("menu.window"))
        windowMenuItem.submenu = windowMenu
        
        windowMenu.addItem(withTitle: lm.string("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: lm.string("menu.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: lm.string("menu.bring.all.front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: lm.string("menu.group.all"), action: #selector(groupAllScreenshots), keyEquivalent: "")
        windowMenu.addItem(withTitle: lm.string("menu.ungroup.all"), action: #selector(ungroupAllScreenshots), keyEquivalent: "")
        
        // Sticky Notes Menu
        let notesMenuItem = NSMenuItem()
        mainMenu.addItem(notesMenuItem)
        let notesMenu = NSMenu(title: LanguageManager.shared.string("menu_sticky_notes"))
        notesMenuItem.submenu = notesMenu
        
        // Add "New Sticky Note" item inside the submenu
        let newNoteItem = NSMenuItem(title: LanguageManager.shared.string("menu_new_sticky_note"), action: #selector(startNewStickyNote), keyEquivalent: Constants.Shortcut.stickyNote.key)
        newNoteItem.keyEquivalentModifierMask = Constants.Shortcut.stickyNote.modifiers
        notesMenu.addItem(newNoteItem)
        
        notesMenu.addItem(NSMenuItem.separator())
        
        // Text Format Submenu
        let formatSubmenu = NSMenu(title: lm.string("menu.text.format"))
        let formatItem = NSMenuItem(title: lm.string("menu.text.format"), action: nil, keyEquivalent: "")
        formatItem.submenu = formatSubmenu
        notesMenu.addItem(formatItem)
        
        let boldItem = NSMenuItem(title: lm.string("format_bold"), action: #selector(stickyNoteBold), keyEquivalent: "")
        formatSubmenu.addItem(boldItem)
        
        let underlineItem = NSMenuItem(title: lm.string("format_underline"), action: #selector(stickyNoteUnderline), keyEquivalent: "")
        formatSubmenu.addItem(underlineItem)
        
        let strikeItem = NSMenuItem(title: lm.string("format_strikethrough"), action: #selector(stickyNoteStrikethrough), keyEquivalent: "")
        formatSubmenu.addItem(strikeItem)
        
        // Font Size Submenu
        let sizeSubmenu = NSMenu(title: lm.string("menu.font.size"))
        let sizeItem = NSMenuItem(title: lm.string("menu.font.size"), action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeSubmenu
        notesMenu.addItem(sizeItem)
        
        let fontSizes: [(String, FontSize)] = [
            (lm.string("sticky_font_small"), .small),
            (lm.string("sticky_font_normal"), .normal),
            (lm.string("sticky_font_large"), .large)
        ]
        for (name, size) in fontSizes {
            let item = NSMenuItem(title: name, action: #selector(stickyNoteSetFontSize(_:)), keyEquivalent: "")
            item.representedObject = size
            sizeSubmenu.addItem(item)
        }
        
        // List Style Submenu
        let listSubmenu = NSMenu(title: lm.string("menu.list.style"))
        let listItem = NSMenuItem(title: lm.string("menu.list.style"), action: nil, keyEquivalent: "")
        listItem.submenu = listSubmenu
        notesMenu.addItem(listItem)
        
        let listStyles: [(String, ListStyle)] = [
            (lm.string("list_none"), .none),
            (lm.string("list_bullet"), .bullet),
            (lm.string("list_numbered"), .numbered)
        ]
        for (name, style) in listStyles {
            let item = NSMenuItem(title: name, action: #selector(stickyNoteSetListStyle(_:)), keyEquivalent: "")
            item.representedObject = style
            listSubmenu.addItem(item)
        }
        
        // Color Submenu
        let colorSubmenu = NSMenu(title: lm.string("menu.sticky.color"))
        let colorItem = NSMenuItem(title: lm.string("menu.sticky.color"), action: nil, keyEquivalent: "")
        colorItem.submenu = colorSubmenu
        notesMenu.addItem(colorItem)
        
        let colors: [(String, String)] = [
            ("#FFEB3B", lm.string("color_select_yellow")),
            ("#FF4081", lm.string("color_select_pink")),
            ("#00E5FF", lm.string("color_select_cyan")),
            ("#76FF03", lm.string("color_select_green")),
            ("#FFFFFF", lm.string("color_select_white"))
        ]
        for (hex, name) in colors {
            let item = NSMenuItem(title: name, action: #selector(stickyNoteSetColor(_:)), keyEquivalent: "")
            item.representedObject = hex
            
            // Color swatch icon
            let swatchSize = NSSize(width: 16, height: 16)
            let swatchImage = NSImage(size: swatchSize, flipped: false) { rect in
                NSColor(hex: hex).setFill()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
                path.fill()
                NSColor.lightGray.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                return true
            }
            item.image = swatchImage
            colorSubmenu.addItem(item)
        }
        
        notesMenu.addItem(NSMenuItem.separator())
        
        let lockNotesItem = NSMenuItem(title: LanguageManager.shared.string("menu.lock.display") ?? "Lock to Display", action: #selector(stickyNoteToggleLockToDisplay), keyEquivalent: "")
        lockNotesItem.target = self
        notesMenu.addItem(lockNotesItem)
        
        notesMenu.addItem(NSMenuItem.separator())
        
        let showAllNotesItem = NSMenuItem(title: LanguageManager.shared.string("menu_show_all_sticky_notes"), action: #selector(showAllStickyNotes), keyEquivalent: "")
        showAllNotesItem.target = self
        notesMenu.addItem(showAllNotesItem)
        
        let hideAllNotesItem = NSMenuItem(title: "Hide All Sticky Notes", action: #selector(hideAllStickyNotes), keyEquivalent: "")
        hideAllNotesItem.target = self
        notesMenu.addItem(hideAllNotesItem)
        
        let unhideAllNotesItem = NSMenuItem(title: "Unhide All Sticky Notes", action: #selector(unhideAllStickyNotes), keyEquivalent: "")
        unhideAllNotesItem.target = self
        notesMenu.addItem(unhideAllNotesItem)
        
        let closeAllNotesItem = NSMenuItem(title: LanguageManager.shared.string("menu_close_all_sticky_notes"), action: #selector(closeAllStickyNotes), keyEquivalent: "")
        closeAllNotesItem.target = self
        notesMenu.addItem(closeAllNotesItem)
        
        notesMenu.addItem(NSMenuItem.separator())
        
        let restoreStickyItem = NSMenuItem(title: lm.string("menu.restore.sticky"), action: #selector(restoreLastStickyNote), keyEquivalent: "")
        notesMenu.addItem(restoreStickyItem)
        
        // 6. Help Menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: lm.string("menu.help"))
        helpMenuItem.submenu = helpMenu
        
        helpMenu.addItem(withTitle: "SilkySnip Help", action: #selector(showHelp), keyEquivalent: "?")
        
        NSApp.mainMenu = mainMenu
    }
    
    @objc func showHelp() {
        if let url = URL(string: "https://silkyapple.com/silkysnip/help") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func checkForUpdates() {
        Logger.shared.info("User requested update check")
        // In a real implementation with Sparkle linked:
        // SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil).checkForUpdates(nil)
        
        let alert = NSAlert()
        let lm = LanguageManager.shared
        alert.messageText = lm.string("alert_latest_version")
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = "SilkySnip \(version)"
        
        alert.addButton(withTitle: lm.string("ok"))
        alert.runModal()
    }

    @objc func toggleShowInDock() {
        let current = UserDefaults.standard.bool(forKey: "ShowInDock")
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "ShowInDock")
        
        if newValue {
            NSApp.setActivationPolicy(.regular)
            // Defer menu setup to ensure policy is active
            DispatchQueue.main.async {
                self.setupMainMenu()
                // Activate app to show dock icon jumping or appearing
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            NSApp.setActivationPolicy(.accessory)
            NSApp.mainMenu = nil // Disable Main Menu
        }
        
        statusItem?.menu = createStatusMenu() // Update checkbox
        Logger.shared.info("Dock Icon \(newValue ? "enabled" : "disabled")")
    }
    
    // MARK: - Phase 4.2: Timer Capture
    
    @objc func startDelayedCapture(_ sender: NSMenuItem) {
        let delay = TimeInterval(sender.tag)
        guard delay > 0 else { return }
        
        // Save preference
        UserDefaults.standard.set(delay, forKey: "LastDelayedCaptureSeconds")
        
        Logger.shared.info("Starting delayed capture in \(delay) seconds")
        
        // Visual feedback (optional: could change icon)
        // For now, just a sound/log
        
        // Schedule capture
        // Phase 34: Pass delay to RegionSelector logic
        // We select the region IMMEDIATELY, then wait.
        startNewCapture(delay: delay)
    }
    
    @objc func startLastUsedDelayedCapture() {
        let savedDelay = UserDefaults.standard.double(forKey: "LastDelayedCaptureSeconds")
        let delay = savedDelay > 0 ? savedDelay : 3.0
        
        Logger.shared.info("Starting last used delayed capture: \(delay)s")
        startNewCapture(delay: delay)
    }
    
    // MARK: - Capture Actions
    
    @objc func startNewCaptureAction(_ sender: Any?) {
        startNewCapture(delay: 0)
    }
    
    @objc func startNewCapture(delay: TimeInterval = 0) {
        Logger.shared.info("Start New Capture Requested")
        // Ensure app is active for cursor and overlay control (fixes CTRL+N crosshair)
        NSApp.activate(ignoringOtherApps: true)
        guard PermissionManager.shared.hasScreenRecordingPermission() else {
            Logger.shared.info("Permission denied")
            PermissionManager.shared.requestScreenRecordingPermission()
            return
        }
        
        // Close any existing region selector
        regionSelector?.close()
        
        Logger.shared.info("Creating RegionSelector (Delay: \(delay))")
        // Create and show region selector
        regionSelector = RegionSelector(delay: delay) { [weak self] capturedImage, captureRect, displayID in
            Logger.shared.info("Region selection complete callback")
            self?.handleCaptureComplete(image: capturedImage, rect: captureRect, displayID: displayID)
        }
        regionSelector?.beginSelection()
    }
    
    @objc func startNewStickyNote() {
        StickyNoteManager.shared.createNote()
        Logger.shared.info("Created new Sticky Note via Menu/Shortcut")
    }
    
    @objc func showAllStickyNotes() {
        StickyNoteManager.shared.showAllNotes()
    }
    
    @objc func hideAllStickyNotes() {
        StickyNoteManager.shared.hideAllNotes()
    }
    
    @objc func unhideAllStickyNotes() {
        StickyNoteManager.shared.unhideAllNotes()
    }
    
    @objc func closeAllStickyNotes() {
        StickyNoteManager.shared.closeAllNotes()
        Logger.shared.info("Closed all Sticky Notes")
    }
    
    // MARK: - Sticky Note Formatting (Menu Bar)
    
    @objc func stickyNoteBold() {
        StickyNoteManager.shared.frontmostNote?.toggleBold()
    }
    
    @objc func stickyNoteUnderline() {
        StickyNoteManager.shared.frontmostNote?.toggleUnderline()
    }
    
    @objc func stickyNoteStrikethrough() {
        StickyNoteManager.shared.frontmostNote?.toggleStrikethrough()
    }
    
    @objc func stickyNoteSetFontSize(_ sender: NSMenuItem) {
        guard let note = StickyNoteManager.shared.frontmostNote else { return }
        note.setFontSize(sender)
    }
    
    @objc func stickyNoteSetListStyle(_ sender: NSMenuItem) {
        guard let note = StickyNoteManager.shared.frontmostNote else { return }
        note.setListStyle(sender)
    }
    
    @objc func stickyNoteSetColor(_ sender: NSMenuItem) {
        guard let note = StickyNoteManager.shared.frontmostNote else { return }
        note.selectColor(sender)
    }
    
    @objc func stickyNoteToggleLockToDisplay() {
        guard let note = StickyNoteManager.shared.frontmostNote else { return }
        note.toggleLockToDisplay()
    }
    
    // MARK: - Advanced Tool Actions
    
    @objc func toggleRuler() {
        guard !activeOverlays.isEmpty else { return }
        let targetState = !(currentActiveOverlay()?.isRulerActive ?? false)
        for overlay in activeOverlays.values {
            if overlay.isRulerActive != targetState {
                overlay.toggleRuler(nil)
            }
        }
    }
    
    @objc func toggleColorPicker() {
        guard !activeOverlays.isEmpty else { return }
        let current = currentActiveOverlay()
        let isCurrentlyOn = current?.isColorPickerMode ?? false
        
        // First, deactivate color picker on ALL overlays
        for overlay in activeOverlays.values {
            if overlay.isColorPickerMode {
                overlay.toggleColorPicker(nil)
            }
        }
        
        // If it was off, activate on the SINGLE current overlay only
        if !isCurrentlyOn, let target = current {
            target.toggleColorPicker(nil)
        }
    }
    
    @objc func toggleLoupe() {
        guard !activeOverlays.isEmpty else { return }
        let current = currentActiveOverlay()
        let isCurrentlyOn = current?.isLoupeActive ?? false
        
        // First, deactivate loupe on ALL overlays
        for overlay in activeOverlays.values {
            if overlay.isLoupeActive {
                overlay.toggleLoupe(nil)
            }
        }
        
        // If it was off, activate on the SINGLE current overlay only
        if !isCurrentlyOn, let target = current {
            target.toggleLoupe(nil)
        }
    }
    
    // Aliases for status bar menu items
    @objc func toggleLoupeGlobal() { toggleLoupe() }
    @objc func toggleColorPickerGlobal() { toggleColorPicker() }
    
    @objc func setMagnificationFromMenu(_ sender: NSMenuItem) {
        let level = CGFloat(sender.tag)
        for overlay in activeOverlays.values {
            overlay.magnificationLevel = level
            if !overlay.isLoupeActive {
                overlay.toggleLoupe(nil)
            }
        }
    }
    
    @objc func toggleGrayscale() {
        guard !activeOverlays.isEmpty else { return }
        let targetState = !(currentActiveOverlay()?.isGrayscale ?? false)
        for overlay in activeOverlays.values {
            if overlay.isGrayscale != targetState {
                overlay.toggleGrayscale()
            }
        }
    }
    
    @objc func toggleGhostMode() {
        guard !activeOverlays.isEmpty else { return }
        let targetState = !(currentActiveOverlay()?.isGhostMode ?? false)
        for overlay in activeOverlays.values {
            if overlay.isGhostMode != targetState {
                overlay.isGhostMode = targetState
            }
        }
    }
    
    // MARK: - Dynamic Tools Menu (Phase 31)
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === toolsMenu else { return }
        populateToolsMenu(menu)
    }
    
    private func populateToolsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let lm = LanguageManager.shared
        let overlay = currentActiveOverlay() // Highest priority / latest overlay
        let settings = ContextMenuSettings.shared
        
        // --- 1. Pen ---
        let penItem = NSMenuItem(title: lm.string("tool_pen"), action: #selector(selectPenTool), keyEquivalent: Constants.Shortcut.pen.key)
        penItem.keyEquivalentModifierMask = Constants.Shortcut.pen.modifiers
        penItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pen")
        if let overlay = overlay {
            penItem.submenu = ContextMenuBuilder.buildPenSubmenu(for: overlay)
            if overlay.currentTool == .pen { penItem.state = .on }
        }
        menu.addItem(penItem)
        
        // --- 2. Highlighter ---
        let highlighterItem = NSMenuItem(title: lm.string("tool_highlighter"), action: #selector(selectHighlighterTool), keyEquivalent: Constants.Shortcut.highlighter.key)
        highlighterItem.keyEquivalentModifierMask = Constants.Shortcut.highlighter.modifiers
        highlighterItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Highlighter")
        if let overlay = overlay {
            highlighterItem.submenu = ContextMenuBuilder.buildHighlighterSubmenu(for: overlay)
            if overlay.currentTool == .highlighter { highlighterItem.state = .on }
        }
        menu.addItem(highlighterItem)
        
        // --- 3. Eraser ---
        let eraserItem = NSMenuItem(title: lm.string("tool_eraser"), action: overlay != nil ? #selector(ContextMenuBuilder.calculateEraserAction(_:)) : #selector(selectEraserTool), keyEquivalent: Constants.Shortcut.eraser.key)
        eraserItem.keyEquivalentModifierMask = Constants.Shortcut.eraser.modifiers
        eraserItem.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: "Eraser")
        if let overlay = overlay {
            eraserItem.representedObject = overlay
            eraserItem.target = ContextMenuBuilder.self
            if overlay.currentTool == .eraser { eraserItem.state = .on }
        }
        menu.addItem(eraserItem)
        
        // --- 4. Text ---
        let textItem = NSMenuItem(title: lm.string("tool_text"), action: #selector(selectTextTool), keyEquivalent: Constants.Shortcut.text.key)
        textItem.keyEquivalentModifierMask = Constants.Shortcut.text.modifiers
        textItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text")
        if let overlay = overlay {
            textItem.submenu = ContextMenuBuilder.buildTextSubmenu(for: overlay)
            if overlay.currentTool == .text { textItem.state = .on }
        }
        menu.addItem(textItem)
        
        // --- 5. Select Text (OCR) ---
        let ocrItem = NSMenuItem(title: lm.string("menu.ocr"), action: #selector(selectTextCurrentOverlay), keyEquivalent: "t")
        ocrItem.keyEquivalentModifierMask = [.control, .shift]
        ocrItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "OCR")
        menu.addItem(ocrItem)
        
        // --- 6. Mask (Blur) ---
        let blurItem = NSMenuItem(title: lm.string("tool_blur"), action: #selector(selectBlurTool), keyEquivalent: Constants.Shortcut.blur.key)
        blurItem.keyEquivalentModifierMask = Constants.Shortcut.blur.modifiers
        blurItem.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Blur")
        if let overlay = overlay {
            blurItem.submenu = ContextMenuBuilder.buildBlurSubmenu(for: overlay)
            if overlay.currentTool == .blur { blurItem.state = .on }
        }
        menu.addItem(blurItem)
        
        // --- 7. Crop ---
        let cropItem = NSMenuItem(title: lm.string("tool_crop"), action: #selector(selectCropTool), keyEquivalent: Constants.Shortcut.crop.key)
        cropItem.keyEquivalentModifierMask = Constants.Shortcut.crop.modifiers
        cropItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Crop")
        menu.addItem(cropItem)
        
        // --- 8. Move Mode ---
        let moveItem = NSMenuItem(title: lm.string("tool_move"), action: #selector(selectMoveTool), keyEquivalent: Constants.Shortcut.move.key)
        moveItem.keyEquivalentModifierMask = Constants.Shortcut.move.modifiers
        moveItem.image = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Move")
        let toolsActive = (overlay?.isColorPickerMode == true) || (overlay?.isLoupeActive == true) || (overlay?.currentTool != nil)
        moveItem.state = (overlay != nil && !toolsActive) ? .on : .off
        menu.addItem(moveItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- 9. Lock Screenshot ---
        let isLocked = overlay?.isLocked ?? false
        let lockTitle = isLocked ? lm.string("menu.unlock.screenshot") : lm.string("menu.lock.screenshot")
        let lockScreenshotItem = NSMenuItem(title: lockTitle, action: #selector(toggleLockCurrentOverlay), keyEquivalent: "l")
        lockScreenshotItem.keyEquivalentModifierMask = .control
        lockScreenshotItem.state = isLocked ? .on : .off
        lockScreenshotItem.image = NSImage(systemSymbolName: isLocked ? "lock.open" : "lock", accessibilityDescription: "Lock")
        menu.addItem(lockScreenshotItem)
        
        // --- 10. Lock Display ---
        let lockItem = NSMenuItem(title: lm.string("menu.lock.display"), action: #selector(toggleLockDisplay), keyEquivalent: Constants.Shortcut.lockDisplay.key)
        lockItem.keyEquivalentModifierMask = Constants.Shortcut.lockDisplay.modifiers
        lockItem.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Lock Display")
        // Just checking state based on primary overlay
        lockItem.state = (overlay?.lockToDisplay == true) ? .on : .off
        menu.addItem(lockItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- 11. Color Picker ---
        if settings.showColorPicker || overlay == nil {
            let colorPickerItem = NSMenuItem(title: lm.string("menu.pick.color"), action: #selector(toggleColorPicker), keyEquivalent: Constants.Shortcut.colorPicker.key)
            colorPickerItem.keyEquivalentModifierMask = Constants.Shortcut.colorPicker.modifiers
            colorPickerItem.target = self
            colorPickerItem.state = (overlay?.isColorPickerMode == true) ? .on : .off
            colorPickerItem.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Color Picker")
            colorPickerItem.toolTip = LanguageManager.shared.string("tooltip_right_click_disable")
            menu.addItem(colorPickerItem)
        }
        
        // --- 12. Magnifier ---
        if settings.showMagnify || overlay == nil {
            let magnifyItem = NSMenuItem(title: lm.string("tool_magnify"), action: #selector(toggleLoupe), keyEquivalent: "m")
            magnifyItem.keyEquivalentModifierMask = .control
            magnifyItem.target = self
            magnifyItem.state = (overlay?.isLoupeActive == true) ? .on : .off
            magnifyItem.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Magnify")
            magnifyItem.toolTip = LanguageManager.shared.string("tooltip_right_click_disable")
            
            if let overlay = overlay {
                let magMenu = NSMenu()
                let levels: [CGFloat] = [3.0, 5.0, 10.0]
                for level in levels {
                    let item = NSMenuItem(title: "\(Int(level))x", action: #selector(OverlayWindow.setMagnification(_:)), keyEquivalent: "")
                    item.target = overlay
                    item.representedObject = level
                    item.state = (overlay.isLoupeActive && overlay.magnificationLevel == level) ? .on : .off
                    magMenu.addItem(item)
                }
                magnifyItem.submenu = magMenu
            }
            menu.addItem(magnifyItem)
        }
        
        // --- 13. Ruler ---
        let isRulerActive = overlay?.isRulerActive ?? false
        let rulerItem = NSMenuItem(title: lm.string("menu.show.rulers"), action: #selector(toggleRuler), keyEquivalent: Constants.Shortcut.ruler.key)
        rulerItem.keyEquivalentModifierMask = Constants.Shortcut.ruler.modifiers
        rulerItem.target = self
        rulerItem.state = isRulerActive ? .on : .off
        rulerItem.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Ruler")
        menu.addItem(rulerItem)
        
        // --- 14. Grayscale ---
        let isGrayscale = overlay?.isGrayscale ?? false
        let grayscaleItem = NSMenuItem(title: lm.string("menu.grayscale"), action: #selector(toggleGrayscale), keyEquivalent: Constants.Shortcut.grayscale.key)
        grayscaleItem.keyEquivalentModifierMask = Constants.Shortcut.grayscale.modifiers
        grayscaleItem.target = self
        grayscaleItem.state = isGrayscale ? .on : .off
        grayscaleItem.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Grayscale")
        menu.addItem(grayscaleItem)
        
        // --- 15. Ghost Mode ---
        let isGhost = overlay?.isGhostMode ?? false
        let ghostModeItem = NSMenuItem(title: lm.string("menu.ghost.mode"), action: #selector(toggleGhostMode), keyEquivalent: Constants.Shortcut.ghostMode.key)
        ghostModeItem.keyEquivalentModifierMask = Constants.Shortcut.ghostMode.modifiers
        ghostModeItem.target = self
        ghostModeItem.state = isGhost ? .on : .off
        ghostModeItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Ghost Mode")
        menu.addItem(ghostModeItem)
    }
    
    private func handleCaptureComplete(image: CGImage, rect: CGRect, displayID: CGDirectDisplayID) {
        Logger.shared.info("Handling capture complete - Image size: \(image.width)x\(image.height)")
        // Play shutter sound if enabled
        if UserDefaults.standard.object(forKey: "PlaySounds") as? Bool ?? true {
            AudioServicesPlaySystemSound(1108)
        }
        
        let overlayID = UUID()
        
        let metadata = CaptureMetadata(
            id: overlayID,
            captureRect: rect,
            displayID: displayID,
            timestamp: Date(),
            zoom: 1.0,
            annotations: []
        )
        
        Logger.shared.info("Creating OverlayWindow")
        let overlay = OverlayWindow(image: image, metadata: metadata)
        overlay.overlayDelegate = self
        overlay.makeKeyAndOrderFront(nil)
        
        activeOverlays[overlayID] = overlay
        Logger.shared.info("OverlayWindow presented")
        
        // Auto Copy to clipboard if enabled
        if UserDefaults.standard.bool(forKey: "AutoCopyEnabled") {
            ExportManager.shared.copyOverlayToClipboard(overlay)
            Logger.shared.info("Auto-copied screenshot to clipboard")
        }
        
        // Auto Save if enabled
        // Auto Save if enabled
        if UserDefaults.standard.bool(forKey: "AutoSaveEnabled") {
            // Use local helper for raw capture save (no annotations yet)
            saveAutoCopy(image: image, metadata: metadata)
            Logger.shared.info("Auto-saved screenshot to disk")
        }
        
        // Update status menu
        Logger.shared.info("Updating status menu")
        statusItem?.menu = createStatusMenu()
        Logger.shared.info("Status menu updated")
        
        Logger.shared.info("handleCaptureComplete finished")
    }
    
    // MARK: - Overlay Actions
    
    @objc func saveCurrentOverlay() {
        guard let overlay = currentActiveOverlay() else { return }
        ExportManager.shared.saveOverlay(overlay)
    }
    
    @objc func copyCurrentOverlay() {
        guard let overlay = currentActiveOverlay() else { return }
        ExportManager.shared.copyOverlayToClipboard(overlay)
        overlay.showCopiedFeedback()
    }
    
    @objc func saveAllScreenshots() {
        let overlays = Array(activeOverlays.values)
        guard !overlays.isEmpty else { return }
        saveNextOverlay(overlays: overlays, index: 0)
    }
    
    private func saveNextOverlay(overlays: [OverlayWindow], index: Int) {
        guard index < overlays.count else { return }
        
        let overlay = overlays[index]
        // Highlight the current overlay being saved
        overlay.makeKeyAndOrderFront(nil)
        
        ExportManager.shared.saveOverlay(overlay) { [weak self] saved in
            guard let self = self else { return }
            
            if saved {
                self.cacheAndCloseOverlay(overlay)
            }
            self.saveNextOverlay(overlays: overlays, index: index + 1)
        }
    }
    
    @objc func closeCurrentOverlay() {
        guard let overlay = currentActiveOverlay() else { return }
        cacheAndCloseOverlay(overlay)
    }
    
    @objc func toggleLockCurrentOverlay() {
        guard let primaryOverlay = currentActiveOverlay() else { return }
        let newState = !primaryOverlay.isLocked
        
        // Apply to ALL overlays
        for overlay in activeOverlays.values {
            if overlay.isLocked != newState {
                overlay.toggleLock()
            }
        }
        Logger.shared.info("Toggled lock on all overlays via hotkey")
    }
    
    @objc func selectTextCurrentOverlay() {
        // Show OCR text selection on the frontmost overlay
        guard let overlay = currentActiveOverlay() else { return }
        
        for otherOverlay in activeOverlays.values where otherOverlay != overlay {
            otherOverlay.endCropMode()
            otherOverlay.hideTextSelection()
        }
        
        overlay.showTextSelection()
        Logger.shared.info("OCR text selection triggered via hotkey")
    }

    @objc func selectPenTool() {
        // Apply to ALL overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .pen
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Pen selected for all overlays")
    }
    
    @objc func selectHighlighterTool() {
        // Apply to ALL overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .highlighter
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Highlighter selected for all overlays")
    }
    
    @objc func selectEraserTool() {
        // Apply to ALL overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .eraser
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Eraser selected for all overlays")
    }

    @objc func selectCropTool() {
        // Crop involves a specific overlay priority logic (last interacted or newest)
        guard let overlay = currentActiveOverlay() else { return }
        
        for otherOverlay in activeOverlays.values where otherOverlay != overlay {
            otherOverlay.endCropMode()
            otherOverlay.hideTextSelection()
        }
        
        overlay.startCropMode()
        NSCursor.crosshair.set()
        Logger.shared.info("Crop selected for highest priority overlay")
    }
    
    @objc func selectTextTool() {
        // Apply to ALL overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .text
        }
        NSCursor.iBeam.set()
        Logger.shared.info("Text tool selected for all overlays")
    }
    
    @objc func selectBlurTool() {
        // Apply to ALL overlays and Force 100% Intensity
        ToolManager.shared.blurIntensity = 30.0 // Max
        
        for overlay in activeOverlays.values {
            overlay.currentTool = .blur
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Blur tool selected (100% Intensity)")
    }
    
    @objc func toggleLockDisplay() {
        guard let primaryOverlay = currentActiveOverlay() else { return }
        let newState = !primaryOverlay.lockToDisplay
        
        // Apply to ALL overlays
        for overlay in activeOverlays.values {
            if overlay.lockToDisplay != newState {
                overlay.toggleLockToDisplay()
            }
        }
        Logger.shared.info("Toggled lock display on all overlays via hotkey")
    }

    @objc func selectMoveTool() {
        // Apply to ALL overlays
        for overlay in activeOverlays.values {
            overlay.endCropMode()
            overlay.currentTool = nil
        }
        NSCursor.arrow.set()
        Logger.shared.info("Move selected for all overlays")
    }
    
    // MARK: - Find SilkySnips
    
    @objc func findSilkySnips() {
        guard !activeOverlays.isEmpty else { return }
        
        let overlays = Array(activeOverlays.values)
        Logger.shared.info("Find SilkySnips - blinking \(overlays.count) screenshots")
        
        Task { @MainActor in
            // First blink ON
            overlays.forEach { $0.setSavingHighlight(true) }
            try? await Task.sleep(nanoseconds: 300 * 1_000_000) // 0.3s
            
            // First blink OFF
            overlays.forEach { $0.setSavingHighlight(false) }
            try? await Task.sleep(nanoseconds: 200 * 1_000_000) // 0.2s
            
            // Second blink ON
            overlays.forEach { $0.setSavingHighlight(true) }
            try? await Task.sleep(nanoseconds: 300 * 1_000_000) // 0.3s
            
            // Second blink OFF
            overlays.forEach { $0.setSavingHighlight(false) }
        }
    }
    
    // MARK: - Menu Bar Tool Actions
    
    @objc func menuSetPenColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        ToolManager.shared.penColor = CodableColor(hex: hex)
        // Apply pen tool to all overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .pen
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Pen color set to \(hex) for all overlays")
    }
    
    @objc func menuSetPenSize(_ sender: NSMenuItem) {
        guard let sizeIndex = sender.representedObject as? Int else { return }
        ToolManager.shared.setPenSize(sizeIndex)
        // Apply pen tool to all overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .pen
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Pen size set to index \(sizeIndex) for all overlays")
    }
    
    @objc func menuSetHighlighterColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        ToolManager.shared.highlighterColor = CodableColor(hex: hex)
        // Apply highlighter tool to all overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .highlighter
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Highlighter color set to \(hex) for all overlays")
    }
    
    @objc func menuSetEraserSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Int else { return }
        ToolManager.shared.eraserSize = CGFloat(size)
        // Apply eraser tool to all overlays
        for overlay in activeOverlays.values {
            overlay.currentTool = .eraser
        }
        NSCursor.crosshair.set()
        Logger.shared.info("Eraser size set to \(size) for all overlays")
    }
    
    // MARK: - Quit Confirmation
    
    @objc func confirmQuit() {
        // If no unsaved overlays, just quit
        if activeOverlays.isEmpty {
            NSApp.terminate(nil)
            return
        }
        
        // Temporarily lower overlay levels so alert is visible
        for overlay in activeOverlays.values {
            overlay.level = .normal
        }
        
        // Show confirmation dialog
        let alert = NSAlert()
        let count = activeOverlays.count
        let lm = LanguageManager.shared
        
        if count == 1 {
            alert.messageText = lm.string("alert_unsaved_title_screenshot_single")
        } else {
            alert.messageText = String(format: lm.string("alert_unsaved_title_screenshot_plural"), count)
        }
        alert.informativeText = lm.string("alert_quit_save_msg")
        alert.alertStyle = .warning
        
        // Add buttons in order: Save All (default), Don't Save, Cancel
        let saveButton = alert.addButton(withTitle: lm.string("menu.save.all"))
        saveButton.keyEquivalent = "\r"
        
        alert.addButton(withTitle: lm.string("btn_discard"))
        alert.addButton(withTitle: lm.string("btn_cancel"))
        
        // Force app activation to bring alert to front
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        
        // Restore levels if we didn't quit (Cancel/Keep Working)
        // If we invoke Quit/SaveAndQuit, the app terminates or windows close anyway.
        // But for safety if user cancels:
        for overlay in activeOverlays.values {
            // Restore to high level (screenSaver or as defined in OverlayWindow)
            // OverlayWindow sets its level to .screenSaver (or implied by its type).
            // Let's assume .screenSaver or .floating.
            // Better: reset to what OverlayWindow expects.
            // Since we can't easily read "original" intent here without coupling,
            // we'll set it to .screenSaver which is standard for this app.
            overlay.level = .screenSaver
        }
        
        switch response {
        case .alertFirstButtonReturn:
            // Save All - save one by one then quit
            saveAllAndQuit()
        case .alertSecondButtonReturn:
            // Don't Save - close all and quit
            closeAllAndQuit()
        case .alertThirdButtonReturn:
            // Cancel - do nothing, go back
            break
        default:
            break
        }
    }
    
    private func saveAllAndQuit() {
        let overlays = Array(activeOverlays.values)
        saveNextOverlayAndQuit(overlays: overlays, index: 0)
    }
    
    private func saveNextOverlayAndQuit(overlays: [OverlayWindow], index: Int) {
        guard index < overlays.count else {
            // All done, now quit
            NSApp.terminate(nil)
            return
        }
        
        let overlay = overlays[index]
        
        ExportManager.shared.saveOverlay(overlay) { [weak self] saved in
            if saved {
                self?.cacheAndCloseOverlay(overlay)
            }
            // Continue to next overlay
            self?.saveNextOverlayAndQuit(overlays: overlays, index: index + 1)
        }
    }
    
    private func closeAllAndQuit() {
        // Close all overlays without saving
        for overlay in activeOverlays.values {
            overlay.orderOut(nil)
        }
        activeOverlays.removeAll()
        
        // Quit the app
        NSApp.terminate(nil)
    }
    
    func cacheAndCloseOverlay(_ overlay: OverlayWindow) {
        Logger.shared.info("cacheAndCloseOverlay called")
        
        // Sync latest annotations to metadata
        overlay.updateMetadataAnnotations()
        
        // Save to cache before closing - use original captured image so annotations remain editable
        // (OverlayWindow will restore annotations from metadata upon re-opening)
        let imageToSave = overlay.capturedImage
        
        // Logic Entanglement: Pass Security Key
        CacheManager.shared.save(overlay.metadata, image: imageToSave, key: LicenseManager.shared.securityKey)
        

        
        // Remove from active overlays
        activeOverlays.removeValue(forKey: overlay.metadata.id)
        
        // Use orderOut instead of close to prevent app termination
        overlay.orderOut(nil)
        Logger.shared.info("Overlay ordered out, remaining overlays: \(activeOverlays.count)")
        
        // Update status menu
        statusItem?.menu = createStatusMenu()
    }
    
    @objc func restoreLastClosed() {
        // Logic Entanglement: Pass Security Key
        guard let entry = CacheManager.shared.restoreLastClosed(key: LicenseManager.shared.securityKey) else {
            NSSound.beep()
            return
        }
        
        let overlay = OverlayWindow(image: entry.image, metadata: entry.metadata)
        overlay.overlayDelegate = self
        
        // CRITICAL: Ensure proper window activation for full interactivity
        overlay.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        // Force window level just in case
        overlay.level = .floating
        
        // Activate app first
        NSApp.activate(ignoringOtherApps: true)
        
        // Order front and make key
        overlay.makeKeyAndOrderFront(nil)
        overlay.orderFrontRegardless() 
        overlay.makeMain()
        
        // CRITICAL FIX: Explicitly make the content view first responder
        // This ensures mouse events are received by the overlay
        if let contentView = overlay.contentView {
            overlay.makeFirstResponder(contentView)
            
            // Ensure content view fills window and has correct frame
            contentView.frame = overlay.contentView!.bounds
            contentView.needsDisplay = true
        }
        
        // LARGE SCREENSHOT FIX: Force window to accept mouse events
        overlay.ignoresMouseEvents = false
        overlay.acceptsMouseMovedEvents = true
        
        activeOverlays[entry.metadata.id] = overlay
        statusItem?.menu = createStatusMenu()
        
        Logger.shared.info("Restored screenshot: \(entry.metadata.id), size: \(entry.image.width)x\(entry.image.height), delegate set: \(overlay.overlayDelegate != nil)")
    }
    
    @objc func closeAllScreenshots() {
        let overlaysToClose = Array(activeOverlays.values)
        for overlay in overlaysToClose {
            cacheAndCloseOverlay(overlay)
        }
        Logger.shared.info("Closed all screenshots")
    }
    
    @objc func restoreLastStickyNote() {
        StickyNoteManager.shared.restoreMostRecent()
    }
    
    @objc func restoreAllCached() {
        // Logic Entanglement: Pass Security Key
        let metadatas = CacheManager.shared.getAllCachedMetadata(key: LicenseManager.shared.securityKey)
        guard !metadatas.isEmpty else {
            NSSound.beep()
            return
        }
        
        var restoredCount = 0
        
        for metadata in metadatas {
            // Skip if already active
            guard activeOverlays[metadata.id] == nil else { continue }
            
            // Load image on demand
            if let image = CacheManager.shared.getCachedImage(for: metadata.id) {
                let overlay = OverlayWindow(image: image, metadata: metadata)
                overlay.overlayDelegate = self
                
                // Force level
                overlay.level = .floating
                
                // Activate
                overlay.makeKeyAndOrderFront(nil)
                overlay.orderFrontRegardless()
                overlay.makeMain()
                
                // Ensure content view receives events
                if let contentView = overlay.contentView {
                    overlay.makeFirstResponder(contentView)
                }
                
                activeOverlays[metadata.id] = overlay
                restoredCount += 1
            }
        }
        
        if restoredCount > 0 {
            statusItem?.menu = createStatusMenu()
            Logger.shared.info("Restored \(restoredCount) cached screenshots")
        } else {
             NSSound.beep()
        }
    }
    
    // MARK: - Group & Visibility Actions
    
    @objc func hideAllScreenshots() {
        for overlay in activeOverlays.values {
            overlay.endCropMode()
            overlay.hideTextSelection()
            overlay.orderOut(nil)
        }
        Logger.shared.info("All screenshots hidden")
        statusItem?.menu = createStatusMenu()
    }
    
    @objc func unhideAllScreenshots() {
        for overlay in activeOverlays.values {
            overlay.makeKeyAndOrderFront(nil)
        }
        Logger.shared.info("All screenshots unhidden")
        statusItem?.menu = createStatusMenu()
    }
    
    @objc func groupAllScreenshots() {
        guard !activeOverlays.isEmpty, let screen = NSScreen.main else { return }
        areScreenshotsStacked = true
        
        // Target: Center of main screen
        let screenFrame = screen.visibleFrame
        let targetPoint = CGPoint(
            x: screenFrame.midX - 200, // Center-ish
            y: screenFrame.midY - 150
        )
        lastStackGroupOrigin = targetPoint
        
        // Animate all to target
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            for (index, overlay) in activeOverlays.values.enumerated() {
                overlay.originalFrame = overlay.frame // Save current pos
                
                // Slight stagger for visual effect
                let stagger = CGFloat(index * 20)
                let offset = CGPoint(x: stagger, y: -stagger)
                let newOrigin = CGPoint(x: targetPoint.x + offset.x, y: targetPoint.y + offset.y)
                
                overlay.stackOffset = offset // Remember relative pos
                
                overlay.animator().setFrameOrigin(newOrigin)
                // Ensure they are ordered front
                overlay.orderFront(nil)
            }
        }
        
        Logger.shared.info("Grouped all screenshots")
        statusItem?.menu = createStatusMenu() // Update menu to show Ungroup
    }
    
    @objc func ungroupAllScreenshots() {
        guard areScreenshotsStacked else { return }
        
        // Calculate delta if group moved
        var delta = CGPoint.zero
        
        // Find a window with valid stack info to calculate global group movement
        if let stackStart = lastStackGroupOrigin, 
           let reference = activeOverlays.values.first(where: { $0.stackOffset != nil }),
           let offset = reference.stackOffset {
             
             // Current pos = stackStart + offset + groupMoveDelta
             // groupMoveDelta = Current pos - stackStart - offset
             delta = CGPoint(
                x: reference.frame.origin.x - stackStart.x - offset.x,
                y: reference.frame.origin.y - stackStart.y - offset.y
             )
        }
        
        let overlays = Array(activeOverlays.values)
        areScreenshotsStacked = false
        lastStackGroupOrigin = nil
        
        NSAnimationContext.runAnimationGroup { context in
             context.duration = 0.3
             context.timingFunction = CAMediaTimingFunction(name: .easeOut)
             
             for overlay in overlays {
                 if let original = overlay.originalFrame {
                     // Apply delta to original frame
                     let restoredOrigin = CGPoint(
                        x: original.origin.x + delta.x,
                        y: original.origin.y + delta.y
                     )
                     overlay.animator().setFrameOrigin(restoredOrigin)
                 }
             }
        }
        
        Logger.shared.info("Ungrouped all screenshots (Delta: \(delta))")
        statusItem?.menu = createStatusMenu()
    }
    
    @objc func confirmClearCache() {
        let alert = NSAlert()
        let lm = LanguageManager.shared
        alert.messageText = lm.string("alert_clear_cache_title")
        alert.informativeText = lm.string("alert_clear_cache_msg")
        alert.alertStyle = .warning
        alert.addButton(withTitle: lm.string("menu.clear.cached"))
        alert.addButton(withTitle: lm.string("btn_cancel"))

        
        if alert.runModal() == .alertFirstButtonReturn {
            CacheManager.shared.clearAll()
            StickyNoteManager.shared.clearHistory()
            // Play trash sound
            NSSound(named: "Funk")?.play()
            statusItem?.menu = createStatusMenu()
        }
    }
    
    // MARK: - Cache Cleanup
    
    private func startCacheCleanupScheduler() {
        // Only use 50-file limit (pruneCache), no time-based expiry
        // Time-based cleanup disabled per user request
        // CacheManager.shared.cleanup() no longer runs
    }
    
    // MARK: - Onboarding Flow
    
    private func shouldShowOnboarding() -> Bool {
        // Show onboarding if first launch OR if permissions not yet granted
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let allPermissionsGranted = PermissionManager.shared.allRequiredPermissionsGranted()
        
        return !hasCompletedOnboarding || !allPermissionsGranted
    }
    
    private func showWelcomeWindow() {
        Logger.shared.info("Initializing WelcomeWindowController")
        welcomeWindow = WelcomeWindowController()
        welcomeWindow?.delegate = self
        welcomeWindow?.show()
    }
    
    private func showOnboardingWindow() {
        welcomeWindow?.dismiss()
        welcomeWindow = nil
        
        onboardingWindow = OnboardingWindowController()
        onboardingWindow?.delegate = self
        onboardingWindow?.show()
    }
    
    func completeSetup() {
        Logger.shared.info("completeSetup() started")
        // Dismiss activation
        activationWindow?.close()
        activationWindow = nil

        // Dismiss any onboarding windows
        welcomeWindow?.dismiss()
        welcomeWindow = nil
        onboardingWindow?.dismiss()
        onboardingWindow = nil
        
        // Mark onboarding as complete
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isOnboardingComplete = true
        
        // Now setup the app normally
        setupStatusBarItem()
        setupHotkeys()
        startCacheCleanupScheduler()
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                self.showStartupNotification()
            }
        }
    }
    
    private func showStartupNotification() {
        let content = UNMutableNotificationContent()
        content.title = LanguageManager.shared.string("title_app_running")
        content.body = "Effectively running in the background. Access settings or Quit via the Menu Bar icon ↗️"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "SilkySnipStartup", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    

    
}

// MARK: - WelcomeWindowDelegate

extension AppDelegate: WelcomeWindowDelegate {
    func welcomeWindowDidClickGetStarted() {
        showOnboardingWindow()
    }
}

// MARK: - OnboardingWindowDelegate

extension AppDelegate: OnboardingWindowDelegate {
    func onboardingDidComplete() {
        completeSetup()
    }
}

// MARK: - OverlayWindowDelegate


    
    // MARK: - OverlayWindowDelegate
    
extension AppDelegate: OverlayWindowDelegate {
    func overlayWindowDidRequestClose(_ overlay: OverlayWindow) {
        // No modifications → close silently (auto-saved to cache)
        guard overlay.hasAnnotations else {
            cacheAndCloseOverlay(overlay)
            return
        }
        
        // Has modifications → prompt only if autosave is disabled
        let autoSaveEnabled = UserDefaults.standard.bool(forKey: "AutoSaveEnabled")
        
        if autoSaveEnabled {
            // Autosave is on but annotations exist → prompt to save annotated version
            let alert = NSAlert()
            let lm = LanguageManager.shared
            alert.messageText = lm.string("alert_unsaved_annotations_title")
            alert.informativeText = lm.string("alert_unsaved_annotations_msg")
            alert.addButton(withTitle: lm.string("btn_save"))
            alert.addButton(withTitle: lm.string("btn_close_without_saving"))
            alert.addButton(withTitle: lm.string("btn_cancel"))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                ExportManager.shared.saveOverlay(overlay) { [weak self] saved in
                    if saved { self?.cacheAndCloseOverlay(overlay) }
                }
            } else if response == .alertSecondButtonReturn {
                cacheAndCloseOverlay(overlay)
            }
        } else {
            // Auto-Save OFF + has annotations → prompt to save
            let alert = NSAlert()
            let lm = LanguageManager.shared
            alert.messageText = lm.string("alert_unsaved_screenshot_title")
            alert.informativeText = lm.string("alert_unsaved_screenshot_msg")
            alert.addButton(withTitle: lm.string("btn_save"))
            alert.addButton(withTitle: lm.string("btn_close_without_saving"))
            alert.addButton(withTitle: lm.string("btn_cancel"))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                ExportManager.shared.saveOverlay(overlay) { [weak self] saved in
                    if saved { self?.cacheAndCloseOverlay(overlay) }
                }
            } else if response == .alertSecondButtonReturn {
                cacheAndCloseOverlay(overlay)
            }
        }
    }
    
    func overlayWindowDidRequestNewCapture(_ overlay: OverlayWindow) {
        startNewCapture()
    }
    
    func overlayWindowDidStartDrag(_ overlay: OverlayWindow) {
        // If stacked, prepare all OTHER windows for dragging
        if areScreenshotsStacked {
            for otherOverlay in activeOverlays.values where otherOverlay != overlay {
                otherOverlay.prepareForGroupDrag()
            }
        }
    }
    
    func overlayWindowDidMove(_ overlay: OverlayWindow, delta: CGPoint) {
        // If stacked, move all OTHER windows by the same delta
        if areScreenshotsStacked {
            for otherOverlay in activeOverlays.values where otherOverlay != overlay {
                if let initial = otherOverlay.initialWindowOrigin {
                    let newOrigin = CGPoint(
                        x: initial.x + delta.x,
                        y: initial.y + delta.y
                    )
                    otherOverlay.setFrameOrigin(newOrigin)
                }
            }
        }
    }
    func updateMenuStateForHiddenWindows() {
        statusItem?.menu = createStatusMenu()
    }
}
    


// MARK: - Actions Extension

extension AppDelegate {
    // MARK: - Global Overlay Actions
    
    @objc func turnOffGhostMode() {
        OverlayWindow.setGlobalGhostMode(false)
        statusItem?.menu = createStatusMenu()
        Logger.shared.info("Ghost mode disabled globally")
        
        // Phase 27 Fix: Visual confirmation
        // NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    
    @objc func turnOnGhostMode() {
        OverlayWindow.setGlobalGhostMode(true)
        statusItem?.menu = createStatusMenu()
        Logger.shared.info("Ghost mode enabled globally")
        
        // Visual confirmation
        // NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    

    
    // MARK: - Auto Save Helper
    
    private func saveAutoCopy(image: CGImage, metadata: CaptureMetadata) {
        // Get save location
        let path = UserDefaults.standard.string(forKey: "AutoSavePath") ?? 
                   FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? ""
        
        let folderURL = URL(fileURLWithPath: path)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        // Format filename: Screenshot YYYY-MM-DD at HH.mm.ss.png
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dateString = formatter.string(from: metadata.timestamp)
        let formatExtension = UserDefaults.standard.string(forKey: "AutoSaveFormat") ?? "png"
        let filename = "SilkySnip \(dateString).\(formatExtension)"
        
        let fileURL = folderURL.appendingPathComponent(filename)
        
        let utType: CFString
        switch formatExtension.lowercased() {
        case "jpg", "jpeg":
            utType = UTType.jpeg.identifier as CFString
        default:
            utType = UTType.png.identifier as CFString
        }
        
        // Save using mapped UTType
        guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, utType, 1, nil) else {
            Logger.shared.error("Failed to create image destination for auto-save")
            return
        }
        
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            Logger.shared.info("Auto-saved copy to: \(fileURL.path)")
        } else {
            Logger.shared.error("Failed to finalize auto-save image")
        }
    }
}

// MARK: - Menu Validation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(restoreLastStickyNote) {
            return !StickyNoteManager.shared.getHistory().isEmpty
        }
        if menuItem.action == #selector(restoreLastClosed) || menuItem.action == #selector(restoreAllCached) {
            let cachedScreenshots = CacheManager.shared.getAllCachedMetadata(key: LicenseManager.shared.securityKey)
            return !cachedScreenshots.isEmpty
        }
        
        // Disable overlay-specific actions if no overlays are active
        let overlayRequiredActions: [Selector] = [
            #selector(saveCurrentOverlay), #selector(saveAllScreenshots),
            #selector(closeCurrentOverlay), #selector(closeAllScreenshots),
            #selector(findSilkySnips), #selector(hideAllScreenshots), #selector(unhideAllScreenshots),
            #selector(groupAllScreenshots), #selector(ungroupAllScreenshots),
            #selector(selectPenTool), #selector(selectHighlighterTool), #selector(selectEraserTool),
            #selector(selectTextTool), #selector(selectTextCurrentOverlay), #selector(selectBlurTool),
            #selector(selectCropTool), #selector(toggleLockCurrentOverlay), #selector(toggleLockDisplay),
            #selector(toggleColorPicker), #selector(toggleLoupe), #selector(toggleRuler),
            #selector(toggleGrayscale), #selector(toggleGhostMode)
        ]
        
        if let action = menuItem.action, overlayRequiredActions.contains(action) {
            let hasOverlays = !activeOverlays.isEmpty
            if hasOverlays {
                let overlay = currentActiveOverlay()
                switch action {
                case #selector(toggleGrayscale):
                    menuItem.state = (overlay?.isGrayscale == true) ? .on : .off
                case #selector(toggleGhostMode):
                    menuItem.state = (overlay?.isGhostMode == true) ? .on : .off
                case #selector(toggleRuler):
                    menuItem.state = (overlay?.isRulerActive == true) ? .on : .off
                case #selector(toggleColorPicker):
                    menuItem.state = (overlay?.isColorPickerMode == true) ? .on : .off
                case #selector(toggleLoupe):
                    menuItem.state = (overlay?.isLoupeActive == true) ? .on : .off
                case #selector(toggleLockCurrentOverlay):
                    menuItem.state = (overlay?.isLocked == true) ? .on : .off
                case #selector(toggleLockDisplay):
                    menuItem.state = (overlay?.lockToDisplay == true) ? .on : .off
                default:
                    break
                }
            } else {
                menuItem.state = .off
            }
            return hasOverlays
        }
        
        // Disable note-specific actions if no sticky notes are active
        let noteActions: [Selector] = [
            #selector(stickyNoteBold), #selector(stickyNoteUnderline), #selector(stickyNoteStrikethrough),
            #selector(stickyNoteSetFontSize(_:)), #selector(stickyNoteSetListStyle(_:)), #selector(stickyNoteSetColor(_:)),
            #selector(stickyNoteToggleLockToDisplay)
        ]
        
        if let action = menuItem.action, noteActions.contains(action) {
            if let frontNote = StickyNoteManager.shared.frontmostNote {
                if action == #selector(stickyNoteToggleLockToDisplay) {
                    menuItem.state = frontNote.isLockedToDisplay ? .on : .off
                }
                return true
            }
            menuItem.state = .off
            return false
        }
        
        let noteGlobalActions: [Selector] = [
            #selector(showAllStickyNotes), #selector(closeAllStickyNotes)
        ]
        
        if let action = menuItem.action, noteGlobalActions.contains(action) {
            return StickyNoteManager.shared.hasActiveNotes
        }
        
        if menuItem.action == #selector(hideAllStickyNotes) {
            return StickyNoteManager.shared.hasVisibleNotes
        }
        
        if menuItem.action == #selector(unhideAllStickyNotes) {
            return StickyNoteManager.shared.hasHiddenNotes
        }
        
        return true
    }
}
