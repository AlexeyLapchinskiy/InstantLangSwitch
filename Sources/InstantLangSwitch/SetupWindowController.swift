import AppKit

final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private enum FnSwitchTest {
        case idle
        case waitingForFn
        case waitingForSelection(expectedID: String, deadline: TimeInterval)
        case retry
        case passed

        var isRunning: Bool {
            switch self {
            case .waitingForFn, .waitingForSelection, .retry: return true
            case .idle, .passed: return false
            }
        }
    }

    private static let setupCompletedKey = "initialSetupCompleted"
    private static let keyboardOpenedAtKey = "setupKeyboardPreferencesOpenedAt"
    private static let inputMonitoringURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
    )!
    private static let keyboardSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
    )!

    private let grantButton = NSButton(title: "Grant Access", target: nil, action: nil)
    private let keyboardButton = NSButton(title: "Open Keyboard Preferences", target: nil, action: nil)
    private let grantedLabel = NSTextField(labelWithString: "Granted")
    private let doneLabel = NSTextField(labelWithString: "Done")
    private let testButton = NSButton(title: "Start Test", target: nil, action: nil)
    private let testPassedLabel = NSTextField(labelWithString: "Passed")
    private let testDetailLabel = NSTextField(labelWithString: "")
    private let currentLayoutLabel = NSTextField(labelWithString: "")
    private let defaults: UserDefaults
    private let openSettings: () -> Void
    private let inputMonitoringChanged: (Bool) -> Void
    private var lastInputMonitoringStatus: Bool?
    private var refreshTimer: Timer?
    private var completedAt: TimeInterval?
    private var fnSwitchTest = FnSwitchTest.idle

    static var hasCompletedSetup: Bool {
        UserDefaults.standard.bool(forKey: setupCompletedKey)
    }

    init(
        defaults: UserDefaults = .standard,
        openSettings: @escaping () -> Void,
        inputMonitoringChanged: @escaping (Bool) -> Void
    ) {
        self.defaults = defaults
        self.openSettings = openSettings
        self.inputMonitoringChanged = inputMonitoringChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Set Up Instant Lang Switch"
        window.delegate = self
        window.isReleasedWhenClosed = false
        configureContent(in: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("SetupWindowController is created programmatically")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if refreshTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        completedAt = nil
        fnSwitchTest = .idle
    }

    func refresh(
        inputMonitoringGranted: Bool = KeyboardMonitor.hasInputMonitoringAccess,
        globeKeyAction: Int? = SetupWindowController.readGlobeKeyAction(),
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        currentInputSource: InputSource? = InputSources.current()
    ) {
        let progress = SetupProgress(
            inputMonitoringGranted: inputMonitoringGranted,
            globeKeyAction: globeKeyAction,
            keyboardOpenedAt: defaults.object(forKey: Self.keyboardOpenedAtKey) as? Date,
            now: Date()
        )

        grantButton.isHidden = progress.inputMonitoringGranted
        grantedLabel.isHidden = !progress.inputMonitoringGranted
        keyboardButton.isHidden = progress.keyboardDone
        doneLabel.isHidden = !progress.keyboardDone

        if lastInputMonitoringStatus != progress.inputMonitoringGranted {
            lastInputMonitoringStatus = progress.inputMonitoringGranted
            inputMonitoringChanged(progress.inputMonitoringGranted)
        }
        if progress.isComplete, !defaults.bool(forKey: Self.setupCompletedKey) {
            defaults.set(true, forKey: Self.setupCompletedKey)
        }
        currentLayoutLabel.stringValue = currentInputSource.map { "Current layout · \($0.name)" }
            ?? "No current layout reported."
        if !progress.isComplete {
            fnSwitchTest = .idle
        } else if case let .waitingForSelection(expectedID, deadline) = fnSwitchTest {
            if uptime > deadline {
                fnSwitchTest = .retry
            } else if currentInputSource?.id == expectedID {
                fnSwitchTest = .passed
            }
        }
        updateFnTestControls(ready: progress.isComplete)

        guard progress.isComplete, window?.isVisible == true, !fnSwitchTest.isRunning else {
            completedAt = nil
            return
        }

        let completedAt = self.completedAt ?? uptime
        self.completedAt = completedAt
        let remaining = 10 - (uptime - completedAt)
        if remaining <= 0 {
            close()
            openSettings()
        } else if let refreshTimer {
            let deadline = Date(timeIntervalSinceNow: remaining)
            if deadline < refreshTimer.fireDate {
                refreshTimer.fireDate = deadline
            }
        }
    }

    func didRequestFnSwitch(
        from previousID: String,
        to expectedID: String,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard window?.isVisible == true, fnSwitchTest.isRunning, previousID != expectedID else { return }
        fnSwitchTest = .waitingForSelection(expectedID: expectedID, deadline: uptime + 3)
        updateFnTestControls(ready: true)
    }

    func didFailFnSwitch() {
        guard window?.isVisible == true, fnSwitchTest.isRunning else { return }
        fnSwitchTest = .retry
        updateFnTestControls(ready: true)
    }

    @objc private func startOrCancelFnTest() {
        guard window?.isVisible == true, testButton.isEnabled else { return }
        fnSwitchTest = fnSwitchTest.isRunning ? .idle : .waitingForFn
        completedAt = nil
        updateFnTestControls(ready: true)
    }

    private func updateFnTestControls(ready: Bool) {
        testButton.isEnabled = ready || fnSwitchTest.isRunning
        testButton.title = fnSwitchTest.isRunning ? "Cancel Test" : "Start Test"
        testButton.isHidden = false
        testPassedLabel.isHidden = true
        switch fnSwitchTest {
        case .idle:
            testDetailLabel.stringValue = ready ? "Try switching with Fn or Globe." : "Complete the steps above to test."
        case .waitingForFn:
            testDetailLabel.stringValue = "Tap and release Fn or Globe by itself."
        case .waitingForSelection:
            testDetailLabel.stringValue = "Waiting for macOS to report the new layout."
        case .retry:
            testDetailLabel.stringValue = "Check that two layouts are available, then tap Fn again."
        case .passed:
            testDetailLabel.stringValue = "macOS confirmed the new layout."
            testButton.isHidden = true
            testPassedLabel.isHidden = false
        }
    }

    static func openInputMonitoring() {
        KeyboardMonitor.requestInputMonitoringAccessIfUndetermined()
        NSWorkspace.shared.open(inputMonitoringURL)
    }

    private static func readGlobeKeyAction() -> Int? {
        // macOS stores this in HIToolbox. Use the timed fallback if the preference is unavailable.
        let domain = "com.apple.HIToolbox" as CFString
        guard CFPreferencesAppSynchronize(domain),
              let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain),
              CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        return value as? Int
    }

    @objc private func grantAccess() {
        Self.openInputMonitoring()
        refresh()
    }

    @objc private func openKeyboardPreferences() {
        if NSWorkspace.shared.open(Self.keyboardSettingsURL) {
            defaults.set(Date(), forKey: Self.keyboardOpenedAtKey)
        }
        refresh()
    }

    private func configureContent(in window: NSWindow) {
        guard let contentView = window.contentView else { return }

        grantButton.target = self
        grantButton.action = #selector(grantAccess)
        keyboardButton.target = self
        keyboardButton.action = #selector(openKeyboardPreferences)
        testButton.target = self
        testButton.action = #selector(startOrCancelFnTest)

        let testInstructions = instruction("Test Fn switching (optional)", detail: testDetailLabel)
        currentLayoutLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        currentLayoutLabel.textColor = .secondaryLabelColor
        currentLayoutLabel.lineBreakMode = .byTruncatingTail
        currentLayoutLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        testInstructions.addArrangedSubview(currentLayoutLabel)

        let grid = NSGridView(views: [
            [
                instruction("1. Allow keyboard input access", detail: "Enable it in Input Monitoring. Reopen if prompted."),
                actionView(button: grantButton, status: grantedLabel)
            ],
            [
                instruction(
                    "2. Set “Press 🌐 key to” to “Do Nothing”",
                    detail: "On some keyboards, this is called “Press fn key to.”"
                ),
                actionView(button: keyboardButton, status: doneLabel)
            ],
            [
                testInstructions,
                actionView(button: testButton, status: testPassedLabel)
            ]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowAlignment = .none
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        grid.columnSpacing = 24
        grid.rowSpacing = 22

        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            grid.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    private func instruction(_ title: String, detail: String) -> NSStackView {
        instruction(title, detail: NSTextField(labelWithString: detail))
    }

    private func instruction(_ title: String, detail: NSTextField) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [heading, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }

    private func actionView(button: NSButton, status: NSTextField) -> NSView {
        let view = NSView()
        button.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        status.textColor = .systemGreen
        view.addSubview(button)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: keyboardButton.intrinsicContentSize.width),
            view.heightAnchor.constraint(equalToConstant: 28),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }
}
