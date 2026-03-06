//
//  PreferencesWindowController.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Cocoa
import ServiceManagement

class PreferencesWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private let tabViewController = NSTabViewController()
    
    // MARK: - Initialization
    
    init() {
        // Create the window programmatically
        // Reduced height to remove empty space
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Ensure it floats significantly above screenshot overlays
        window.level = .floating + 5
        window.title = LanguageManager.shared.string("title_preferences")
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Spawn on the active monitor where the mouse is located
        let mouseLoc = NSEvent.mouseLocation
        if let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main {
            let screenFrame = currentScreen.visibleFrame
            let newOrigin = CGPoint(
                x: screenFrame.midX - window.frame.width / 2,
                y: screenFrame.midY - window.frame.height / 2
            )
            window.setFrameOrigin(newOrigin)
        } else {
            window.center()
        }
        
        super.init(window: window)
        
        setupTabs()
        window.contentViewController = tabViewController
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTabs() {
        tabViewController.tabStyle = .toolbar
        let lm = LanguageManager.shared
        
        let generalVC = GeneralPreferencesViewController()
        generalVC.title = lm.string("section_general")
        
        let appearanceVC = AppearancePreferencesViewController()
        appearanceVC.title = lm.string("section_appearance")
        
        let toolsVC = ToolsPreferencesViewController()
        toolsVC.title = LanguageManager.shared.string("tab_tools") // Needs key in JSON if missing, but focusing on tabs for now
        
        let permissionsVC = PermissionsPreferencesViewController()
        permissionsVC.title = lm.string("tab_permissions")
        
        tabViewController.addChild(generalVC)
        tabViewController.tabViewItem(for: generalVC)?.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "General")
        
        tabViewController.addChild(appearanceVC)
        tabViewController.tabViewItem(for: appearanceVC)?.image = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: "Appearance")
        
        tabViewController.addChild(toolsVC)
        tabViewController.tabViewItem(for: toolsVC)?.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: lm.string("accessibility_tools"))
        
        tabViewController.addChild(permissionsVC)
        tabViewController.tabViewItem(for: permissionsVC)?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: lm.string("tab_permissions"))
        
        // General Tab Accessibility
        tabViewController.tabViewItem(for: generalVC)?.image?.accessibilityDescription = lm.string("accessibility_general")
        
        // Appearance Tab Accessibility
        tabViewController.tabViewItem(for: appearanceVC)?.image?.accessibilityDescription = lm.string("accessibility_appearance")

        updateTitle()
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitle), name: Notification.Name("LanguageChanged"), object: nil)
    }

    @objc private func updateTitle() {
        self.window?.title = LanguageManager.shared.string("title_preferences")
        
        // Update Tab Titles
        let lm = LanguageManager.shared
        if tabViewController.tabViewItems.count > 0 {
             tabViewController.tabViewItems[0].label = lm.string("section_general")
        }
        if tabViewController.tabViewItems.count > 1 {
             tabViewController.tabViewItems[1].label = lm.string("section_appearance")
        }
        if tabViewController.tabViewItems.count > 2 {
             tabViewController.tabViewItems[2].label = lm.string("label_tools_tab")
        }
        if tabViewController.tabViewItems.count > 3 {
             tabViewController.tabViewItems[3].label = lm.string("tab_permissions")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - General Tab

class GeneralPreferencesViewController: NSViewController {
    
    // UI Elements
    private var languageLabel: NSTextField!
    private var launchLabel: NSTextField!
    private var launchCheckbox: NSButton!
    private var autoSaveLabel: NSTextField!
    private var autoSaveCheckbox: NSButton!
    private var freezeScreenLabel: NSTextField!
    private var freezeScreenCheckbox: NSButton!
    private var locationLabel: NSTextField!
    private var changeButton: NSButton!
    private var formatLabel: NSTextField!
    private var notificationsLabel: NSTextField!
    private var soundsCheckbox: NSButton!
    private var languagePopup: NSPopUpButton!
    private var formatPopup: NSPopUpButton!
    private var autoCopyCheckbox: NSButton!
    private var showDockCheckbox: NSButton!
    private var behaviorLabel: NSTextField!
    
    override func loadView() {
        // Increased height for additional options
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 280))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateLocalizedStrings), name: Notification.Name("LanguageChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private var pathControl: NSPathControl?
    
    private func setupUI() {
        pathControl = createPathControl()
        
        languageLabel = createLabel("Language:")
        launchLabel = createLabel("Launch Behavior:")
        autoSaveLabel = createLabel("Auto-Save:")
        freezeScreenLabel = createLabel("Capture:")
        locationLabel = createLabel("Auto-Save Location:")
        formatLabel = createLabel("Auto-Save Format:")
        notificationsLabel = createLabel("Notifications:")
        
        changeButton = NSButton(title: LanguageManager.shared.string("btn_change"), target: self, action: #selector(changeLocation))
        launchCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(launchAtLoginToggled(_:)))
        launchCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        autoSaveCheckbox = createCheckbox("Auto-save SilkySnips", key: "AutoSaveEnabled")
        
        // Change default behavior to false to reflect new UX paradigm
        if UserDefaults.standard.object(forKey: "FreezeScreenOnInstant") == nil {
            UserDefaults.standard.set(false, forKey: "FreezeScreenOnInstant")
        }
        freezeScreenCheckbox = createCheckbox(LanguageManager.shared.string("checkbox_freeze_screen"), key: "FreezeScreenOnInstant")
        
        soundsCheckbox = createCheckbox("Play Sounds", key: "PlaySounds")
        
        // Auto Copy and Show in Dock
        autoCopyCheckbox = createCheckbox(LanguageManager.shared.string("checkbox_auto_copy"), key: "AutoCopyEnabled")
        showDockCheckbox = NSButton(checkboxWithTitle: LanguageManager.shared.string("checkbox_show_dock"), target: self, action: #selector(showInDockToggled(_:)))
        showDockCheckbox.state = UserDefaults.standard.bool(forKey: "ShowInDock") ? .on : .off
        behaviorLabel = createLabel("Behavior:")
        
        // Behavior stack — vertical layout of checkboxes
        let behaviorStack = NSStackView(views: [autoCopyCheckbox, showDockCheckbox])
        behaviorStack.orientation = .vertical
        behaviorStack.alignment = .leading
        behaviorStack.spacing = 4
        
        formatPopup = createFormatDropdown()
        languagePopup = createLanguageDropdown()
        
        let grid = NSGridView(views: [
            [languageLabel!, languagePopup!],
            [launchLabel!, launchCheckbox!],
            [autoSaveLabel!, autoSaveCheckbox!],
            [locationLabel!, NSStackView(views: [pathControl!, changeButton!])],
            [formatLabel!, formatPopup!],
            [freezeScreenLabel!, freezeScreenCheckbox!],
            [notificationsLabel!, soundsCheckbox!],
            [behaviorLabel!, behaviorStack]
        ])
        
        // Compact layout
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        
        view.addSubview(grid)
        
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        // Configure StackView
        if let stack = grid.cell(atColumnIndex: 1, rowIndex: 3).contentView as? NSStackView {
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.distribution = .fillProportionally
        }
        
        // Tooltips — hover descriptions for each setting
        updateLocalizedStrings()
        
        updateLocalizedStrings()
    }
    
    @objc private func updateLocalizedStrings() {
        let lm = LanguageManager.shared
        languageLabel.stringValue = lm.string("label_language") + ":"
        launchLabel.stringValue = lm.string("label_launch_behavior") + ":"
        autoSaveLabel.stringValue = lm.string("label_autosave") + ":"
        locationLabel.stringValue = lm.string("label_autosave_location") + ":"
        formatLabel.stringValue = lm.string("label_autosave_format") + ":"
        notificationsLabel.stringValue = lm.string("label_notifications") + ":"
        freezeScreenLabel.stringValue = lm.string("label_capture") + ":"
        
        launchCheckbox.title = lm.string("checkbox_launch_login")
        autoSaveCheckbox.title = lm.string("checkbox_autosave")
        soundsCheckbox.title = lm.string("checkbox_play_sounds")
        changeButton.title = lm.string("btn_change_ellipsis")
        
        // Update format popup titles if needed, though they are usually static or need rebuild
        let selectedIdx = formatPopup.indexOfSelectedItem
        formatPopup.removeAllItems()
        formatPopup.addItems(withTitles: [
            lm.string("format_png_default"),
            lm.string("format_jpg_compact")
        ])
        
        // Ensure index doesn't go out of bounds since we removed 2 items
        if selectedIdx >= 0 && selectedIdx < formatPopup.numberOfItems {
            formatPopup.selectItem(at: selectedIdx)
        } else {
            formatPopup.selectItem(at: 0) // Fallback to PNG
        }
        
        freezeScreenCheckbox.title = lm.string("checkbox_freeze_screen")
        
        // Update Tooltips dynamically
        languageLabel.toolTip = lm.string("settings.language.tooltip")
        languagePopup.toolTip = lm.string("settings.languagePopup.tooltip")
        launchLabel.toolTip = lm.string("settings.launch.tooltip")
        launchCheckbox.toolTip = lm.string("settings.launchCheckbox.tooltip")
        autoSaveLabel.toolTip = lm.string("settings.autoSave.tooltip")
        autoSaveCheckbox.toolTip = lm.string("settings.autoSaveCheckbox.tooltip")
        locationLabel.toolTip = lm.string("settings.location.tooltip")
        pathControl?.toolTip = lm.string("settings.pathControl.tooltip")
        changeButton.toolTip = lm.string("settings.changeButton.tooltip")
        formatLabel.toolTip = lm.string("settings.format.tooltip")
        formatPopup.toolTip = lm.string("settings.formatPopup.tooltip")
        freezeScreenLabel.toolTip = lm.string("settings.freezeScreen.tooltip")
        freezeScreenCheckbox.toolTip = lm.string("settings.freezeScreenCheckbox.tooltip")
        notificationsLabel.toolTip = lm.string("settings.notifications.tooltip")
        soundsCheckbox.toolTip = lm.string("settings.soundsCheckbox.tooltip")
        
        // Behavior section
        behaviorLabel.stringValue = lm.string("label_behavior") + ":"
        autoCopyCheckbox.title = lm.string("checkbox_auto_copy")
        showDockCheckbox.title = lm.string("checkbox_show_dock")
        autoCopyCheckbox.toolTip = lm.string("settings.autoSaveCheckbox.tooltip")
        showDockCheckbox.toolTip = lm.string("settings.notifications.tooltip")
    }
    
    private func createLanguageDropdown() -> NSPopUpButton {
        let popup = NSPopUpButton(title: "", target: self, action: #selector(languageChanged(_:)))
        
        let manager = LanguageManager.shared
        for language in manager.availableLanguages {
            popup.addItem(withTitle: language.name)
            popup.lastItem?.representedObject = language.code
        }
        
        // Select current
        let currentCode = manager.currentLanguageCode
        if let index = manager.availableLanguages.firstIndex(where: { $0.code == currentCode }) {
            popup.selectItem(at: index)
        }
        
        return popup
    }
    
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let code = sender.selectedItem?.representedObject as? String else { return }
        
        LanguageManager.shared.setLanguage(code)
        
        // Show restart alert
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.string("settings.language.restart.title") // Fallback will just show key if missing, or we can use English default for now
        let titleStr = alert.messageText == "settings.language.restart.title" ? "Restart Required" : alert.messageText
        alert.messageText = titleStr
        
        let msgStr = LanguageManager.shared.string("settings.language.restart.message")
        alert.informativeText = msgStr == "settings.language.restart.message" ? "To fully apply the language change to system menus, please restart SilkySnip." : msgStr
        
        let restartStr = LanguageManager.shared.string("btn_restart_now")
        alert.addButton(withTitle: restartStr == "btn_restart_now" ? "Restart Now" : restartStr)
        
        let laterStr = LanguageManager.shared.string("btn_later")
        alert.addButton(withTitle: laterStr == "btn_later" ? "Later" : laterStr)
        
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Restart App
            let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
            let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-n", path]
            task.launch()
            NSApp.terminate(nil)
        }
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }
    
    private func createCheckbox(_ title: String, key: String) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxToggled(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(key)
        checkbox.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        return checkbox
    }
    
    private func createPathControl() -> NSPathControl {
        let pathControl = NSPathControl()
        pathControl.url = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "AutoSavePath") ?? NSHomeDirectory().appending("/Documents"))
        pathControl.pathStyle = .standard
        // Constrain width to force truncation (middle ellipsis by default for standard path control)
        pathControl.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return pathControl
    }
    
    private func createFormatDropdown() -> NSPopUpButton {
        let popup = NSPopUpButton(title: "", target: self, action: #selector(formatChanged(_:)))
        popup.identifier = NSUserInterfaceItemIdentifier("AutoSaveFormat")
        // Items will be populated in updateLocalizedStrings, but adding defaults here to avoid empty
        popup.addItems(withTitles: [
            LanguageManager.shared.string("format_png_default"),
            LanguageManager.shared.string("format_jpg_compact")
        ])
        
        // Load state
        let current = UserDefaults.standard.string(forKey: "AutoSaveFormat") ?? "png"
        switch current {
        case "jpg": popup.selectItem(at: 1)
        default: popup.selectItem(at: 0)
        }
        
        return popup
    }
    
    @objc private func changeLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = LanguageManager.shared.string("title_select_location")
        
        guard let window = self.view.window else {
            // Fallback if window is somehow nil
            panel.level = .floating + 6
            panel.begin { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.pathControl?.url = url
                    UserDefaults.standard.set(url.path, forKey: "AutoSavePath")
                }
            }
            return
        }
        
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url {
                // Update PathControl
                self?.pathControl?.url = url
                // Save Preference
                UserDefaults.standard.set(url.path, forKey: "AutoSavePath")
            }
        }
    }
    
    @objc private func checkboxToggled(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
    }
    
    @objc private func showInDockToggled(_ sender: NSButton) {
        let newValue = sender.state == .on
        UserDefaults.standard.set(newValue, forKey: "ShowInDock")
        
        if newValue {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
                Logger.shared.info("Launch at Login: Registered")
            } else {
                try SMAppService.mainApp.unregister()
                Logger.shared.info("Launch at Login: Unregistered")
            }
        } catch {
            Logger.shared.error("Launch at Login failed: \(error.localizedDescription)")
            // Revert the checkbox if registration failed
            sender.state = (sender.state == .on) ? .off : .on
        }
    }
    
    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let format: String
        switch sender.indexOfSelectedItem {
        case 1: format = "jpg"
        default: format = "png"
        }
        UserDefaults.standard.set(format, forKey: "AutoSaveFormat")
    }
}

// MARK: - Appearance Tab

// MARK: - Appearance Tab

class AppearancePreferencesViewController: NSViewController {
    
    private var opacityLabel: NSTextField!
    private var neonLabel: NSTextField!
    private var themeLabel: NSTextField!
    private var neonCheckbox: NSButton!
    private var themePopup: NSPopUpButton!
    private var opacitySlider: NSSlider!
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 250))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(updateLocalizedStrings), name: Notification.Name("LanguageChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        opacityLabel = createLabel("Default Opacity:")
        neonLabel = createLabel("Neon Border:")
        themeLabel = createLabel("Theme:")
        
        neonCheckbox = createCheckbox("Enable Neon Glow", key: "NeonBorderEnabled")
        themePopup = createThemeDropdown()
        opacitySlider = createSlider(key: "DefaultOpacity")
        
        let grid = NSGridView(views: [
            [opacityLabel!, opacitySlider!],
            [neonLabel!, neonCheckbox!],
            [themeLabel!, themePopup!]
        ])
        
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        // Tooltips
        updateLocalizedStrings()
        
        updateLocalizedStrings()
    }
    
    @objc private func updateLocalizedStrings() {
        let lm = LanguageManager.shared
        opacityLabel.stringValue = lm.string("label_default_opacity") + ":"
        neonLabel.stringValue = lm.string("label_neon_border") + ":"
        themeLabel.stringValue = lm.string("label_theme") + ":"
        
        neonCheckbox.title = lm.string("checkbox_neon_glow")
        
        // Refresh items if needed, or just keep them (themes might be English only or localized names)
        // ideally reload items:
        let selectedIdx = themePopup.indexOfSelectedItem
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: [
            lm.string("theme_cyberpunk"),
            lm.string("theme_matrix"),
            lm.string("theme_solar")
        ])
        if selectedIdx >= 0 && selectedIdx < themePopup.numberOfItems {
             themePopup.selectItem(at: selectedIdx)
        }
        
        // Update Tooltips dynamically
        opacityLabel.toolTip = lm.string("settings.opacity.tooltip")
        neonLabel.toolTip = lm.string("settings.neon.tooltip")
        neonCheckbox.toolTip = lm.string("settings.neonCheckbox.tooltip")
        themeLabel.toolTip = lm.string("settings.theme.tooltip")
        themePopup.toolTip = lm.string("settings.themePopup.tooltip")
        opacitySlider.toolTip = lm.string("settings.slider.tooltip")
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }
    
    private func createCheckbox(_ title: String, key: String) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxToggled(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(key)
        checkbox.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        return checkbox
    }
    
    private func createSlider(key: String) -> NSSlider {
        let savedValue = UserDefaults.standard.object(forKey: key) as? Double ?? 1.0
        let slider = NSSlider(value: savedValue, minValue: 0.2, maxValue: 1.0, target: self, action: #selector(sliderChanged(_:)))
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        return slider
    }
    
    private func createThemeDropdown() -> NSPopUpButton {
        let popup = NSPopUpButton(title: "", target: self, action: #selector(themeChanged(_:)))
        popup.identifier = NSUserInterfaceItemIdentifier("SelectedTheme")
        // Items will be populated in updateLocalizedStrings, but adding defaults here to avoid empty
        popup.addItems(withTitles: [
            LanguageManager.shared.string("theme_cyberpunk"),
            LanguageManager.shared.string("theme_matrix"),
            LanguageManager.shared.string("theme_solar")
        ])
        // Load saved state
        let savedIndex = UserDefaults.standard.integer(forKey: "SelectedTheme")
        if savedIndex >= 0 && savedIndex < popup.numberOfItems {
            popup.selectItem(at: savedIndex)
        }
        return popup
    }
    
    @objc private func themeChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "SelectedTheme")
    }
    
    @objc private func checkboxToggled(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.doubleValue, forKey: key)
    }
}

// MARK: - Tools Tab

class ToolsPreferencesViewController: NSViewController {
    
    private var clickLabel: NSTextField!
    private var magicLabel: NSTextField!
    private var advancedToolsLabel: NSTextField!
    private var clickPopup: NSPopUpButton!
    private var magicCheckbox: NSButton!
    
    // Advanced tool checkboxes
    private var magnifyCheckbox: NSButton!
    private var grayscaleCheckbox: NSButton!
    private var rulersCheckbox: NSButton!
    private var colorPickerCheckbox: NSButton!
    private var ghostModeCheckbox: NSButton!
    
    private let settings = ContextMenuSettings.shared
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 350))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(updateLocalizedStrings), name: Notification.Name("LanguageChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        clickLabel = createLabel("Click Behavior:")
        magicLabel = createLabel("Magic Restore:")
        advancedToolsLabel = createLabel("Advanced Tools:")
        
        clickPopup = createClickDropdown()
        magicCheckbox = createCheckbox("Enable Smart App Pinning", key: "SmartRestoreEnabled")
        
        let lm = LanguageManager.shared
        // Create advanced tool checkboxes
        magnifyCheckbox = createToolCheckbox(lm.string("tool_magnify"), isOn: settings.showMagnify, action: #selector(magnifyToggled(_:)))
        grayscaleCheckbox = createToolCheckbox(lm.string("menu.grayscale"), isOn: settings.showFilters, action: #selector(filtersToggled(_:)))
        rulersCheckbox = createToolCheckbox("Rulers", isOn: settings.showRulers, action: #selector(rulersToggled(_:)))
        colorPickerCheckbox = createToolCheckbox("Color Picker", isOn: settings.showColorPicker, action: #selector(colorPickerToggled(_:)))
        ghostModeCheckbox = createToolCheckbox("Ghost Mode", isOn: settings.showGhostMode, action: #selector(ghostModeToggled(_:)))
        
        // Advanced tools stack - vertical layout of checkboxes
        let advancedStack = NSStackView(views: [
            magnifyCheckbox,
            grayscaleCheckbox,
            rulersCheckbox,
            colorPickerCheckbox,
            ghostModeCheckbox
        ])
        advancedStack.orientation = .vertical
        advancedStack.alignment = .leading
        advancedStack.spacing = 4
        
        let grid = NSGridView(views: [
            [clickLabel!, clickPopup!],
            [magicLabel!, magicCheckbox!],
            [advancedToolsLabel!, advancedStack]
        ])
        
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        view.addSubview(grid)
        
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 20)
        ])
        
        // Tooltips
        updateLocalizedStrings()
        
        updateLocalizedStrings()
    }
    
    @objc private func updateLocalizedStrings() {
        let lm = LanguageManager.shared
        clickLabel.stringValue = lm.string("label_click_behavior") + ":"
        magicLabel.stringValue = lm.string("label_magic_restore") + ":"
        advancedToolsLabel.stringValue = lm.string("label_show_in_menu")
        
        magicCheckbox.title = lm.string("checkbox_smart_pinning")
        
        // Tool names
        magnifyCheckbox.title = lm.string("tool_magnify")
        
        // Update Tooltips dynamically
        clickLabel.toolTip = lm.string("settings.click.tooltip")
        clickPopup.toolTip = lm.string("settings.clickPopup.tooltip")
        magicLabel.toolTip = lm.string("settings.magic.tooltip")
        magicCheckbox.toolTip = lm.string("settings.magicCheckbox.tooltip")
        advancedToolsLabel.toolTip = lm.string("settings.advancedTools.tooltip")
        magnifyCheckbox.toolTip = lm.string("settings.magnifyCheckbox.tooltip")
        grayscaleCheckbox.toolTip = lm.string("settings.grayscaleCheckbox.tooltip")
        rulersCheckbox.toolTip = lm.string("settings.rulersCheckbox.tooltip")
        colorPickerCheckbox.toolTip = lm.string("settings.colorPickerCheckbox.tooltip")
        ghostModeCheckbox.toolTip = lm.string("settings.ghostModeCheckbox.tooltip")
        grayscaleCheckbox.title = LanguageManager.shared.string("menu.grayscale")
        rulersCheckbox.title = lm.string("menu.show.rulers")
        colorPickerCheckbox.title = lm.string("menu.pick.color")
        ghostModeCheckbox.title = lm.string("menu.ghost.mode")
        
        // Update items (preserve selection ideally)
        let selectedIdx = clickPopup.indexOfSelectedItem
        clickPopup.removeAllItems()
        clickPopup.addItems(withTitles: [
            lm.string("click_single"),
            lm.string("click_double")
        ])
        if selectedIdx >= 0 && selectedIdx < clickPopup.numberOfItems {
             clickPopup.selectItem(at: selectedIdx)
        }
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }
    
    private func createCheckbox(_ title: String, key: String) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxToggled(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(key)
        checkbox.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        return checkbox
    }
    
    private func createToolCheckbox(_ title: String, isOn: Bool, action: Selector) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: action)
        checkbox.state = isOn ? .on : .off
        return checkbox
    }
    
    @objc private func checkboxToggled(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
    }
    
    private func createClickDropdown() -> NSPopUpButton {
        let popup = NSPopUpButton(title: "", target: self, action: #selector(dropdownChanged(_:)))
        popup.identifier = NSUserInterfaceItemIdentifier("CloseClickBehavior")
        
        // Initial items (will be localized in updateLocalizedStrings)
        popup.addItems(withTitles: [
            LanguageManager.shared.string("click_single"),
            LanguageManager.shared.string("click_double")
        ])
        
        // Load state
        let current = UserDefaults.standard.string(forKey: "CloseClickBehavior") ?? "single"
        if current == "double" {
            popup.selectItem(at: 1)
        } else {
            popup.selectItem(at: 0)
        }
        
        return popup
    }
    
    @objc private func dropdownChanged(_ sender: NSPopUpButton) {
        // Handle dropdown
        if sender.identifier?.rawValue == "CloseClickBehavior" {
            let value = sender.indexOfSelectedItem == 1 ? "double" : "single"
            UserDefaults.standard.set(value, forKey: "CloseClickBehavior")
            // DebugLogger.shared.log("Click behavior set to: \(value)")
        }
    }
    
    // MARK: - Advanced Tool Toggles
    
    @objc private func magnifyToggled(_ sender: NSButton) {
        settings.showMagnify = sender.state == .on
    }
    
    @objc private func filtersToggled(_ sender: NSButton) {
        settings.showFilters = sender.state == .on
    }
    
    @objc private func rulersToggled(_ sender: NSButton) {
        settings.showRulers = sender.state == .on
    }
    
    @objc private func colorPickerToggled(_ sender: NSButton) {
        settings.showColorPicker = sender.state == .on
    }
    
    @objc private func ghostModeToggled(_ sender: NSButton) {
        settings.showGhostMode = sender.state == .on
    }
}

// MARK: - Permissions Tab

class PermissionsPreferencesViewController: NSViewController {
    
    private var screenRecordingLabel: NSTextField!
    private var screenRecordingStatusLabel: NSTextField!
    private var screenRecordingButton: NSButton!
    
    private var accessibilityLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var accessibilityButton: NSButton!
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 180))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Listen for standard app activation to refresh statuses in case user changed them in Settings
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPermissionsStatuses), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateLocalizedStrings), name: Notification.Name("LanguageChanged"), object: nil)
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        refreshPermissionsStatuses() // Always refresh when this tab becomes visible
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        // Screen Recording UI
        screenRecordingLabel = createLabel("perm_screen_recording")
        screenRecordingStatusLabel = createStatusLabel()
        screenRecordingButton = NSButton(title: LanguageManager.shared.string("btn_open_settings"), target: self, action: #selector(openScreenRecordingSettings))
        
        // Accessibility UI
        accessibilityLabel = createLabel("perm_accessibility")
        accessibilityStatusLabel = createStatusLabel()
        accessibilityButton = NSButton(title: LanguageManager.shared.string("btn_open_settings"), target: self, action: #selector(openAccessibilitySettings))
        
        let grid = NSGridView(views: [
            [screenRecordingLabel!, screenRecordingStatusLabel!, screenRecordingButton!],
            [accessibilityLabel!, accessibilityStatusLabel!, accessibilityButton!]
        ])
        
        grid.columnSpacing = 16
        grid.rowSpacing = 16
        grid.xPlacement = .leading
        grid.yPlacement = .center
        
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 30)
        ])
        
        updateLocalizedStrings()
        refreshPermissionsStatuses()
    }
    
    @objc private func updateLocalizedStrings() {
        let lm = LanguageManager.shared
        screenRecordingLabel.stringValue = lm.string("perm_screen_recording") + ":"
        accessibilityLabel.stringValue = lm.string("perm_accessibility") + ":"
        screenRecordingButton.title = lm.string("btn_open_settings")
        accessibilityButton.title = lm.string("btn_open_settings")
        refreshPermissionsStatuses() // To localize the 'Granted' / 'Not Granted' text
    }
    
    @objc private func refreshPermissionsStatuses() {
        self.view.window?.level = .floating + 5
        
        let lm = LanguageManager.shared
        
        // 1. Screen Recording
        let screenGranted = PermissionManager.shared.hasScreenRecordingPermission()
        if screenGranted {
            screenRecordingStatusLabel.stringValue = lm.string("perm_granted")
            screenRecordingStatusLabel.textColor = .systemGreen
        } else {
            screenRecordingStatusLabel.stringValue = lm.string("perm_denied")
            screenRecordingStatusLabel.textColor = .systemRed
        }
        
        // 2. Accessibility
        let accessibilityGranted = PermissionManager.shared.hasAccessibilityPermission()
        if accessibilityGranted {
            accessibilityStatusLabel.stringValue = lm.string("perm_granted")
            accessibilityStatusLabel.textColor = .systemGreen
        } else {
            accessibilityStatusLabel.stringValue = lm.string("perm_denied")
            accessibilityStatusLabel.textColor = .systemRed
        }
    }
    
    private func createLabel(_ localizationKey: String) -> NSTextField {
        let labelText = String(format: "%@:", LanguageManager.shared.string(localizationKey))
        let label = NSTextField(labelWithString: labelText)
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .right
        return label
    }
    
    private func createStatusLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        return label
    }
    
    @objc private func openScreenRecordingSettings() {
        self.view.window?.level = .normal
        PermissionManager.shared.openScreenRecordingSettings()
    }
    
    @objc private func openAccessibilitySettings() {
        self.view.window?.level = .normal
        PermissionManager.shared.openAccessibilitySettings()
    }
}
