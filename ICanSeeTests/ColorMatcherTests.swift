import XCTest
@testable import ICanSee

final class ColorMatcherTests: XCTestCase {
    func testPureRedMatchesRed() {
        let m = ColorMatcher.match(red: 1, green: 0, blue: 0)
        XCTAssertEqual(m.name, "Red")
    }

    func testPureGreenMatchesGreen() {
        let m = ColorMatcher.match(red: 0, green: 1, blue: 0)
        XCTAssertEqual(m.name, "Lime")
    }

    func testPureBlueMatchesBlue() {
        let m = ColorMatcher.match(red: 0, green: 0, blue: 1)
        XCTAssertEqual(m.name, "Blue")
    }

    func testBlackAndWhite() {
        XCTAssertEqual(ColorMatcher.match(red: 0, green: 0, blue: 0).name, "Black")
        XCTAssertEqual(ColorMatcher.match(red: 1, green: 1, blue: 1).name, "White")
    }

    func testCompositionForOrange() {
        let m = ColorMatcher.match(red: 1, green: 0.5, blue: 0)
        XCTAssertEqual(m.name, "Orange")
        XCTAssertEqual(m.composition, "Red + Yellow")
    }

    func testChromaticBlueIsNotCalledGray() {
        // Washed-out blue that previously matched "Gray" because Lab
        // distance favored neutrals. Chroma penalty should keep us blue.
        let m = ColorMatcher.match(red: 0.30, green: 0.40, blue: 0.60)
        XCTAssertFalse(m.name.contains("Gray"))
        XCTAssertFalse(m.name == "Black")
        XCTAssertFalse(m.name == "White")
    }

    func testRedGreenDisambiguation() {
        // Classic deuteranopia confusion pair — the app must NOT call
        // these the same thing or it has no value to the user.
        let red = ColorMatcher.match(red: 0.80, green: 0.15, blue: 0.15)
        let green = ColorMatcher.match(red: 0.15, green: 0.60, blue: 0.20)
        XCTAssertNotEqual(red.name, green.name)
    }
}
