import AppKit
import ApplicationServices
import Carbon

enum SelectionCorrection {
    private enum Failure: LocalizedError {
        case accessibilityRequired
        case secureInput
        case unsupportedField
        case noSelection
        case incompatibleLayouts
        case unchanged
        case selectionChanged
        case couldNotReplace

        var errorDescription: String? {
            switch self {
            case .accessibilityRequired:
                return "Allow Instant Lang Switch in System Settings → Privacy & Security → Accessibility, then try again."
            case .secureInput:
                return "Text correction is unavailable while secure keyboard input is active."
            case .unsupportedField:
                return "Select text in an editable field that supports Accessibility text replacement."
            case .noSelection:
                return "Select the text you want to correct first."
            case .incompatibleLayouts:
                return "Choose two keyboard layouts that support physical-key conversion."
            case .unchanged:
                return "The selection has no characters that can be converted between these layouts."
            case .selectionChanged:
                return "The active selection changed. Select the text and try again."
            case .couldNotReplace:
                return "The active app couldn’t replace the selected text."
            }
        }
    }

    private static let messagingTimeout: Float = 0.3

    static func correct(source: Data, target: Data, application: NSRunningApplication?) throws {
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
        var settable: DarwinBoolean = false
        let selectedTextAttribute = kAXSelectedTextAttribute as CFString
        guard AXUIElementIsAttributeSettable(field, selectedTextAttribute, &settable) == .success,
              settable.boolValue else { throw Failure.unsupportedField }
        guard let selection = attribute(kAXSelectedTextAttribute, of: field) as? String, !selection.isEmpty else {
            throw Failure.noSelection
        }
        let range = attribute(kAXSelectedTextRangeAttribute, of: field)
        let corrected = try convert(selection, source: source, target: target)
        guard corrected != selection else { throw Failure.unchanged }

        guard !IsSecureEventInputEnabled() else { throw Failure.secureInput }
        guard let focused = focusedField(in: appElement), CFEqual(field, focused),
              attribute(kAXSelectedTextAttribute, of: field) as? String == selection else {
            throw Failure.selectionChanged
        }
        if let range {
            guard let currentRange = attribute(kAXSelectedTextRangeAttribute, of: field), CFEqual(range, currentRange) else {
                throw Failure.selectionChanged
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            throw Failure.selectionChanged
        }
        guard AXUIElementSetAttributeValue(field, selectedTextAttribute, corrected as CFString) == .success else {
            throw Failure.couldNotReplace
        }
    }

    static func convert(_ text: String, source: Data, target: Data) throws -> String {
        let keyboardType = UInt32(LMGetKbdType())
        let modifiers: [UInt32] = [0, UInt32(shiftKey >> 8)]
        guard source.count >= MemoryLayout<UCKeyboardLayout>.size,
              target.count >= MemoryLayout<UCKeyboardLayout>.size else { throw Failure.incompatibleLayouts }

        let candidates: [(Character, Character?)] = source.withUnsafeBytes { sourceBytes in
            target.withUnsafeBytes { targetBytes in
                let sourceLayout = sourceBytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
                let targetLayout = targetBytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
                var candidates: [(Character, Character?)] = []
                for modifier in modifiers {
                    for key in UInt16(0)...127 {
                        guard let character = translate(key, modifier: modifier, keyboardType: keyboardType, layout: sourceLayout)
                        else { continue }
                        let replacement = translate(key, modifier: modifier, keyboardType: keyboardType, layout: targetLayout)
                        candidates.append((character, replacement))
                    }
                }
                return candidates
            }
        }
        let mapping = characterMap(from: candidates)
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
