import Carbon
import Foundation
import XCTest
@testable import InstantLangSwitch

final class SelectionCorrectionTests: XCTestCase {
    func testConvertsPhysicalKeysAndPreservesUnmappedText() throws {
        let russian = try layoutData(for: "com.apple.keylayout.Russian")
        let english = try layoutData(for: "com.apple.keylayout.US")

        let converted = try SelectionCorrection.convert("Руддщ 🌍\nцщкдв", first: russian, second: english, preferredDestination: .first)

        XCTAssertEqual(converted, "Hello 🌍\nworld")
    }

    func testSameLayoutPairAlsoConvertsInReverse() throws {
        let russian = try layoutData(for: "com.apple.keylayout.Russian")
        let english = try layoutData(for: "com.apple.keylayout.US")

        let converted = try SelectionCorrection.convert("Ghbdtn 🌍", first: russian, second: english, preferredDestination: .second)

        XCTAssertEqual(converted, "Привет 🌍")
    }

    func testUsesActiveDestinationForAmbiguousSameScriptLayouts() throws {
        let english = try layoutData(for: "com.apple.keylayout.US")
        let dvorak = try layoutData(for: "com.apple.keylayout.Dvorak")

        XCTAssertEqual(try SelectionCorrection.convert("b", first: english, second: dvorak, preferredDestination: .second), "x")
        XCTAssertEqual(try SelectionCorrection.convert("b", first: english, second: dvorak, preferredDestination: .first), "n")
        XCTAssertThrowsError(try SelectionCorrection.convert("b", first: english, second: dvorak))
    }

    func testResolvesTwoEnabledLayoutsOrTwoEnabledFavorites() throws {
        let english = InputSource(id: "en", name: "English", shortLabel: "EN", supportsTextCorrection: true)
        let russian = InputSource(id: "ru", name: "Russian", shortLabel: "RU", supportsTextCorrection: true)
        let ukrainian = InputSource(id: "uk", name: "Ukrainian", shortLabel: "UK", supportsTextCorrection: true)
        let ime = InputSource(id: "ime", name: "Input Method", shortLabel: "IM")

        let systemPair = try XCTUnwrap(SelectionCorrection.layoutPair(in: [english, russian], favorites: []))
        XCTAssertEqual([systemPair.first.id, systemPair.second.id], ["en", "ru"])
        let enabled = [english, russian, ukrainian, ime]
        let favoritePair = try XCTUnwrap(SelectionCorrection.layoutPair(in: enabled, favorites: ["en", "uk", "disabled"]))
        XCTAssertEqual([favoritePair.first.id, favoritePair.second.id], ["en", "uk"])
        XCTAssertNil(SelectionCorrection.layoutPair(in: enabled, favorites: []))
        XCTAssertNil(SelectionCorrection.layoutPair(in: enabled, favorites: ["en", "ime"]))
        XCTAssertNil(SelectionCorrection.layoutPair(in: enabled, favorites: ["en", "ru", "uk"]))
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
