//
//  OnboardingWindowController.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa

protocol OnboardingWindowDelegate: AnyObject {
    func onboardingDidComplete()
}

class OnboardingWindowController: NSWindowController {
    
    // MARK: - Properties
    
    weak var delegate: OnboardingWindowDelegate?
    
    private var screenRecordingCard: PermissionCardView?
    private var accessibilityCard: PermissionCardView?
    private var continueButton: NSButton?
    private var permissionMonitorTimer: Timer?
    
    // MARK: - Initialization
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.init(window: window)
        
        setupWindow()
        setupContent()
        startPermissionMonitoring()
    }
    
    deinit {
        stopPermissionMonitoring()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.center()
        
        // Use normal level so system permission dialogs can appear in front
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    private func setupContent() {
        guard let window = window else { return }
        
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        
        // Visual effect background
        let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .sidebar
        visualEffectView.state = .active
        contentView.addSubview(visualEffectView)
        
        // Main container
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 24
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)
        
        // Header
        let headerStack = createHeader()
        container.addArrangedSubview(headerStack)
        
        // Permission cards container
        let cardsStack = NSStackView()
        cardsStack.orientation = .vertical
        cardsStack.alignment = .leading
        cardsStack.spacing = 16
        
        // Screen Recording Permission Card
        let lm = LanguageManager.shared
        screenRecordingCard = PermissionCardView(
            icon: "rectangle.dashed.badge.record",
            title: lm.string("onboarding_screen_recording"),
            description: lm.string("onboarding_screen_recording_desc"),
            isRequired: true
        )
        screenRecordingCard?.onGrantClicked = { [weak self] in
            self?.openScreenRecordingSettings()
        }
        if let card = screenRecordingCard {
            cardsStack.addArrangedSubview(card)
        }
        
        // Accessibility Permission Card
        accessibilityCard = PermissionCardView(
            icon: "keyboard",
            title: lm.string("onboarding_accessibility"),
            description: lm.string("onboarding_accessibility_desc"),
            isRequired: true
        )
        accessibilityCard?.onGrantClicked = { [weak self] in
            self?.requestAccessibilityPermission()
        }
        if let card = accessibilityCard {
            cardsStack.addArrangedSubview(card)
        }
        
        container.addArrangedSubview(cardsStack)
        
        // Info text
        let infoLabel = NSTextField(wrappingLabelWithString: lm.string("onboarding_permission_info"))
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = NSColor.tertiaryLabelColor
        infoLabel.alignment = .center
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
        container.addArrangedSubview(infoLabel)
        
        // Spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
        container.addArrangedSubview(spacer)
        
        // Continue button
        continueButton = NSButton(title: lm.string("btn_continue"), target: self, action: #selector(continueClicked))
        continueButton?.bezelStyle = .rounded
        continueButton?.controlSize = .large
        continueButton?.keyEquivalent = "\r"
        continueButton?.isEnabled = false
        
        continueButton?.translatesAutoresizingMaskIntoConstraints = false
        continueButton?.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        
        if let button = continueButton {
            container.addArrangedSubview(button)
        }
        
        // Layout
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 40),
            container.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40)
        ])
        
        window.contentView = contentView
        
        // Initial permission check
        updatePermissionStatus()
    }
    
    private func createHeader() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        
        // Icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Permissions")
        iconView.contentTintColor = NSColor.controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(iconView)
        
        // Title
        let titleLabel = NSTextField(labelWithString: LanguageManager.shared.string("onboarding_permissions_required"))
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.alignment = .center
        stack.addArrangedSubview(titleLabel)
        
        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: LanguageManager.shared.string("onboarding_permissions_subtitle"))
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.alignment = .center
        stack.addArrangedSubview(subtitleLabel)
        
        return stack
    }
    
    // MARK: - Permission Actions
    
    private func openScreenRecordingSettings() {
        // Use PermissionManager which triggers the system prompt and opens System Settings
        PermissionManager.shared.requestScreenRecordingPermission()
    }
    
    private func requestAccessibilityPermission() {
        // Use PermissionManager which triggers the system prompt and opens System Settings
        PermissionManager.shared.requestAccessibilityPermission()
    }
    
    // MARK: - Permission Monitoring
    
    private func startPermissionMonitoring() {
        // Check permissions every 1 second (not too frequently to avoid issues)
        permissionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePermissionStatus()
        }
    }
    
    private func stopPermissionMonitoring() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
    }
    
    private func updatePermissionStatus() {
        let screenRecordingGranted = PermissionManager.shared.hasScreenRecordingPermission()
        let accessibilityGranted = PermissionManager.shared.hasAccessibilityPermission()
        
        screenRecordingCard?.setGranted(screenRecordingGranted)
        accessibilityCard?.setGranted(accessibilityGranted)
        
        // Enable continue button when Screen Recording is granted
        // Accessibility is optional - its detection is unreliable for ad-hoc builds
        // but hotkeys typically work via Carbon API regardless
        let canProceed = screenRecordingGranted
        continueButton?.isEnabled = canProceed
        
        if canProceed {
            continueButton?.title = LanguageManager.shared.string("btn_continue")
        } else {
            continueButton?.title = LanguageManager.shared.string("btn_waiting_permissions")
        }
    }
    
    // MARK: - Actions
    
    @objc private func continueClicked() {
        stopPermissionMonitoring()
        delegate?.onboardingDidComplete()
    }
    
    // MARK: - Public Methods
    
    func show() {
        updatePermissionStatus()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func dismiss() {
        stopPermissionMonitoring()
        window?.close()
    }
}

// MARK: - Permission Card View

class PermissionCardView: NSView {
    
    var onGrantClicked: (() -> Void)?
    
    private var statusIcon: NSImageView?
    private var grantButton: NSButton?
    private var isGranted = false
    
    init(icon: String, title: String, description: String, isRequired: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 80))
        
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 420).isActive = true
        heightAnchor.constraint(equalToConstant: 80).isActive = true
        
        setupContent(icon: icon, title: title, description: description, isRequired: isRequired)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupContent(icon: String, title: String, description: String, isRequired: Bool) {
        // Main horizontal stack
        let mainStack = NSStackView()
        mainStack.orientation = .horizontal
        mainStack.alignment = .centerY
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Permission icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        iconView.contentTintColor = NSColor.controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true
        mainStack.addArrangedSubview(iconView)
        
        // Text stack
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        
        // Title with required badge
        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.spacing = 8
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleStack.addArrangedSubview(titleLabel)
        
        if isRequired {
            let requiredLabel = NSTextField(labelWithString: LanguageManager.shared.string("label_required"))
            requiredLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            requiredLabel.textColor = NSColor.systemOrange
            titleStack.addArrangedSubview(requiredLabel)
        }
        
        textStack.addArrangedSubview(titleStack)
        
        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = NSColor.secondaryLabelColor
        textStack.addArrangedSubview(descLabel)
        
        mainStack.addArrangedSubview(textStack)
        
        // Spacer
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mainStack.addArrangedSubview(spacer)
        
        // Status icon
        statusIcon = NSImageView()
        statusIcon?.translatesAutoresizingMaskIntoConstraints = false
        statusIcon?.widthAnchor.constraint(equalToConstant: 20).isActive = true
        statusIcon?.heightAnchor.constraint(equalToConstant: 20).isActive = true
        statusIcon?.isHidden = true
        if let statusIcon = statusIcon {
            mainStack.addArrangedSubview(statusIcon)
        }
        
        // Grant button
        grantButton = NSButton(title: LanguageManager.shared.string("btn_grant"), target: self, action: #selector(grantClicked))
        grantButton?.bezelStyle = .rounded
        grantButton?.controlSize = .small
        if let button = grantButton {
            mainStack.addArrangedSubview(button)
        }
    }
    
    func setGranted(_ granted: Bool) {
        isGranted = granted
        
        if granted {
            grantButton?.isHidden = true
            statusIcon?.isHidden = false
            statusIcon?.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Granted")
            statusIcon?.contentTintColor = NSColor.systemGreen
            
            layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.5).cgColor
            layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.05).cgColor
        } else {
            grantButton?.isHidden = false
            statusIcon?.isHidden = true
            
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
    
    @objc private func grantClicked() {
        onGrantClicked?()
    }
}
