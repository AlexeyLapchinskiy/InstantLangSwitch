import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let keyboardMonitor = KeyboardMonitor()
    private let loginItem = SMAppService.mainApp
    private let preferences = Preferences()
    private lazy var globalShortcuts = GlobalShortcuts { [weak self] action in
        switch action {
        case .switchLayout: self?.switchLayout(fromFn: false)
        case .correctSelection: self?.correctSelectedText()
        }
    }

    private var statusItem: NSStatusItem!
    private var monitoringMenuItem: NSMenuItem!
    private var layoutMenuItems: [NSMenuItem] = []
    private var menuBarPreference: AnyCancellable?
    private var setupWindow: SetupWindowController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        observeInputSources()
        keyboardMonitor.onTap = { [weak self] in self?.switchLayout(fromFn: true) }
        refreshMonitoring()
        for action in ShortcutAction.allCases {
            guard let shortcut = preferences.shortcut(for: action) else { continue }
            if !globalShortcuts.set(shortcut, for: action) {
                preferences.shortcutErrors[action] = "This shortcut is unavailable. Record another combination."
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )

        if !SetupWindowController.hasCompletedSetup {
            showSetup()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshMonitoring()
        preferences.startupStatus = loginItem.status
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
        globalShortcuts.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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

    private func observeInputSources() {
        let center = DistributedNotificationCenter.default()
        for name in [InputSources.selectedChanged, InputSources.enabledChanged] {
            center.addObserver(self, selector: #selector(inputSourcesDidChange(_:)), name: name, object: nil)
        }
        preferences.refreshSources()
        menuBarPreference = preferences.$configuration
            .map(\.showActiveLayout)
            .removeDuplicates()
            .sink { [weak self] in self?.updateStatusItem(showActiveLayout: $0) }
    }

    @objc private func inputSourcesDidChange(_ notification: Notification) {
        preferences.refreshSources()
        updateStatusItem(showActiveLayout: preferences.configuration.showActiveLayout)
        if setupWindow?.window?.isVisible == true {
            setupWindow?.refresh()
        }
    }

    private func updateStatusItem(showActiveLayout: Bool) {
        let current = InputSources.current()
        statusItem.button?.toolTip = current.map { "Instant Lang Switch · \($0.name)" } ?? "Instant Lang Switch"
        statusItem.button?.setAccessibilityLabel(statusItem.button?.toolTip)
        if showActiveLayout, let current {
            statusItem.length = NSStatusItem.variableLength
            statusItem.button?.image = nil
            statusItem.button?.title = current.shortLabel
        } else {
            statusItem.length = NSStatusItem.squareLength
            let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
            image?.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = image == nil ? "⇄" : ""
        }
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        InputSources.select(id: id)
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = application.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return }
        DispatchQueue.main.async { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
                  let id = self?.preferences.configuration.appRules.first(where: { $0.id == bundleID })?.sourceID else {
                return
            }
            InputSources.select(id: id)
        }
    }

    private func switchLayout(fromFn: Bool) {
        let change = InputSources.selectNext(favorites: preferences.configuration.favorites)
        guard fromFn, let change, let previous = change.previousID else { return }
        setupWindow?.didRequestFnSwitch(from: previous, to: change.selectedID)
        if setupWindow?.window?.isVisible == true {
            setupWindow?.refresh()
        }
    }

    private func correctSelectedText() {
        preferences.refreshSources()
        guard let pair = preferences.correctionPair,
              let first = InputSources.layoutData(for: pair.first.id),
              let second = InputSources.layoutData(for: pair.second.id) else {
            showAlert("Text correction needs two layouts", detail: SelectionCorrection.pairRequirement)
            return
        }

        let activeID = InputSources.current()?.id
        let preferredDestination: SelectionCorrection.Destination?
        switch activeID {
        case pair.first.id: preferredDestination = .first
        case pair.second.id: preferredDestination = .second
        default: preferredDestination = nil
        }
        do {
            try SelectionCorrection.correct(
                first: first, second: second, preferredDestination: preferredDestination,
                application: NSWorkspace.shared.frontmostApplication
            )
        } catch {
            showAlert("Couldn’t correct selected text", detail: error.localizedDescription)
        }
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
        preferences.refreshSources()
        preferences.startupStatus = loginItem.status
        if settingsWindow == nil {
            let bundle = Bundle.main
            let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Instant Lang Switch"
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let footer = version.map { "\(appName) · Version \($0)" } ?? appName
            let view = PreferencesView(
                preferences: preferences, footer: footer,
                openSetup: { [weak self] in self?.showSetup() },
                changeStartup: { [weak self] in self?.changeStartup($0) },
                setShortcut: { [weak self] in self?.setShortcut($0, for: $1) ?? false },
                setRecording: { [weak self] in self?.globalShortcuts.setRecording($0) }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 555, height: 410),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view.frame(width: 555, height: 410))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) -> Bool {
        guard globalShortcuts.set(shortcut, for: action) else {
            preferences.shortcutErrors[action] = "This shortcut is unavailable. Record another combination."
            return false
        }
        preferences.shortcutErrors[action] = nil
        preferences.saveShortcut(shortcut, for: action)
        return true
    }

    private func changeStartup(_ enabled: Bool) {
        defer { preferences.startupStatus = loginItem.status }
        do {
            if enabled {
                try loginItem.register()
                if loginItem.status == .requiresApproval {
                    showLoginItemApproval()
                }
            } else {
                try loginItem.unregister()
            }
        } catch {
            if enabled, loginItem.status == .requiresApproval {
                showLoginItemApproval()
            } else {
                showAlert("Couldn’t change Open on startup", detail: error.localizedDescription)
            }
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

    private func showAlert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMonitoring()
        preferences.refreshSources()
        layoutMenuItems.forEach { menu.removeItem($0) }
        let currentID = InputSources.current()?.id
        layoutMenuItems = preferences.sources.map { source in
            let item = NSMenuItem(title: source.name, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.representedObject = source.id
            item.state = source.id == currentID ? .on : .off
            item.target = self
            return item
        }
        if !layoutMenuItems.isEmpty {
            layoutMenuItems.append(.separator())
        }
        for (index, item) in layoutMenuItems.enumerated() {
            menu.insertItem(item, at: index)
        }
    }
}
