import Carbon
import Foundation
import XCTest
@testable import InstantLangSwitch

final class SelectionCorrectionTests: XCTestCase {
    func testConvertsPhysicalKeysAndPreservesUnmappedText() throws {
        let russian = try layoutData(for: "com.apple.keylayout.Russian")
        let english = try layoutData(for: "com.apple.keylayout.US")

        let converted = try SelectionCorrection.convert("Руддщ 🌍\nцщкдв", source: russian, target: english)

        XCTAssertEqual(converted, "Hello 🌍\nworld")
    }

    func testOmitsConflictingAndUnavailableDestinations() {
        let candidates: [(Character, Character?)] = [
            ("a", "ф"), ("a", "ф"), ("b", "и"), ("b", "б"), ("c", "с"), ("c", nil)
        ]

        XCTAssertEqual(SelectionCorrection.characterMap(from: candidates), ["a": "ф"])
    }

    private func layoutData(for id: String) throws -> Data {
        let filters = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = TISCreateInputSourceList(filters, true)?.takeRetainedValue() as? [TISInputSource]
        let source = try XCTUnwrap(sources?.first)
        let property = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData))
        return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    }
}
