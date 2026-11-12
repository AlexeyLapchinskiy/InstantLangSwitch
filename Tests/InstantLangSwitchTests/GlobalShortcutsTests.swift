import AppKit
import Carbon
import XCTest
@testable import InstantLangSwitch

final class GlobalShortcutsTests: XCTestCase {
    func testRecordedShortcutIgnoresCapsLockAndRequiresACommandModifier() throws {
        let shortcut = try XCTUnwrap(Shortcut(
            keyCode: UInt16(kVK_ANSI_S),
            modifierFlags: [.control, .shift, .capsLock],
            keyTitle: "s"
        ))

        XCTAssertEqual(shortcut.title, "⌃⇧S")
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
        XCTAssertNil(Shortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: .shift, keyTitle: "s"))
        XCTAssertNil(Shortcut(keyCode: UInt16(kVK_Function), modifierFlags: .control, keyTitle: "Fn"))
    }

    func testConflictLeavesThePreviousShortcutRegistered() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let modifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
            let first = try XCTUnwrap(Shortcut(keyCode: UInt16(kVK_F18), modifierFlags: modifiers, keyTitle: "F18"))
            let second = try XCTUnwrap(Shortcut(keyCode: UInt16(kVK_F19), modifierFlags: modifiers, keyTitle: "F19"))
            let manager = GlobalShortcuts {}
            let other = GlobalShortcuts {}
            defer {
                manager.stop()
                other.stop()
            }

            guard manager.set(first), other.set(second) else {
                throw XCTSkip("The test shortcuts are unavailable in this macOS session.")
            }
            XCTAssertFalse(manager.set(second))
            XCTAssertTrue(other.set(nil))
            XCTAssertFalse(other.set(first))
            XCTAssertTrue(manager.set(second))
            XCTAssertTrue(other.set(first))
        }
    }

    func testUpgradingKeepsLayoutShortcutAndDiscardsRemovedShortcut() throws {
        let suite = "GlobalShortcutsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let layoutSwitch = try XCTUnwrap(Shortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: .control, keyTitle: "S"))
        let legacyShortcut = try XCTUnwrap(Shortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: .command, keyTitle: "D"))
        let saved = PreferencesConfiguration(favorites: ["en", "ru"], shortcuts: ["0": layoutSwitch, "1": legacyShortcut])
        defaults.set(try PropertyListEncoder().encode(saved), forKey: "switchingPreferences")

        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.configuration.favorites, saved.favorites)
        XCTAssertEqual(preferences.layoutShortcut, layoutSwitch)
        XCTAssertEqual(preferences.configuration.shortcuts, ["0": layoutSwitch])
        let stored = try XCTUnwrap(defaults.data(forKey: "switchingPreferences"))
        let upgraded = try PropertyListDecoder().decode(PreferencesConfiguration.self, from: stored)
        XCTAssertEqual(upgraded.shortcuts, ["0": layoutSwitch])
    }
}
