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

    func testOpensSettingsOnlyAfterTenSecondsOfVisibleCompletedSetup() async throws {
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

            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 100)
            setup.refresh(inputMonitoringGranted: false, globeKeyAction: 0, uptime: 109)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 110)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 119)
            XCTAssertEqual(settingsOpened, 0)

            setup.close()
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 120)
            XCTAssertEqual(settingsOpened, 0)

            window.orderBack(nil)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 121)
            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 130.99)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(settingsOpened, 0)

            setup.refresh(inputMonitoringGranted: true, globeKeyAction: 0, uptime: 131)
            XCTAssertFalse(window.isVisible)
            XCTAssertEqual(settingsOpened, 1)
        }
    }
}
