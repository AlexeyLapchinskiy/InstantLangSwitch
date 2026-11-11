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

    func testFavoritesCycleInChosenOrderAndSkipUnavailableLayouts() {
        let available = ["US", "Polish", "Ukrainian"]
        let favorites = ["Ukrainian", "French", "US"]
        XCTAssertEqual(InputSourceCycle.nextID(in: available, favorites: favorites, current: "Polish"), "Ukrainian")
        XCTAssertEqual(InputSourceCycle.nextID(in: available, favorites: favorites, current: "Ukrainian"), "US")
        XCTAssertEqual(InputSourceCycle.nextID(in: available, favorites: favorites, current: "US"), "Ukrainian")
        XCTAssertEqual(InputSourceCycle.nextID(in: available, favorites: ["French"], current: "US"), "Polish")
    }

    func testOneFavoriteCanBeSelectedFromOutsideTheCycle() {
        let available = ["US", "Polish", "Ukrainian"]
        XCTAssertEqual(InputSourceCycle.nextID(in: available, favorites: ["US"], current: "Polish"), "US")
        XCTAssertNil(InputSourceCycle.nextID(in: available, favorites: ["US"], current: "US"))
    }
}
