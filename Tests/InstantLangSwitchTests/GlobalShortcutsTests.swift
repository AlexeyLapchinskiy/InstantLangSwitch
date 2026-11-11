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
            let manager = GlobalShortcuts { _ in }
            defer { manager.stop() }

            guard manager.set(first, for: .switchLayout), manager.set(second, for: .correctSelection) else {
                throw XCTSkip("The test shortcuts are unavailable in this macOS session.")
            }
            XCTAssertFalse(manager.set(second, for: .switchLayout))
            XCTAssertTrue(manager.set(nil, for: .correctSelection))
            XCTAssertFalse(manager.set(first, for: .correctSelection))
        }
    }
}
