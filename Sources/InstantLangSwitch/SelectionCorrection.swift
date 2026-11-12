import AppKit
import ApplicationServices
import Carbon
import OSLog

enum SelectionCorrection {
    enum Destination {
        case first, second
    }

    private enum Failure: LocalizedError {
        case accessibilityRequired
        case secureInput
        case unsupportedField
        case noSelection
        case incompatibleLayouts
        case ambiguousDirection
        case unchanged
        case selectionChanged
        case couldNotReplace
        case clipboardUnavailable

        var errorDescription: String? {
            switch self {
            case .accessibilityRequired:
                return "In System Settings → Privacy & Security, allow Instant Lang Switch to control apps, then try again. Look for Accessibility or Device Control and Data Access."
            case .secureInput:
                return "Text correction is unavailable while secure keyboard input is active."
            case .unsupportedField:
                return "Select text in an editable field that exposes its selection to macOS Accessibility."
            case .noSelection:
                return "Select the text you want to correct first."
            case .incompatibleLayouts:
                return "Choose two keyboard layouts that support physical-key conversion."
            case .ambiguousDirection:
                return "Switch to the layout you want to convert to, then try again."
            case .unchanged:
                return "The selection has no characters that can be converted between these layouts."
            case .selectionChanged:
                return "The active selection changed. Select the text and try again."
            case .couldNotReplace:
                return "The active app couldn’t replace the selected text."
            case .clipboardUnavailable:
                return "The clipboard couldn’t be preserved for this edit. Try again after copying plain text."
            }
        }
    }

    private static let messagingTimeout: Float = 0.3
    private static let logger = Logger(subsystem: "com.alexeylapchinskiy.InstantLangSwitch", category: "TextCorrection")
    private static let selectedTextMarkerRange = "AXSelectedTextMarkerRange"
    private static var pasteInProgress = false
    static let pairRequirement = "Enable exactly two keyboard layouts in macOS or select two enabled favorites in Layouts. Both must support text correction."

    static func layoutPair(in sources: [InputSource], favorites: [String]) -> (first: InputSource, second: InputSource)? {
        let favorites = Set(favorites)
        let selected = sources.filter { favorites.contains($0.id) }
        let pair = selected.count == 2 ? selected : sources
        guard pair.count == 2, pair.allSatisfy(\.supportsTextCorrection) else { return nil }
        return (pair[0], pair[1])
    }

    static func correct(
        first: Data, second: Data, preferredDestination: Destination?, application: NSRunningApplication?
    ) throws {
        guard !IsSecureEventInputEnabled() else { throw Failure.secureInput }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw Failure.accessibilityRequired }

        let frontmost = NSWorkspace.shared.frontmostApplication
        guard let application = application ?? frontmost,
              application.processIdentifier == frontmost?.processIdentifier else { throw Failure.unsupportedField }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard let field = focusedField(in: appElement) else { throw Failure.unsupportedField }
        AXUIElementSetMessagingTimeout(field, messagingTimeout)

        if attribute(kAXSubroleAttribute, of: field) as? String == kAXSecureTextFieldSubrole {
            throw Failure.secureInput
        }
        let selectedTextAttribute = kAXSelectedTextAttribute as CFString
        guard let selection = selection(in: field) else {
            throw Failure.noSelection
        }
        let corrected = try convert(selection.text, first: first, second: second, preferredDestination: preferredDestination)
        guard corrected != selection.text else { throw Failure.unchanged }

        func validateSelection() throws {
            guard !IsSecureEventInputEnabled() else { throw Failure.secureInput }
            guard let focused = focusedField(in: appElement), CFEqual(field, focused),
                  let current = Self.selection(in: field), selection.matches(current),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
                throw Failure.selectionChanged
            }
        }

        try validateSelection()
        let canPasteSelection = selection.range != nil && canPaste(into: field)
        // Web editors can report success before their selected-text setter applies an edit.
        let preferPaste = canPasteSelection && attribute("AXDOMClassList", of: field) is [String]
        try replaceSelectedText {
            guard !preferPaste, selection.rangeAttribute != selectedTextMarkerRange,
                  isSettable(kAXSelectedTextAttribute, in: field) else { return .attributeUnsupported }
            return AXUIElementSetAttributeValue(field, selectedTextAttribute, corrected as CFString)
        } paste: {
            guard canPasteSelection else { throw Failure.unsupportedField }
            try paste(corrected, into: application.processIdentifier, validateSelection: validateSelection)
        }
    }

    static func replaceSelectedText(setAttribute: () -> AXError, paste: () throws -> Void) throws {
        let status = setAttribute()
        switch status {
        case .success:
            return
        case .attributeUnsupported, .notImplemented, .illegalArgument:
            try paste()
        default:
            logger.error("Selected text replacement failed with AX status \(status.rawValue).")
            throw Failure.couldNotReplace
        }
    }

    private struct Selection {
        let text: String
        let range: CFTypeRef?
        let rangeAttribute: String

        func matches(_ other: Selection) -> Bool {
            guard text == other.text, rangeAttribute == other.rangeAttribute else { return false }
            if let range, let otherRange = other.range { return CFEqual(range, otherRange) }
            return range == nil && other.range == nil
        }
    }

    private static func selection(in field: AXUIElement) -> Selection? {
        let selected = attribute(kAXSelectedTextAttribute, of: field) as? String
        if let selected, !selected.isEmpty, let range = attribute(kAXSelectedTextRangeAttribute, of: field) {
            var bounds = CFRange()
            if CFGetTypeID(range) == AXValueGetTypeID(),
               AXValueGetValue(range as! AXValue, .cfRange, &bounds), bounds.length > 0 {
                return Selection(text: selected, range: range, rangeAttribute: kAXSelectedTextRangeAttribute)
            }
        }
        // Web editors may represent the selection with text markers instead of a character range.
        if let markerRange = attribute(selectedTextMarkerRange, of: field) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                field, "AXStringForTextMarkerRange" as CFString, markerRange, &value
            ) == .success, let text = value as? String, !text.isEmpty {
                return Selection(text: text, range: markerRange, rangeAttribute: selectedTextMarkerRange)
            }
        }
        guard let selected, !selected.isEmpty else { return nil }
        return Selection(text: selected, range: nil, rangeAttribute: kAXSelectedTextRangeAttribute)
    }

    private static func isSettable(_ name: String, in field: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(field, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func canPaste(into field: AXUIElement) -> Bool {
        let role = attribute(kAXRoleAttribute, of: field) as? String
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? ""),
           isSettable(kAXValueAttribute, in: field) { return true }
        guard let editable = attribute("AXEditableAncestor", of: field),
              CFGetTypeID(editable) == AXUIElementGetTypeID() else { return false }
        return true
    }

    private static func paste(_ text: String, into pid: pid_t, validateSelection: () throws -> Void) throws {
        guard !pasteInProgress else { throw Failure.couldNotReplace }
        guard CGPreflightPostEventAccess() else { throw Failure.accessibilityRequired }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw Failure.couldNotReplace
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        let pasteCharacter: [UniChar] = [0x76]
        down.keyboardSetUnicodeString(stringLength: pasteCharacter.count, unicodeString: pasteCharacter)
        up.keyboardSetUnicodeString(stringLength: pasteCharacter.count, unicodeString: pasteCharacter)

        let restore = try stagePaste(text, on: .general, validateSelection: validateSelection)
        pasteInProgress = true
        down.postToPid(pid)
        up.postToPid(pid)
        // Let the target consume the paste and preserve anything copied in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            restore()
            pasteInProgress = false
        }
    }

    static func stagePaste(_ text: String, on board: NSPasteboard, validateSelection: () throws -> Void) throws -> () -> Void {
        let originalCount = board.changeCount
        let saved = try (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else {
                    throw Failure.clipboardUnavailable
                }
            }
            return copy
        }
        try validateSelection()
        guard board.changeCount == originalCount else { throw Failure.clipboardUnavailable }
        let temporary = NSPasteboardItem()
        guard temporary.setString(text, forType: .string) else { throw Failure.clipboardUnavailable }
        temporary.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let clearedCount = board.prepareForNewContents(with: .currentHostOnly)
        guard board.writeObjects([temporary]) else {
            if board.changeCount == clearedCount, !saved.isEmpty { board.writeObjects(saved) }
            throw Failure.clipboardUnavailable
        }
        let temporaryCount = board.changeCount
        return {
            guard board.changeCount == temporaryCount else { return }
            board.clearContents()
            if !saved.isEmpty { board.writeObjects(saved) }
        }
    }

    static func convert(_ text: String, first: Data, second: Data, preferredDestination: Destination? = nil) throws -> String {
        let keyboardType = UInt32(LMGetKbdType())
        let modifiers: [UInt32] = [0, UInt32(shiftKey >> 8)]
        guard first.count >= MemoryLayout<UCKeyboardLayout>.size,
              second.count >= MemoryLayout<UCKeyboardLayout>.size else { throw Failure.incompatibleLayouts }

        let maps = first.withUnsafeBytes { firstBytes in
            second.withUnsafeBytes { secondBytes in
                let firstLayout = firstBytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
                let secondLayout = secondBytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
                var firstToSecond: [(Character, Character?)] = []
                var secondToFirst: [(Character, Character?)] = []
                for modifier in modifiers {
                    for key in UInt16(0)...127 {
                        let a = translate(key, modifier: modifier, keyboardType: keyboardType, layout: firstLayout)
                        let b = translate(key, modifier: modifier, keyboardType: keyboardType, layout: secondLayout)
                        if let a { firstToSecond.append((a, b)) }
                        if let b { secondToFirst.append((b, a)) }
                    }
                }
                return (forward: characterMap(from: firstToSecond), reverse: characterMap(from: secondToFirst))
            }
        }

        // Letters shared by both layouts and punctuation cannot reliably identify the source layout.
        var evidence = 0
        for character in text where character.isLetter {
            switch (maps.forward[character], maps.reverse[character]) {
            case (.some, .none): evidence += 1
            case (.none, .some): evidence -= 1
            default: break
            }
        }
        let destination: Destination
        if evidence > 0 {
            destination = .second
        } else if evidence < 0 {
            destination = .first
        } else if let preferredDestination {
            destination = preferredDestination
        } else {
            let forward = String(text.map { maps.forward[$0] ?? $0 })
            let reverse = String(text.map { maps.reverse[$0] ?? $0 })
            guard forward == reverse else { throw Failure.ambiguousDirection }
            return forward
        }
        let mapping = destination == .second ? maps.forward : maps.reverse
        guard !mapping.isEmpty else { throw Failure.incompatibleLayouts }
        return String(text.map { mapping[$0] ?? $0 })
    }

    static func characterMap(from candidates: [(Character, Character?)]) -> [Character: Character] {
        var mappings: [Character: Character] = [:]
        var ambiguous: Set<Character> = []
        for (character, replacement) in candidates {
            guard let replacement else {
                ambiguous.insert(character)
                continue
            }
            if let previous = mappings[character], previous != replacement {
                ambiguous.insert(character)
            }
            mappings[character] = replacement
        }
        return mappings.filter { !ambiguous.contains($0.key) }
    }

    private static func translate(
        _ key: UInt16, modifier: UInt32, keyboardType: UInt32, layout: UnsafePointer<UCKeyboardLayout>
    ) -> Character? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, key, UInt16(kUCKeyActionDown), modifier, keyboardType, 0,
            &deadKeyState, units.count, &length, &units
        )
        guard status == noErr, deadKeyState == 0, length > 0 else { return nil }
        let text = String(decoding: units.prefix(length), as: UTF16.self)
        guard text.count == 1, let character = text.first, !character.isWhitespace,
              !character.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .privateUse
              }) else { return nil }
        return character
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func focusedField(in app: AXUIElement) -> AXUIElement? {
        guard let value = attribute(kAXFocusedUIElementAttribute, of: app),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
