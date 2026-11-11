import XCTest
@testable import InstantLangSwitch

final class SetupProgressTests: XCTestCase {
    private let openedAt = Date(timeIntervalSinceReferenceDate: 1_000)

    func testRecognizesDoNothingWithoutOpeningKeyboardPreferences() {
        let progress = SetupProgress(
            inputMonitoringGranted: true, globeKeyAction: 0, keyboardOpenedAt: nil, now: openedAt
        )

        XCTAssertTrue(progress.keyboardDone)
        XCTAssertTrue(progress.isComplete)
    }

    func testDoesNotMarkKnownIncorrectSettingAsDoneAfterFallback() {
        let progress = SetupProgress(
            inputMonitoringGranted: true, globeKeyAction: 1,
            keyboardOpenedAt: openedAt, now: openedAt.addingTimeInterval(30)
        )

        XCTAssertFalse(progress.keyboardDone)
        XCTAssertFalse(progress.isComplete)
    }

    func testUnreadableSettingUsesFifteenSecondFallbackOnlyAfterOpeningPreferences() {
        for (startedAt, elapsed, expected) in [
            (nil as Date?, 60.0, false),
            (openedAt, 14.99, false),
            (openedAt, 15.0, true)
        ] {
            let progress = SetupProgress(
                inputMonitoringGranted: true, globeKeyAction: nil,
                keyboardOpenedAt: startedAt, now: openedAt.addingTimeInterval(elapsed)
            )

            XCTAssertEqual(progress.keyboardDone, expected)
        }
    }

    func testCompletingKeyboardStepDoesNotReplacePermissionGrant() {
        let progress = SetupProgress(
            inputMonitoringGranted: false, globeKeyAction: 0, keyboardOpenedAt: nil, now: openedAt
        )

        XCTAssertTrue(progress.keyboardDone)
        XCTAssertFalse(progress.isComplete)
    }
}
