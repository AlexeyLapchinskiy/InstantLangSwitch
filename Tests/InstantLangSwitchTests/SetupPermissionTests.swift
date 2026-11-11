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
            let setup = SetupWindowController(defaults: defaults) { reportedChanges.append($0) }
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
}
