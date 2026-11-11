import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let keyboardMonitor = KeyboardMonitor()
    private let loginItem = SMAppService.mainApp
    private var statusItem: NSStatusItem!
    private var monitoringMenuItem: NSMenuItem!
    private var setupWindow: SetupWindowController?
    private var settingsWindow: NSWindow?
    private var startupToggle: NSSwitch?
    private var startupApprovalLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        refreshMonitoring()

        if !SetupWindowController.hasCompletedSetup {
            showSetup()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshMonitoring()
        refreshStartupToggle()
        if setupWindow?.window?.isVisible == true {
            setupWindow?.refresh()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if SetupWindowController.hasCompletedSetup {
            showSettings()
        } else {
            showSetup()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.stop()
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Instant Lang Switch") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "⇄"
        }
        statusItem.button?.toolTip = "Instant Lang Switch"

        let menu = NSMenu()
        menu.delegate = self
        let setupItem = NSMenuItem(title: "Setup…", action: #selector(showSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        monitoringMenuItem = NSMenuItem(
            title: "Enable Input Monitoring…",
            action: #selector(enableInputMonitoring),
            keyEquivalent: ""
        )
        monitoringMenuItem.target = self
        menu.addItem(monitoringMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Instant Lang Switch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func refreshMonitoring(inputMonitoringGranted: Bool = KeyboardMonitor.hasInputMonitoringAccess) {
        guard let monitoringMenuItem else { return }
        if inputMonitoringGranted {
            let started = keyboardMonitor.start()
            monitoringMenuItem.title = "Retry Keyboard Monitoring"
            monitoringMenuItem.isHidden = started
        } else {
            keyboardMonitor.stop()
            monitoringMenuItem.title = "Enable Input Monitoring…"
            monitoringMenuItem.isHidden = false
        }
    }

    @objc private func enableInputMonitoring() {
        if !KeyboardMonitor.hasInputMonitoringAccess {
            SetupWindowController.openInputMonitoring()
        }
        refreshMonitoring()
    }

    @objc private func showSetup() {
        if setupWindow == nil {
            setupWindow = SetupWindowController(openSettings: { [weak self] in
                self?.showSettings()
            }) { [weak self] granted in
                self?.refreshMonitoring(inputMonitoringGranted: granted)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.showWindow(nil)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let bundle = Bundle.main
            let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Instant Lang Switch"
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 344, height: 126),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "\(appName) Settings"
            window.isReleasedWhenClosed = false

            let startupLabel = NSTextField(labelWithString: "Open on startup")
            let approvalLabel = NSTextField(labelWithString: "Approval required in Login Items")
            approvalLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            approvalLabel.textColor = .secondaryLabelColor

            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(changeStartup(_:))
            toggle.setAccessibilityLabel(startupLabel.stringValue)

            let separator = NSBox()
            separator.boxType = .separator

            var footerText = appName
            if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                footerText += " · Version \(version)"
            }
            let footer = NSTextField(labelWithString: footerText)
            footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            footer.textColor = .secondaryLabelColor

            if let contentView = window.contentView {
                for view in [startupLabel, approvalLabel, toggle, separator, footer] {
                    view.translatesAutoresizingMaskIntoConstraints = false
                    contentView.addSubview(view)
                }
                NSLayoutConstraint.activate([
                    toggle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 23),
                    toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
                    startupLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
                    startupLabel.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
                    startupLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
                    approvalLabel.leadingAnchor.constraint(equalTo: startupLabel.leadingAnchor),
                    approvalLabel.topAnchor.constraint(equalTo: startupLabel.bottomAnchor, constant: 5),
                    separator.leadingAnchor.constraint(equalTo: startupLabel.leadingAnchor),
                    separator.trailingAnchor.constraint(equalTo: toggle.trailingAnchor),
                    separator.heightAnchor.constraint(equalToConstant: 1),
                    separator.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
                    footer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                    footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
                ])
            }

            window.center()
            startupToggle = toggle
            startupApprovalLabel = approvalLabel
            settingsWindow = window
        }
        refreshStartupToggle()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshStartupToggle() {
        guard let startupToggle else { return }
        let status = loginItem.status
        let needsApproval = status == .requiresApproval
        startupToggle.state = status == .enabled || needsApproval ? .on : .off
        startupToggle.toolTip = needsApproval ? "Approve Instant Lang Switch in Login Items" : nil
        startupApprovalLabel?.isHidden = !needsApproval
    }

    @objc private func changeStartup(_ sender: NSSwitch) {
        defer { refreshStartupToggle() }
        do {
            if sender.state == .on {
                try loginItem.register()
                if loginItem.status == .requiresApproval {
                    showLoginItemApproval()
                }
            } else {
                try loginItem.unregister()
            }
        } catch {
            if sender.state == .on, loginItem.status == .requiresApproval {
                showLoginItemApproval()
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t change Open on startup"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func showLoginItemApproval() {
        let alert = NSAlert()
        alert.messageText = "Approve Open on startup"
        alert.informativeText = "Allow Instant Lang Switch in Login Items to launch it when you sign in."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMonitoring()
    }
}
