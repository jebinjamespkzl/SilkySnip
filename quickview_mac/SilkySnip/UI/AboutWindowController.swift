import Cocoa

class AboutWindowController: NSWindowController {
    
    // MARK: - Initialization
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Standard "About" window behavior
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.level = .floating + 5
        
        self.init(window: window)
        setupContent()
    }
    
    // MARK: - Setup
    
    private func setupContent() {
        guard let window = window else { return }
        let lm = LanguageManager.shared
        
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        
        // Background effect
        let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .sidebar
        visualEffectView.state = .active
        contentView.addSubview(visualEffectView)
        
        // Main Stack
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)
        
        // Top Spacer to push logo down from traffic lights
        container.addArrangedSubview(createSpacer(height: Theme.Layout.large))
        
        // 1. Icon
        let iconView = NSImageView()
        if let appIcon = NSImage(named: "AppIcon") {
            iconView.image = appIcon
        } else if let appIcon = NSApp.applicationIconImage {
            iconView.image = appIcon
        } else {
             iconView.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: lm.string("accessibility_app_icon"))
             iconView.contentTintColor = NSColor.controlAccentColor
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: Theme.Layout.largeIconSize).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: Theme.Layout.largeIconSize).isActive = true
        
        // Debug Crash Trigger
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleIconClick(_:)))
        iconView.addGestureRecognizer(clickGesture)
        iconView.isEditable = false // Ensure it accepts clicks
        
        container.addArrangedSubview(iconView)
        
        // Spacer
        container.addArrangedSubview(createSpacer(height: Theme.Layout.small))
        
        // 2. App Name
        let nameLabel = NSTextField(labelWithString: lm.string("app_name"))
        nameLabel.font = Theme.Fonts.heroTitle
        nameLabel.textColor = NSColor.labelColor
        container.addArrangedSubview(nameLabel)
        
        // 3. Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "\(lm.string("label_version")) \(version) (\(lm.string("label_build")) \(build))")
        versionLabel.font = Theme.Fonts.secondaryLabel
        versionLabel.textColor = NSColor.secondaryLabelColor
        container.addArrangedSubview(versionLabel)
        
        // Spacer
        container.addArrangedSubview(createSpacer(height: Theme.Layout.medium))
        
        // 4. Copyright
        let copyrightLabel = NSTextField(labelWithString: String(format: lm.string("label_copyright_format"), lm.string("company_name")))
        copyrightLabel.font = Theme.Fonts.caption
        copyrightLabel.textColor = NSColor.tertiaryLabelColor
        container.addArrangedSubview(copyrightLabel)
        
        let rightsLabel = NSTextField(labelWithString: lm.string("label_rights_reserved"))
        rightsLabel.font = Theme.Fonts.caption
        rightsLabel.textColor = NSColor.tertiaryLabelColor
        container.addArrangedSubview(rightsLabel)
        
        // Rewards button removed per Phase 17
        
        
        let licensesBtn = NSButton(title: lm.string("btn_licenses"), target: self, action: #selector(showLicenses))
        licensesBtn.bezelStyle = .rounded
        licensesBtn.setAccessibilityLabel(lm.string("btn_licenses"))
        container.addArrangedSubview(licensesBtn)
        
        let updateBtn = NSButton(title: lm.string("btn_check_updates"), target: self, action: #selector(checkForUpdates))
        updateBtn.bezelStyle = .rounded
        updateBtn.setAccessibilityLabel(lm.string("btn_check_updates"))
        container.addArrangedSubview(updateBtn)
        
        // Translation Warning Section - only show for non-English languages
        let currentLanguage = Locale.preferredLanguages.first ?? "en"
        if !currentLanguage.hasPrefix("en") {
            // Spacer before translation warning
            container.addArrangedSubview(createSpacer(height: Theme.Layout.medium))
            
            let warningLabel = NSTextField(wrappingLabelWithString: lm.string("translation_warning_message"))
            warningLabel.font = Theme.Fonts.caption
            warningLabel.textColor = NSColor.secondaryLabelColor
            warningLabel.alignment = .center
            warningLabel.preferredMaxLayoutWidth = 260
            container.addArrangedSubview(warningLabel)
            
            container.addArrangedSubview(createSpacer(height: Theme.Layout.small))
            
            let reportBtn = NSButton(title: lm.string("report_translation_error"), target: self, action: #selector(reportTranslationError))
            reportBtn.bezelStyle = .rounded
            reportBtn.setAccessibilityLabel(lm.string("report_translation_error"))
            container.addArrangedSubview(reportBtn)
        }
        
        // Layout - Anchor to top to prevent clipping at bottom when content is tall
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            container.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        ])
        
        window.contentView = contentView
        window.center()
    }
    
    private func createSpacer(height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }
    
    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Rewards functionality removed per Phase 17
    
    
    @objc func showLicenses() {
        let lm = LanguageManager.shared
        let alert = NSAlert()
        alert.messageText = lm.string("btn_licenses")
        alert.informativeText = lm.string("license_text_header") +
                                lm.string("license_swift") + "\n" +
                                lm.string("license_sparkle") + "\n" +
                                lm.string("license_logmanager") +
                                lm.string("license_text_footer")
        alert.addButton(withTitle: lm.string("ok"))
        alert.runModal()
    }
    
    @objc func handleIconClick(_ sender: NSClickGestureRecognizer) {
        let optionsPressed = NSEvent.modifierFlags.contains(.option)
        if optionsPressed {
            Logger.shared.warning("Debug Crash Triggered by User")
            fatalError("Debug Test Crash triggered from About Window")
        }
    }
    
    @objc func checkForUpdates() {
        (NSApp.delegate as? AppDelegate)?.checkForUpdates()
    }
    
    @objc func reportTranslationError() {
        let lm = LanguageManager.shared
        let subject = lm.string("email_subject_translation").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = lm.string("email_body_translation").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:techsupport@silkyapple.com?subject=\(subject)&body=\(body)") {
            NSWorkspace.shared.open(url)
        }
    }
}
