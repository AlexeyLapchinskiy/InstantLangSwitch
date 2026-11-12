import AppKit
import Carbon
import OSLog

struct Shortcut: Codable, Equatable {
    private static let modifiers: [(flag: NSEvent.ModifierFlags, carbon: UInt32, symbol: String)] = [
        (.control, UInt32(controlKey), "⌃"),
        (.option, UInt32(optionKey), "⌥"),
        (.shift, UInt32(shiftKey), "⇧"),
        (.command, UInt32(cmdKey), "⌘")
    ]
    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_RightCommand), UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption), UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_CapsLock), UInt16(kVK_Function)
    ]

    fileprivate let keyCode: UInt16
    fileprivate let carbonModifiers: UInt32
    private let keyTitle: String

    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, keyTitle: String) {
        self.keyCode = keyCode
        carbonModifiers = Self.modifiers.reduce(0) { mask, modifier in
            modifierFlags.contains(modifier.flag) ? mask | modifier.carbon : mask
        }
        self.keyTitle = keyTitle.uppercased()
        guard isValid else { return nil }
    }

    var title: String {
        let symbols = Self.modifiers.compactMap { modifier in
            carbonModifiers & modifier.carbon != 0 ? modifier.symbol : nil
        }
        return symbols.joined() + keyTitle
    }

    fileprivate var isValid: Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let required = UInt32(cmdKey | controlKey | optionKey)
        return carbonModifiers & required != 0 &&
            carbonModifiers & ~allowed == 0 &&
            keyCode <= 0x7F &&
            !Self.modifierKeyCodes.contains(keyCode) &&
            !keyTitle.isEmpty &&
            keyTitle.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    fileprivate func matches(_ other: Shortcut) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }
}

// Carbon's event handler and registration are confined to the main event loop.
final class GlobalShortcuts {
    private struct Registration {
        let id: UInt32
        let shortcut: Shortcut
        let ref: EventHotKeyRef
    }

    private static let signature: OSType = 0x494C5357 // ILSW
    private let logger = Logger(subsystem: "com.alexeylapchinskiy.InstantLangSwitch", category: "Shortcuts")
    private let onTrigger: () -> Void
    private var handler: EventHandlerRef?
    private var registration: Registration?
    private var shortcut: Shortcut?
    private var nextID: UInt32 = 0
    private var isRecording = false

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        stop()
    }

    @discardableResult
    func set(_ shortcut: Shortcut?) -> Bool {
        guard let shortcut else {
            unregister()
            self.shortcut = nil
            return true
        }

        guard shortcut.isValid, !isRecording else { return false }
        if let registration, shortcut.matches(registration.shortcut) {
            self.shortcut = shortcut
            return true
        }

        guard let replacement = register(shortcut) else { return false }
        unregister()
        registration = replacement
        self.shortcut = shortcut
        return true
    }

    func setRecording(_ isRecording: Bool) {
        guard self.isRecording != isRecording else { return }
        self.isRecording = isRecording
        if isRecording {
            unregister()
        } else if let shortcut {
            registration = register(shortcut)
            if registration == nil {
                logger.error("Could not restore the layout switch shortcut.")
            }
        }
    }

    func stop() {
        unregister()
        shortcut = nil
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        isRecording = false
    }

    private func unregister() {
        if let registration {
            UnregisterEventHotKey(registration.ref)
            self.registration = nil
        }
    }

    private func register(_ shortcut: Shortcut) -> Registration? {
        guard !Self.isSystemShortcut(shortcut), installHandlerIfNeeded() else { return nil }
        nextID &+= 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: nextID),
            GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref
        )
        guard status == noErr, let ref else { return nil }
        return Registration(id: nextID, shortcut: shortcut, ref: ref)
    }

    private static func isSystemShortcut(_ shortcut: Shortcut) -> Bool {
        var keys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&keys) == noErr,
              let entries = keys?.takeRetainedValue() as? [[String: NSNumber]] else { return false }
        return entries.contains {
            $0["kHISymbolicHotKeyEnabled"]?.boolValue == true &&
                $0["kHISymbolicHotKeyCode"]?.uint16Value == shortcut.keyCode &&
                $0["kHISymbolicHotKeyModifiers"]?.uint32Value == shortcut.carbonModifiers
        }
    }

    private func installHandlerIfNeeded() -> Bool {
        if handler != nil { return true }
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )
        return InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue().handle(event)
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id
        )
        guard status == noErr, id.signature == Self.signature, registration?.id == id.id else {
            return OSStatus(eventNotHandledErr)
        }
        onTrigger()
        return noErr
    }
}

final class ShortcutRecorder: NSButton {
    private static let specialKeyTitles: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Enter",
        kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete", kVK_Tab: "Tab",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    var shortcut: Shortcut? {
        didSet { updateTitle() }
    }
    var onRecord: ((Shortcut) -> Bool)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var eventMonitor: Any?
    private var pendingShortcut: Shortcut?

    init() {
        super.init(frame: .zero)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRecorder is created programmatically")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow != window { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func toggleRecording() {
        if eventMonitor != nil {
            stopRecording()
            return
        }
        guard let window, window.makeFirstResponder(self) else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            self.capture(event)
            return nil
        }
        guard eventMonitor != nil else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(stopRecording), name: NSWindow.didResignKeyNotification, object: window
        )
        onRecordingChanged?(true)
        updateTitle()
    }

    private func capture(_ event: NSEvent) {
        if event.type == .keyUp {
            guard let pendingShortcut, pendingShortcut.keyCode == event.keyCode else { return }
            stopRecording()
            if onRecord?(pendingShortcut) == true {
                shortcut = pendingShortcut
            }
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        guard !event.isARepeat, pendingShortcut == nil else { return }

        let keyTitle = Self.specialKeyTitles[Int(event.keyCode)]
            ?? event.characters(byApplyingModifiers: [])
            ?? event.charactersIgnoringModifiers
        guard let keyTitle, let shortcut = Shortcut(
            keyCode: event.keyCode, modifierFlags: event.modifierFlags, keyTitle: keyTitle
        ) else {
            NSSound.beep()
            return
        }
        pendingShortcut = shortcut
    }

    @objc private func stopRecording() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
        pendingShortcut = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        onRecordingChanged?(false)
        updateTitle()
    }

    private func updateTitle() {
        title = eventMonitor == nil ? (shortcut?.title ?? "Record Shortcut…") : "Press shortcut…"
    }
}
