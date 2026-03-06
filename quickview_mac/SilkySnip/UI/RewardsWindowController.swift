import Cocoa

class RewardsWindowController: NSWindowController {
    
    private var lifetimeLabel: NSTextField!
    private var monthlyLabel: NSTextField!
    private var claimButton: NSButton!
    private var statusLabel: NSTextField!
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = LanguageManager.shared.string("title_referrals_rewards")
        window.center()
        
        self.init(window: window)
        setupContent()
        
        // Mock Load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateStats(lifetime: 0, monthly: 0)
        }
    }
    
    private func setupContent() {
        guard let window = window else { return }
        let contentView = window.contentView!
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // Title
        let lm = LanguageManager.shared
        let titleValues = [
            (lm.string("label_refer_earn"), NSFont.boldSystemFont(ofSize: 18)),
            (lm.string("label_refer_earn_desc"), NSFont.systemFont(ofSize: 13))
        ]
        
        for (text, font) in titleValues {
            let label = NSTextField(labelWithString: text)
            label.font = font
            stack.addArrangedSubview(label)
        }
        
        stack.addArrangedSubview(NSBox()) // Separator
        
        // Stats Grid
        let grid = NSGridView(views: [
            [createLabel(lm.string("label_lifetime_referrals")), createValueLabel(&lifetimeLabel)],
            [createLabel(lm.string("label_monthly_referrals")), createValueLabel(&monthlyLabel)]
        ])
        grid.columnSpacing = 20
        grid.rowSpacing = 10
        stack.addArrangedSubview(grid)
        
        // Claim Button
        claimButton = NSButton(title: lm.string("btn_claim_reward"), target: self, action: #selector(onClaim))
        claimButton.bezelStyle = .rounded
        claimButton.isEnabled = false
        stack.addArrangedSubview(claimButton)
        
        // Status
        statusLabel = NSTextField(labelWithString: lm.string("label_loading_stats"))
        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.boldSystemFont(ofSize: 13)
        return l
    }
    
    private func createValueLabel(_ ref: inout NSTextField!) -> NSTextField {
        let l = NSTextField(labelWithString: "-")
        ref = l
        return l
    }
    
    func updateStats(lifetime: Int, monthly: Int) {
        let lm = LanguageManager.shared
        lifetimeLabel.stringValue = "\(lifetime) " + lm.string("label_confirmed")
        monthlyLabel.stringValue = "\(monthly) " + lm.string("label_confirmed")
        statusLabel.stringValue = lm.string("label_invite_friends")
        
        // Logic: 2 confirmed = reward
        claimButton.isEnabled = (lifetime >= 2 || monthly >= 2)
    }
    
    @objc func onClaim() {
        let alert = NSAlert()
        let lm = LanguageManager.shared
        alert.messageText = lm.string("alert_coming_soon")
        alert.informativeText = lm.string("alert_rewards_coming")
        alert.runModal()
    }
}
