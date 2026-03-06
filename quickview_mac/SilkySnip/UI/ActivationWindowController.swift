import Cocoa
import SwiftUI

class ActivationWindowController: NSWindowController {
    
    private let licenseManager = LicenseManager.shared
    
    // UI Elements
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: LanguageManager.shared.string("title_activate_silkysnip"))
        label.font = NSFont.boldSystemFont(ofSize: 18)
        label.alignment = .center
        return label
    }()
    
    private let statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: LanguageManager.shared.string("label_enter_license_key"))
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()
    
    private let priceLabel: NSTextField = {
        let label = NSTextField(labelWithString: LanguageManager.shared.string("label_loading_price"))
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.systemBlue
        label.alignment = .center
        return label
    }()
    
    private let inputField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "XXXX-XXXX-XXXX-XXXX"
        return field
    }()
    
    private let activateButton: NSButton = {
        let btn = NSButton(title: LanguageManager.shared.string("btn_activate_license"), target: nil, action: nil)
        btn.bezelStyle = .rounded
        return btn
    }()
    
    private let trialButton: NSButton = {
        let btn = NSButton(title: LanguageManager.shared.string("btn_start_trial"), target: nil, action: nil)
        btn.bezelStyle = .recessed
        return btn
    }()
    
    private let spinner: NSProgressIndicator = {
        let spin = NSProgressIndicator()
        spin.style = .spinning
        spin.isDisplayedWhenStopped = false
        return spin
    }()
    
    private let transparencyLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        return label
    }()
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.center()
        window.title = LanguageManager.shared.string("title_activation")
        super.init(window: window)
        
        setupUI()
        setupActions()
        fetchPricing()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        let stack = NSStackView(views: [titleLabel, statusLabel, priceLabel, inputField, activateButton, trialButton, spinner, transparencyLabel])
        stack.orientation = .vertical
        stack.spacing = 15
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 40, bottom: 30, right: 40)
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 320),
            inputField.widthAnchor.constraint(equalToConstant: 250),
            activateButton.widthAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    private func setupActions() {
        activateButton.target = self
        activateButton.action = #selector(onActivate)
        
        trialButton.target = self
        trialButton.action = #selector(onTrial)
    }
    
    private func fetchPricing() {
        licenseManager.fetchPricing { [weak self] item in
            DispatchQueue.main.async {
                if let item = item {
                    self?.priceLabel.stringValue = String(format: LanguageManager.shared.string("license_lifetime_format"), item.label, String(format: "%.2f", item.lifetime))
                    self?.transparencyLabel.stringValue = item.transparency
                } else {
                    self?.priceLabel.stringValue = LanguageManager.shared.string("label_standard_pricing_fallback")
                }
            }
        }
    }
    
    @objc private func onActivate() {
        let key = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            statusLabel.stringValue = LanguageManager.shared.string("error_please_enter_key")
            statusLabel.textColor = .systemRed
            return
        }
        
        performActivation(key: key)
    }
    
    @objc private func onTrial() {
        performActivation(key: "TRIAL")
    }
    
    private func performActivation(key: String, force: Bool = false) {
        setLoading(true)
        
        licenseManager.activate(licenseKey: key, force: force) { [weak self] success, errorMsg in
            DispatchQueue.main.async {
                self?.setLoading(false)
                
                if success {
                    self?.close()
                    // Get AppDelegate to resume launch
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.completeSetup()
                    }
                    if force {
                        self?.showForceSuccess()
                    }
                } else {
                    if let msg = errorMsg, msg.contains("409") {
                        self?.showDeviceLimitAlert(key: key)
                    } else {
                        self?.statusLabel.stringValue = errorMsg ?? LanguageManager.shared.string("alert_activation_failed")
                        self?.statusLabel.textColor = .systemRed
                    }
                }
            }
        }
    }
    
    private func showDeviceLimitAlert(key: String) {
        let alert = NSAlert()
        let lm = LanguageManager.shared
        alert.messageText = lm.string("alert_device_limit_reached")
        alert.informativeText = lm.string("alert_max_devices")
        alert.addButton(withTitle: lm.string("btn_deactivate_oldest"))
        alert.addButton(withTitle: lm.string("cancel"))
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // User chose "Deactivate Oldest"
            performActivation(key: key, force: true)
        }
    }
    
    private func showForceSuccess() {
        let alert = NSAlert()
        let lm = LanguageManager.shared
        alert.messageText = lm.string("alert_device_deactivated")
        alert.informativeText = lm.string("alert_device_deactivated_message")
        alert.addButton(withTitle: lm.string("ok"))
        alert.runModal()
    }
    
    private func setLoading(_ loading: Bool) {
        inputField.isEnabled = !loading
        activateButton.isEnabled = !loading
        trialButton.isEnabled = !loading
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
}
