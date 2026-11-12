import AppKit
import XCTest
@testable import InstantLangSwitch

final class SetupPermissionTests: XCTestCase {
    func testRefreshReflectsGrantAndRevocationWithoutReopeningWindow() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let suite = "SetupPermissionTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            var reportedChanges: [Bool] = []
            let setup = SetupWindowController(defaults: defaults, openSettings: {}) { reportedChanges.append($0) }
            let grid = try XCTUnwrap(setup.window?.contentView?.subviews.first as? NSGridView)
            let accessControls = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 0).contentView)
            let grant = try XCTUnwrap(accessControls.subviews.compactMap { $0 as? NSButton }.first)
            let granted = try XCTUnwrap(accessControls.subviews.compactMap { $0 as? NSTextField }.first)

            for hasAccess in [false, true, true, false] {
                setup.refresh(inputMonitoringGranted: hasAccess)
                XCTAssertEqual(grant.isHidden, hasAccess)
                XCTAssertEqual(granted.isHidden, !hasAccess)
            }

            XCTAssertEqual(reportedChanges, [false, true, false])
        }
    }

    func testFinishSetupRequiresBothChecksAndAButtonClick() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let suite = "SetupPermissionTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            var settingsOpened = 0
            let setup = SetupWindowController(defaults: defaults, openSettings: { settingsOpened += 1 }) { _ in }
            let window = try XCTUnwrap(setup.window)
            window.orderBack(nil)
            defer { setup.close() }

            let finish = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Finish setup" })
            setup.refresh(inputMonitoringGranted: false, globeKeyAction: 0)
            XCTAssertTrue(finish.isHidden)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 1)
            XCTAssertTrue(finish.isHidden)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 100)
            XCTAssertFalse(finish.isHidden)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 200)
            XCTAssertTrue(window.isVisible)
            XCTAssertFalse(defaults.bool(forKey: "initialSetupCompleted"))
            XCTAssertEqual(settingsOpened, 0)

            finish.performClick(nil)
            XCTAssertFalse(window.isVisible)
            XCTAssertTrue(defaults.bool(forKey: "initialSetupCompleted"))
            XCTAssertEqual(settingsOpened, 1)
        }
    }

    func testFnSwitchTestAutomaticallyWaitsForTheRequestedLayout() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let suite = "SetupPermissionTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let setup = SetupWindowController(defaults: defaults, openSettings: {}) { _ in }
            let window = try XCTUnwrap(setup.window)
            window.orderBack(nil)
            defer { setup.close() }

            let grid = try XCTUnwrap(window.contentView?.subviews.first as? NSGridView)
            let status = try XCTUnwrap(grid.cell(atColumnIndex: 1, rowIndex: 2).contentView as? NSTextField)
            let english = InputSource(id: "en", name: "English", shortLabel: "EN")
            let ukrainian = InputSource(id: "uk", name: "Ukrainian", shortLabel: "UK")

            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 100, currentInputSource: english)
            XCTAssertEqual(status.stringValue, "Not Tested")
            XCTAssertEqual(status.textColor, .systemRed)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 110, currentInputSource: ukrainian)
            XCTAssertEqual(status.stringValue, "Not Tested", "A change from another shortcut must not count.")

            setup.didRequestFnSwitch(from: ukrainian.id, to: english.id, uptime: 111)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 112, currentInputSource: ukrainian)
            XCTAssertEqual(status.stringValue, "Not Tested", "The requested layout has not been selected yet.")
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 113, currentInputSource: english)
            XCTAssertEqual(status.stringValue, "Tested")
            XCTAssertEqual(status.textColor, .systemGreen)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 130, currentInputSource: english)
            XCTAssertTrue(window.isVisible)
        }
    }
}
