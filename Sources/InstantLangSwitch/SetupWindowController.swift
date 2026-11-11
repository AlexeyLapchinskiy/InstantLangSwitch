import AppKit

final class SetupWindowController: NSWindowController, NSWindowDelegate {
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
    private let defaults: UserDefaults
    private let inputMonitoringChanged: (Bool) -> Void
    private var lastInputMonitoringStatus: Bool?
    private var refreshTimer: Timer?

    static var hasCompletedSetup: Bool {
        UserDefaults.standard.bool(forKey: setupCompletedKey)
    }

    init(defaults: UserDefaults = .standard, inputMonitoringChanged: @escaping (Bool) -> Void) {
        self.defaults = defaults
        self.inputMonitoringChanged = inputMonitoringChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 556, height: 154),
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
        refresh()
        super.showWindow(sender)
        if refreshTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh(inputMonitoringGranted: Bool = KeyboardMonitor.hasInputMonitoringAccess) {
        let progress = SetupProgress(
            inputMonitoringGranted: inputMonitoringGranted,
            globeKeyAction: Self.readGlobeKeyAction(),
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
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let description = NSTextField(labelWithString: detail)
        description.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        description.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [heading, description])
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
