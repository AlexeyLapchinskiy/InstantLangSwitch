import XCTest
@testable import InstantLangSwitch

final class InputSourceCycleTests: XCTestCase {
    func testCyclesFromTheCurrentSourceAndWraps() {
        let sources = ["US", "Polish", "Ukrainian"]
        XCTAssertEqual(InputSourceCycle.nextIndex(in: sources, current: "US"), 1)
        XCTAssertEqual(InputSourceCycle.nextIndex(in: sources, current: "Polish"), 2)
        XCTAssertEqual(InputSourceCycle.nextIndex(in: sources, current: "Ukrainian"), 0)
    }

    func testStartsAtFirstSourceWhenCurrentSourceIsMissing() {
        XCTAssertEqual(InputSourceCycle.nextIndex(in: ["US", "Polish"], current: "French"), 0)
    }

    func testSkipsSwitchingWhenOnlyOneSourceIsAvailable() {
        XCTAssertNil(InputSourceCycle.nextIndex(in: [], current: "US"))
        XCTAssertNil(InputSourceCycle.nextIndex(in: ["US"], current: "US"))
    }
}
