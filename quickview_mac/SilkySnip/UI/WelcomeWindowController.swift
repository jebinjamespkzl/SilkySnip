//
//  WelcomeWindowController.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa

protocol WelcomeWindowDelegate: AnyObject {
    func welcomeWindowDidClickGetStarted()
}

class WelcomeWindowController: NSWindowController {
    
    // MARK: - Properties
    
    weak var delegate: WelcomeWindowDelegate?
    
    // MARK: - Initialization
    
    convenience init() {
        // Reduced width (480 -> 420) and increased height (520 -> 560) for slimmer look
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        // Ensure it floats above screenshot overlays
        window.level = .floating + 2
        
        self.init(window: window)
        
        setupWindow()
        setupContent()
        Logger.shared.info("WelcomeWindowController initialized")
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window as? NSPanel else { return }
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        // Make it a floating panel that stays on top
        window.level = .floating
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
    }
    
    private func setupContent() {
        guard let window = window else { return }
        
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        
        // Create a visual effect view for the background
        let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .sidebar
        visualEffectView.state = .active
        contentView.addSubview(visualEffectView)
        
        // Container for all content
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 20
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)
        
        // App Icon
        let iconView = createAppIconView()
        container.addArrangedSubview(iconView)
        
        // Welcome Title
        let lm = LanguageManager.shared
        let formatStr = LanguageManager.shared.string("welcome_to_app")
        let titleLabel = NSTextField(labelWithString: String(format: formatStr, lm.string("app_name")))
        titleLabel.font = Theme.Fonts.welcomeTitle // Slightly smaller font
        titleLabel.textColor = NSColor.labelColor
        titleLabel.alignment = .center
        container.addArrangedSubview(titleLabel)
        
        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: lm.string("welcome_subtitle"))
        subtitleLabel.font = Theme.Fonts.secondaryLabel
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.alignment = .center
        container.addArrangedSubview(subtitleLabel)
        
        // Spacer
        let spacer1 = NSView()
        spacer1.translatesAutoresizingMaskIntoConstraints = false
        spacer1.heightAnchor.constraint(equalToConstant: 10).isActive = true
        container.addArrangedSubview(spacer1)
        
        // Feature list
        let featuresStack = createFeaturesStack()
        container.addArrangedSubview(featuresStack)
        
        // Spacer
        let spacer2 = NSView()
        spacer2.translatesAutoresizingMaskIntoConstraints = false
        spacer2.heightAnchor.constraint(equalToConstant: 20).isActive = true
        container.addArrangedSubview(spacer2)
        
        // Get Started Button
        let getStartedButton = createGetStartedButton()
        container.addArrangedSubview(getStartedButton)
        
        // Spacer
        let spacer3 = NSView()
        spacer3.translatesAutoresizingMaskIntoConstraints = false
        spacer3.heightAnchor.constraint(equalToConstant: 10).isActive = true
        container.addArrangedSubview(spacer3)
        
        // Legal Footer
        let legalLabel = NSTextField(labelWithString: String(format: lm.string("legal_footer_format"), lm.string("company_name")))
        legalLabel.font = Theme.Fonts.legal
        legalLabel.textColor = NSColor.tertiaryLabelColor
        legalLabel.alignment = .center
        legalLabel.lineBreakMode = .byWordWrapping
        legalLabel.preferredMaxLayoutWidth = 340 // Ensure wrapping within narrower width
        legalLabel.maximumNumberOfLines = 5 // Allow more lines for wrapping
        
        container.addArrangedSubview(legalLabel)
        
        // Layout container - Pin to TOP to prevent icon clipping
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50),
            container.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 40),
            container.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40),
            // Ensure bottom margin is at least something
            container.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
        
        window.contentView = contentView
    }
    
    private func createAppIconView() -> NSView {
        let containerSize: CGFloat = 100
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerSize, height: containerSize))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = true
        
        let imageView = NSImageView(frame: container.bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        // Try to load app icon
        if let appIcon = NSImage(named: "AppIcon") {
            imageView.image = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            imageView.image = appIcon
        } else {
            // Fallback to SF Symbol
            let lm = LanguageManager.shared
            imageView.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: lm.string("accessibility_app_icon"))
            imageView.contentTintColor = NSColor.controlAccentColor
        }
        
        container.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: containerSize),
            container.heightAnchor.constraint(equalToConstant: containerSize)
        ])
        
        return container
    }
    
    private func createFeaturesStack() -> NSStackView {
        let lm = LanguageManager.shared
        let features = [
            ("camera.viewfinder", lm.string("feature_capture_region"), lm.string("feature_capture_region_desc")),
            ("pin.fill", lm.string("feature_persistent_overlays"), lm.string("feature_persistent_overlays_desc")),
            ("pencil.tip.crop.circle", lm.string("feature_quick_annotations"), lm.string("feature_quick_annotations_desc")),
            ("arrow.counterclockwise", lm.string("feature_instant_restore"), lm.string("feature_instant_restore_desc"))
        ]
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        
        for (icon, title, description) in features {
            let featureView = createFeatureRow(icon: icon, title: title, description: description)
            stack.addArrangedSubview(featureView)
        }
        
        return stack
    }
    
    private func createFeatureRow(icon: String, title: String, description: String) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .top
        container.spacing = 12
        
        // Icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        iconView.contentTintColor = NSColor.controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        container.addArrangedSubview(iconView)
        
        // Text stack
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Theme.Fonts.featureTitle
        titleLabel.textColor = NSColor.labelColor
        textStack.addArrangedSubview(titleLabel)
        
        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = Theme.Fonts.caption
        descLabel.textColor = NSColor.secondaryLabelColor
        textStack.addArrangedSubview(descLabel)
        
        container.addArrangedSubview(textStack)
        
        return container
    }
    
    private func createGetStartedButton() -> NSButton {
        let button = NSButton(title: LanguageManager.shared.string("btn_get_started"), target: self, action: #selector(getStartedClicked))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r" // Enter key
        
        // Style as prominent button
        button.contentTintColor = NSColor.white
        if #available(macOS 11.0, *) {
            button.hasDestructiveAction = false
        }
        
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        
        return button
    }
    
    // MARK: - Actions
    
    @objc private func getStartedClicked() {
        delegate?.welcomeWindowDidClickGetStarted()
    }
    
    // MARK: - Public Methods
    
    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func dismiss() {
        window?.close()
    }
}
