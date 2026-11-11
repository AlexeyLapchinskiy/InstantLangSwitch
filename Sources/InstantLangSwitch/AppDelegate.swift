import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let keyboardMonitor = KeyboardMonitor()
    private let loginItem = SMAppService.mainApp
    private var statusItem: NSStatusItem!
    private var monitoringMenuItem: NSMenuItem!
    private var setupWindow: SetupWindowController?
    private var settingsWindow: NSWindow?
    private var startupCheckbox: NSButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        refreshMonitoring()

        if !SetupWindowController.hasCompletedSetup {
            showSetup()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshMonitoring()
        refreshStartupCheckbox()
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
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 92),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Instant Lang Switch"
            window.isReleasedWhenClosed = false

            let checkbox = NSButton(checkboxWithTitle: "Open on startup", target: self, action: #selector(changeStartup(_:)))
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            if let contentView = window.contentView {
                contentView.addSubview(checkbox)
                NSLayoutConstraint.activate([
                    checkbox.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                    checkbox.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
                ])
            }

            window.center()
            startupCheckbox = checkbox
            settingsWindow = window
        }
        refreshStartupCheckbox()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshStartupCheckbox() {
        guard let startupCheckbox else { return }
        let status = loginItem.status
        let needsApproval = status == .requiresApproval
        startupCheckbox.allowsMixedState = needsApproval
        startupCheckbox.state = needsApproval ? .mixed : (status == .enabled ? .on : .off)
        startupCheckbox.toolTip = needsApproval ? "Approve Instant Lang Switch in Login Items" : nil
    }

    @objc private func changeStartup(_ sender: NSButton) {
        defer { refreshStartupCheckbox() }
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
