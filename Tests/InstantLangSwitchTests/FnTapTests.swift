import XCTest
@testable import InstantLangSwitch

final class FnTapTests: XCTestCase {
    func testStandaloneTapSwitchesExactlyOnceOnRelease() {
        var tap = FnTap()
        XCTAssertFalse(tap.fnChanged(isDown: true, hasOtherModifiers: false))
        XCTAssertTrue(tap.fnChanged(isDown: false, hasOtherModifiers: false))
        XCTAssertFalse(tap.fnChanged(isDown: false, hasOtherModifiers: false))
    }

    func testChordDoesNotSwitchEvenAfterTheOtherKeyIsReleased() {
        var tap = FnTap()
        _ = tap.fnChanged(isDown: true, hasOtherModifiers: false)
        tap.otherKeyPressed()
        _ = tap.fnChanged(isDown: true, hasOtherModifiers: false)
        XCTAssertFalse(tap.fnChanged(isDown: false, hasOtherModifiers: false))
        _ = tap.fnChanged(isDown: true, hasOtherModifiers: false)
        XCTAssertTrue(tap.fnChanged(isDown: false, hasOtherModifiers: false))
    }

    func testFnPressedWithAnotherModifierDoesNotSwitch() {
        var tap = FnTap()
        _ = tap.fnChanged(isDown: true, hasOtherModifiers: true)
        XCTAssertFalse(tap.fnChanged(isDown: false, hasOtherModifiers: false))
    }

    func testResetDiscardsAnInterruptedPress() {
        var tap = FnTap()
        _ = tap.fnChanged(isDown: true, hasOtherModifiers: false)
        tap.reset()
        XCTAssertFalse(tap.fnChanged(isDown: false, hasOtherModifiers: false))
    }
}
